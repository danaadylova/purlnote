import 'dart:math';

import '../ravelry/ravelry_client.dart';
import 'local_database.dart';
import 'pending_edit.dart';

/// What the knitter chose for one conflicting field.
enum ConflictChoice {
  /// Keep the value edited on this phone.
  mine,

  /// Keep the value now on Ravelry.
  theirs,

  /// For notes: keep both texts, Ravelry's first.
  both,
}

/// How a round of sending went.
class SendResult {
  const SendResult({this.sent = 0, this.conflicts = 0, this.offline = false});

  final int sent;
  final int conflicts;

  /// True if sending stopped because Ravelry couldn't be reached.
  final bool offline;
}

/// Saves the knitter's edits on the phone and sends them to Ravelry.
///
/// Every edit shows on screen at once and is kept in the pending_edit table
/// until Ravelry accepts it, so editing works offline. Before sending, the
/// record is read from Ravelry again: if a field the knitter edited was also
/// changed on Ravelry since they started, the edit is held as a conflict for
/// them to resolve instead of overwriting the other change.
class Outbox {
  Outbox({required this.ravelry, required this.database, DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  final RavelryClient ravelry;
  final LocalDatabase database;
  final DateTime Function() _now;

  /// The longest wait between attempts when Ravelry keeps failing.
  static const maxBackoff = Duration(hours: 1);

  /// Saves an edit to a record and shows it on the phone right away.
  ///
  /// [changes] uses Ravelry's field names and is what gets sent.
  /// [displayFields] only updates what the phone shows (for example the
  /// status name that goes with a new status ID) and is never sent.
  Future<void> saveEdit({
    required RecordType type,
    required int ravelryId,
    required Map<String, Object?> changes,
    Map<String, Object?> displayFields = const {},
  }) async {
    final record = await database.record(type, ravelryId) ?? const {};
    final existing = await database.pendingEditFor(type, ravelryId);

    // The baseline is what each field looked like before the knitter first
    // touched it. A field already in a pending edit keeps its first baseline.
    // Fields the phone doesn't have yet are left out and never flagged.
    final baseline = <String, Object?>{...?existing?.baseline};
    for (final field in changes.keys) {
      if (!baseline.containsKey(field) && _hasField(record, field)) {
        baseline[field] = fieldValue(record, field);
      }
    }

    if (existing == null) {
      await database.insertPendingEdit(
        type: type,
        ravelryId: ravelryId,
        changes: changes,
        baseline: baseline,
        now: _now(),
      );
    } else {
      await database.updatePendingEdit(
        existing.id,
        changes: {...existing.changes, ...changes},
        baseline: baseline,
        // A new edit is worth another try even if the last one failed.
        state: existing.state == PendingEditState.failed ? PendingEditState.waiting : null,
        clearProblem: existing.state == PendingEditState.failed,
        clearNextAttempt: true,
      );
    }
    await database.updateRecord(type, ravelryId, {...changes, ...displayFields}, _now());
  }

  /// Sends every waiting edit, oldest first.
  ///
  /// Stops early if Ravelry can't be reached; the rest wait for next time.
  /// Throws SignInExpired if the knitter must sign in again.
  Future<SendResult> sendAll({required String username}) async {
    var sent = 0;
    var conflicts = 0;

    for (final edit in await database.pendingEdits()) {
      if (edit.state != PendingEditState.waiting) continue;
      final notBefore = edit.nextAttemptAt;
      if (notBefore != null && _now().isBefore(notBefore)) continue;

      try {
        final outcome = await _send(edit, username);
        if (outcome == _Outcome.sent) sent++;
        if (outcome == _Outcome.conflict) conflicts++;
      } on RavelryUnreachable {
        return SendResult(sent: sent, conflicts: conflicts, offline: true);
      } on RavelryError catch (error) {
        await _recordFailure(edit, error);
      }
    }
    return SendResult(sent: sent, conflicts: conflicts);
  }

  Future<_Outcome> _send(PendingEdit edit, String username) async {
    final path = recordPath(edit.recordType, username, edit.ravelryId);
    final theirs = await _fetch(edit.recordType, path);

    // A field is in conflict when Ravelry's value moved away from what the
    // knitter started from, to something other than what they chose.
    final conflicting = <String, Object?>{};
    for (final field in edit.changes.keys) {
      if (!edit.baseline.containsKey(field)) continue;
      final current = fieldValue(theirs, field);
      final changedOnRavelry = !sameValue(current, edit.baseline[field]);
      final differsFromMine = !sameValue(current, edit.changes[field]);
      if (changedOnRavelry && differsFromMine) conflicting[field] = current;
    }

    if (conflicting.isNotEmpty) {
      await database.updatePendingEdit(edit.id, state: PendingEditState.conflict, theirValues: conflicting);
      return _Outcome.conflict;
    }

    final reply = await ravelry.post(path, edit.changes);
    final saved = reply[_replyKey(edit.recordType)] as Map<String, dynamic>?;
    if (saved != null) await database.updateRecord(edit.recordType, edit.ravelryId, saved, _now());
    await database.deletePendingEdit(edit.id);
    return _Outcome.sent;
  }

  Future<Map<String, dynamic>> _fetch(RecordType type, String path) async {
    final reply = await ravelry.get(path);
    return reply.body![_replyKey(type)] as Map<String, dynamic>;
  }

  Future<void> _recordFailure(PendingEdit edit, RavelryError error) async {
    if (error.isTemporary) {
      // Wait 1, 2, 4, 8… minutes, up to an hour, before trying again.
      final attempts = edit.attempts + 1;
      final wait = Duration(minutes: pow(2, attempts - 1).toInt());
      await database.updatePendingEdit(
        edit.id,
        attempts: attempts,
        nextAttemptAt: _now().add(wait > maxBackoff ? maxBackoff : wait),
      );
      return;
    }
    final problem = switch (error.statusCode) {
      404 => 'This was deleted on Ravelry, so the change could not be saved.',
      403 => 'Ravelry did not allow this change.',
      _ => 'Ravelry refused this change (error ${error.statusCode}).',
    };
    await database.updatePendingEdit(edit.id, state: PendingEditState.failed, problem: problem);
  }

  /// Settles a conflict with the knitter's choice for each conflicting field,
  /// then queues what's left to send.
  Future<void> resolveConflict(PendingEdit edit, Map<String, ConflictChoice> choices) async {
    final changes = Map<String, Object?>.of(edit.changes);
    final baseline = Map<String, Object?>.of(edit.baseline);
    final showOnPhone = <String, Object?>{};

    for (final field in edit.conflictingFields) {
      final theirs = edit.theirValues[field];
      // Ravelry's value is now the starting point for this field.
      baseline[field] = theirs;
      switch (choices[field] ?? ConflictChoice.theirs) {
        case ConflictChoice.mine:
          break;
        case ConflictChoice.theirs:
          changes.remove(field);
          showOnPhone[field] = theirs;
        case ConflictChoice.both:
          changes[field] = combineNotes(theirs: theirs, mine: changes[field]);
      }
    }

    if (changes.isEmpty) {
      await database.deletePendingEdit(edit.id);
    } else {
      await database.updatePendingEdit(
        edit.id,
        changes: changes,
        baseline: baseline,
        theirValues: const {},
        state: PendingEditState.waiting,
        clearNextAttempt: true,
      );
    }
    await database.updateRecord(edit.recordType, edit.ravelryId, {...showOnPhone, ...changes}, _now());
  }

  /// Drops an edit that won't be sent and puts the fields back as they were.
  Future<void> discard(PendingEdit edit) async {
    await database.deletePendingEdit(edit.id);
    await database.updateRecord(edit.recordType, edit.ravelryId, edit.baseline, _now());
  }

  /// Puts edits that haven't reached Ravelry back on top of freshly synced
  /// records, so a sync never hides the knitter's unsent changes.
  Future<void> reapplyPendingEdits() async {
    for (final edit in await database.pendingEdits()) {
      if (edit.state == PendingEditState.failed) continue;
      await database.updateRecord(edit.recordType, edit.ravelryId, edit.changes, _now());
    }
  }

  /// Ravelry's address for one project or stash record.
  static String recordPath(RecordType type, String username, int id) {
    final user = Uri.encodeComponent(username);
    return switch (type) {
      RecordType.project => '/projects/$user/$id.json',
      RecordType.stash => '/people/$user/stash/$id.json',
      _ => throw ArgumentError('Only projects and stash can be edited, not ${type.name}.'),
    };
  }

  static String _replyKey(RecordType type) => type == RecordType.stash ? 'stash' : 'project';
}

enum _Outcome { sent, conflict }

/// A field's value in a Ravelry record. Most fields are sent and read under
/// the same name; stash status is sent as an ID but read back as an object.
Object? fieldValue(Map<String, dynamic> record, String field) {
  if (field == 'stash_status_id' && !record.containsKey(field)) {
    return (record['stash_status'] as Map<String, dynamic>?)?['id'];
  }
  return record[field];
}

bool _hasField(Map<String, dynamic> record, String field) {
  return record.containsKey(field) || (field == 'stash_status_id' && record.containsKey('stash_status'));
}

/// Compares two field values the way a knitter would: an empty string and no
/// value are the same, and surrounding spaces don't count.
bool sameValue(Object? a, Object? b) {
  Object? normal(Object? value) {
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    if (value is num) return value.toDouble();
    return value;
  }

  return normal(a) == normal(b);
}

/// "Keep both" for notes: Ravelry's text, a blank line, then the phone's.
String combineNotes({required Object? theirs, required Object? mine}) {
  final parts = [theirs, mine].whereType<String>().map((text) => text.trim()).where((text) => text.isNotEmpty);
  return parts.join('\n\n');
}
