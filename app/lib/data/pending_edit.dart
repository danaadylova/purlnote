import 'dart:convert';

import 'local_database.dart';

/// Where a pending edit stands.
enum PendingEditState {
  /// Saved on the phone, waiting to be sent to Ravelry.
  waiting,

  /// The record changed on Ravelry too; the knitter must choose, field by
  /// field, which version to keep.
  conflict,

  /// Ravelry refused it for good (for example, the project was deleted).
  failed,
}

/// One saved change to a Ravelry record that hasn't reached Ravelry yet.
///
/// Edits to the same record are merged into one pending edit, so a project
/// edited three times offline is sent as one update.
class PendingEdit {
  const PendingEdit({
    required this.id,
    required this.recordType,
    required this.ravelryId,
    required this.changes,
    required this.baseline,
    required this.state,
    required this.attempts,
    required this.createdAt,
    this.nextAttemptAt,
    this.problem,
    this.theirValues = const {},
  });

  factory PendingEdit.fromRow(Map<String, Object?> row) {
    Map<String, Object?> decode(Object? text) =>
        text == null ? {} : (jsonDecode(text as String) as Map<String, dynamic>);
    return PendingEdit(
      id: row['id'] as int,
      recordType: RecordType.values.byName(row['record_type'] as String),
      ravelryId: row['ravelry_id'] as int,
      changes: decode(row['changes']),
      baseline: decode(row['baseline']),
      theirValues: decode(row['their_values']),
      state: PendingEditState.values.byName(row['state'] as String),
      attempts: row['attempts'] as int,
      nextAttemptAt: _time(row['next_attempt_at']),
      problem: row['problem'] as String?,
      createdAt: _time(row['created_at'])!,
    );
  }

  final int id;
  final RecordType recordType;
  final int ravelryId;

  /// The new value for each edited field, using Ravelry's field names.
  final Map<String, Object?> changes;

  /// Each edited field's value when the knitter started editing. If Ravelry's
  /// value is different when we send, someone changed it elsewhere.
  final Map<String, Object?> baseline;

  /// Ravelry's current values for conflicting fields (only in [PendingEditState.conflict]).
  final Map<String, Object?> theirValues;

  final PendingEditState state;

  /// How many times sending failed for a passing reason (Ravelry busy).
  final int attempts;

  /// Don't try again before this time. Null means "now".
  final DateTime? nextAttemptAt;

  /// Why it failed, in words the knitter can read.
  final String? problem;
  final DateTime createdAt;

  /// The fields that changed on both sides.
  Iterable<String> get conflictingFields => theirValues.keys;
}

DateTime? _time(Object? millis) => millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis as int);
