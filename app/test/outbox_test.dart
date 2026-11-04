import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:purlnote/data/local_database.dart';
import 'package:purlnote/data/outbox.dart';
import 'package:purlnote/data/pending_edit.dart';
import 'package:purlnote/data/sync_engine.dart';
import 'package:purlnote/ravelry/ravelry_client.dart';

import 'support/fake_ravelry.dart';
import 'support/fakes.dart';

void main() {
  late FakeRavelry ravelry;
  late LocalDatabase database;
  late SyncEngine engine;
  late DateTime now;

  setUp(() async {
    ravelry = FakeRavelry();
    database = await emptyDatabase();
    now = testNow;
    engine = syncEngineFor(
      ravelryHttp: ravelry.client,
      database: database,
      auth: await signedInAuth(),
      clock: () => now,
    );
    // Start like the app does after sign-in, with the Harbour Raglan page
    // opened so its notes and size are on the phone.
    await engine.syncEverything();
    await engine.refreshRecord(RecordType.project, 10);
    ravelry.requests.clear();
  });

  tearDown(() => database.close());

  Outbox outbox() => engine.outbox;
  Future<Map<String, dynamic>?> storedProject(int id) => database.record(RecordType.project, id);

  group('saving an edit', () {
    test('shows on the phone at once and waits to be sent', () async {
      await outbox().saveEdit(type: RecordType.project, ravelryId: 10, changes: {'progress': 55});

      expect((await storedProject(10))!['progress'], 55);
      final pending = (await database.pendingEdits()).single;
      expect(pending.state, PendingEditState.waiting);
      expect(pending.baseline, {'progress': 40});
      expect(ravelry.requests, isEmpty, reason: 'saving never waits on the network');
    });

    test('is sent on the next sync with only the changed fields', () async {
      await outbox().saveEdit(type: RecordType.project, ravelryId: 10, changes: {'progress': 55});

      await engine.syncEverything();

      expect(ravelry.updatesSent, [
        {'progress': 55},
      ]);
      expect(await database.pendingEdits(), isEmpty);
      expect(ravelry.projects.first['progress'], 55);
    });

    test('several edits to one project are sent as one update', () async {
      await outbox().saveEdit(type: RecordType.project, ravelryId: 10, changes: {'progress': 50});
      await outbox().saveEdit(type: RecordType.project, ravelryId: 10, changes: {'progress': 60, 'size': 'L'});

      final pending = (await database.pendingEdits()).single;
      expect(pending.changes, {'progress': 60, 'size': 'L'});
      expect(pending.baseline, {'progress': 40, 'size': 'M'}, reason: 'the first baseline is kept');

      await engine.syncEverything();
      expect(ravelry.updatesSent, [
        {'progress': 60, 'size': 'L'},
      ]);
    });

    test('a stash status is sent as an ID and compared with Ravelry\'s status object', () async {
      await outbox().saveEdit(type: RecordType.stash, ravelryId: 30, changes: {'stash_status_id': 2});

      expect((await database.pendingEdits()).single.baseline, {'stash_status_id': 1});
      await engine.syncEverything();
      expect(ravelry.updatesSent, [
        {'stash_status_id': 2},
      ]);
    });
  });

  group('when Ravelry can\'t take it yet', () {
    test('offline, the edit waits and stays on screen', () async {
      await outbox().saveEdit(type: RecordType.project, ravelryId: 10, changes: {'progress': 55});
      final offline = syncEngineFor(
        ravelryHttp: MockClient((_) async => throw http.ClientException('offline')),
        database: database,
        auth: await signedInAuth(),
      );

      await expectLater(offline.syncEverything(), throwsA(isA<RavelryUnreachable>()));

      expect((await database.pendingEdits()).single.state, PendingEditState.waiting);
      expect((await storedProject(10))!['progress'], 55);
    });

    test('a busy Ravelry means waiting longer each time, and synced lists keep the edit', () async {
      ravelry.updateStatus = 503;
      await outbox().saveEdit(type: RecordType.project, ravelryId: 10, changes: {'progress': 55});

      await engine.syncEverything();
      var pending = (await database.pendingEdits()).single;
      expect(pending.attempts, 1);
      expect(pending.nextAttemptAt, testNow.add(const Duration(minutes: 1)));
      // The project list was synced from Ravelry, but the unsent edit is laid back on top.
      expect((await storedProject(10))!['progress'], 55);

      now = testNow.add(const Duration(minutes: 2));
      await engine.syncEverything();
      pending = (await database.pendingEdits()).single;
      expect(pending.attempts, 2);
      expect(pending.nextAttemptAt, now.add(const Duration(minutes: 2)));
    });

    test('a deleted project is reported, and "undo" puts the old values back', () async {
      await outbox().saveEdit(type: RecordType.project, ravelryId: 10, changes: {'progress': 55});
      ravelry.updateStatus = 404;

      await engine.syncEverything();
      final failed = (await database.pendingEdits()).single;
      expect(failed.state, PendingEditState.failed);
      expect(failed.problem, contains('deleted on Ravelry'));

      await outbox().discard(failed);
      expect(await database.pendingEdits(), isEmpty);
      expect((await storedProject(10))!['progress'], 40);
    });
  });

  group('conflicts', () {
    test('a field changed on Ravelry since editing began is held, not overwritten', () async {
      await outbox().saveEdit(type: RecordType.project, ravelryId: 10, changes: {'notes': 'Switched to 3.75mm.'});
      ravelry.editProjectOnWebsite(10, {'notes': 'Cast on with 4mm. Blocked the swatch.'});

      await engine.syncEverything();

      expect(ravelry.updatesSent, isEmpty);
      final conflict = (await database.pendingEdits()).single;
      expect(conflict.state, PendingEditState.conflict);
      expect(conflict.theirValues, {'notes': 'Cast on with 4mm. Blocked the swatch.'});
    });

    test('a change on Ravelry to a different field is not a conflict', () async {
      await outbox().saveEdit(type: RecordType.project, ravelryId: 10, changes: {'notes': 'Switched to 3.75mm.'});
      ravelry.editProjectOnWebsite(10, {'size': 'L'});

      await engine.syncEverything();

      expect(ravelry.updatesSent, [
        {'notes': 'Switched to 3.75mm.'},
      ]);
      expect(ravelry.projects.first['size'], 'L');
    });

    test('the same change made in both places is not a conflict', () async {
      await outbox().saveEdit(type: RecordType.project, ravelryId: 10, changes: {'progress': 70});
      ravelry.editProjectOnWebsite(10, {'progress': 70});

      await engine.syncEverything();
      expect(await database.pendingEdits(), isEmpty);
    });

    test('"keep both" sends Ravelry\'s notes followed by the phone\'s', () async {
      await outbox().saveEdit(type: RecordType.project, ravelryId: 10, changes: {'notes': 'Switched to 3.75mm.'});
      ravelry.editProjectOnWebsite(10, {'notes': 'Blocked the swatch.'});
      await engine.syncEverything();

      final conflict = (await database.pendingEdits()).single;
      await outbox().resolveConflict(conflict, {'notes': ConflictChoice.both});
      await engine.syncEverything();

      expect(ravelry.projects.first['notes'], 'Blocked the swatch.\n\nSwitched to 3.75mm.');
      expect(await database.pendingEdits(), isEmpty);
    });

    test('choosing Ravelry\'s version drops the phone\'s change for that field only', () async {
      await outbox().saveEdit(
        type: RecordType.project,
        ravelryId: 10,
        changes: {'notes': 'Switched to 3.75mm.', 'progress': 60},
      );
      ravelry.editProjectOnWebsite(10, {'notes': 'Blocked the swatch.'});
      await engine.syncEverything();

      final conflict = (await database.pendingEdits()).single;
      await outbox().resolveConflict(conflict, {'notes': ConflictChoice.theirs});

      expect((await storedProject(10))!['notes'], 'Blocked the swatch.');
      await engine.syncEverything();
      expect(ravelry.updatesSent, [
        {'progress': 60},
      ]);
    });
  });

  test('empty text and no value count as the same', () {
    expect(sameValue('', null), isTrue);
    expect(sameValue(' M ', 'M'), isTrue);
    expect(sameValue(40, 40.0), isTrue);
    expect(sameValue('M', 'L'), isFalse);
  });
}
