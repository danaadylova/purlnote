import 'package:flutter_test/flutter_test.dart';
import 'package:purlnote/data/local_database.dart';
import 'package:purlnote/notes/notes_backup.dart';
import 'package:purlnote/notes/project_comments.dart';
import 'package:purlnote/ravelry/ravelry_client.dart';
import 'package:purlnote/reader/reader_store.dart';

import 'support/fake_ravelry.dart';
import 'support/fakes.dart';

void main() {
  late FakeRavelry ravelry;
  late LocalDatabase database;
  late RavelryClient client;

  setUp(() async {
    ravelry = FakeRavelry();
    database = await emptyDatabase();
    client = RavelryClient(baseUrl: testConfig.ravelryApiUrl, auth: await signedInAuth(), httpClient: ravelry.client);
  });

  tearDown(() => database.close());

  group('note tags', () {
    test('say where in the pattern a note was made', () {
      expect(const NoteTag(page: 2, fileLabel: 'Charts', row: 31).text, '[Charts p.2 · row 31]');
      expect(const NoteTag(page: 4).text, '[p.4]');
      expect(const NoteTag(page: 4, row: 0).text, '[p.4]', reason: 'a counter at zero says nothing useful');
    });

    test('can be read back from a comment', () {
      final tag = NoteTag.parse('[Charts p.2 · row 31] Switched to 3.75 mm');
      expect(tag!.fileLabel, 'Charts');
      expect(tag.page, 2);
      expect(tag.row, 31);
      expect(NoteTag.parse('[p.4] Note')!.fileLabel, isNull);
      expect(NoteTag.parse('Just a comment'), isNull);
    });

    test('comment HTML from Ravelry becomes plain text', () {
      expect(plainText('<p>[p.2] K2tog &amp; ssk</p>'), '[p.2] K2tog & ssk');
    });
  });

  group('project comments', () {
    late ProjectComments comments;

    setUp(() => comments = ProjectComments(ravelry: client, database: database, clock: () => testNow));

    test('a note waits on this device, then posts once', () async {
      await comments.queue(projectId: 10, body: '[p.2] Switched to 3.75 mm', annotationId: 1);
      expect((await comments.unsent(10)).single.state, CommentState.waiting);
      expect(ravelry.commentsPosted, 0);

      expect(await comments.sendAll(username: 'unraveled-makes'), 1);
      expect(await comments.sendAll(username: 'unraveled-makes'), 0);

      expect(ravelry.commentsPosted, 1);
      expect(await comments.unsent(10), isEmpty);
      final posted = await comments.forAnnotation(1);
      expect(posted!.state, CommentState.posted);
      expect(posted.postedCommentId, 5000);
    });

    test('if the connection drops after posting, it is not posted twice', () async {
      ravelry.dropConnectionAfterNextComment = true;
      await comments.queue(projectId: 10, body: '[p.2] Switched to 3.75 mm');

      expect(await comments.sendAll(username: 'unraveled-makes'), 0);
      expect(ravelry.commentsPosted, 1);

      // Next sync finds the comment already there instead of posting again.
      expect(await comments.sendAll(username: 'unraveled-makes'), 1);
      expect(ravelry.commentsPosted, 1);
      expect(await comments.unsent(10), isEmpty);
    });

    test('a refused comment is reported and can be cancelled', () async {
      ravelry.commentStatus = 403;
      final id = await comments.queue(projectId: 10, body: 'Note');

      await comments.sendAll(username: 'unraveled-makes');
      final failed = (await comments.unsent(10)).single;
      expect(failed.state, CommentState.failed);
      expect(failed.problem, contains('didn\'t allow'));

      await comments.cancel(id);
      expect(await comments.unsent(10), isEmpty);
    });

    test('loads the project\'s comments and deletes one', () async {
      await comments.queue(projectId: 10, body: '[p.2] Note');
      await comments.sendAll(username: 'unraveled-makes');

      final loaded = await comments.load(username: 'unraveled-makes', projectId: 10);
      expect(loaded.single.body, '[p.2] Note');
      expect(loaded.single.author, 'unraveled-makes');

      await comments.deletePosted(loaded.single.id);
      expect(await comments.load(username: 'unraveled-makes', projectId: 10), isEmpty);
    });
  });

  group('notes backup', () {
    late NotesBackup backup;
    late ReaderStore reader;

    setUp(() {
      backup = NotesBackup(ravelry: client, database: database);
      reader = ReaderStore(database, clock: () => testNow);
    });

    Future<void> addSomeNotes() async {
      await reader.addAnnotation(
        fileSha256: 'a' * 64,
        page: 2,
        kind: AnnotationKind.note,
        points: const [Offset(0.5, 0.5)],
        text: 'Switched to 3.75 mm',
      );
      await reader.addAnnotation(
        fileSha256: 'a' * 64,
        page: 3,
        kind: AnnotationKind.ink,
        points: const [Offset(0.1, 0.1), Offset(0.2, 0.2)],
      );
      final rows = (await reader.countersFor(10)).single;
      await reader.setCounterValue(rows.id, 31);
    }

    test('backs up notes and counters, but not pen strokes', () async {
      await addSomeNotes();
      await backup.backUp();

      final fileKey = NotesBackup.fileKey('a' * 64);
      expect(ravelry.appData['pn_index'], fileKey);
      expect(ravelry.appData[fileKey], contains('Switched to 3.75 mm'));
      expect(ravelry.appData[fileKey], isNot(contains('"ink"')));
      expect(ravelry.appData['pn_counters'], contains('31'));
    });

    test('only writes what changed', () async {
      await addSomeNotes();
      expect(await backup.backUp(), greaterThan(0));
      expect(await backup.backUp(), 0);
    });

    test('restores onto an empty phone without touching what is already there', () async {
      await addSomeNotes();
      await backup.backUp();

      final freshPhone = await emptyDatabase();
      final freshBackup = NotesBackup(ravelry: client, database: freshPhone);
      expect(await freshBackup.restore(), 1);

      final freshReader = ReaderStore(freshPhone);
      expect((await freshReader.annotationsFor('a' * 64)).single.text, 'Switched to 3.75 mm');
      expect((await freshReader.countersFor(10)).single.value, 31);

      expect(await freshBackup.restore(), 0, reason: 'nothing is added twice');
      await freshPhone.close();
    });

    test('turning it off deletes the backup from Ravelry', () async {
      await addSomeNotes();
      await backup.backUp();
      expect(ravelry.appData, isNotEmpty);

      await backup.setEnabled(false);

      expect(ravelry.appData, isEmpty);
      expect(await backup.backUp(), 0);
    });
  });
}
