import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purlnote/data/local_database.dart';
import 'package:purlnote/library/library_models.dart';
import 'package:purlnote/reader/awake_timer.dart';
import 'package:purlnote/reader/reader_store.dart';

import 'support/fakes.dart';

void main() {
  late LocalDatabase database;
  late ReaderStore store;

  setUp(() async {
    database = await emptyDatabase();
    store = ReaderStore(database, clock: () => testNow);
  });

  tearDown(() => database.close());

  group('reading spots', () {
    test('two projects on the same pattern keep separate spots', () async {
      await store.savePage(1, 4, projectId: 10);
      await store.savePage(1, 7, projectId: 11);

      expect(await store.savedPage(1, projectId: 10), 4);
      expect(await store.savedPage(1, projectId: 11), 7);
      expect(await store.savedPage(1), isNull, reason: 'reading outside a project has its own spot');
    });

    test('a project reopens the file it had open last', () async {
      final files = [
        const PatternFile(id: 1, patternKey: 'volume:70', label: 'Pattern', sortOrder: 0),
        const PatternFile(id: 2, patternKey: 'volume:70', label: 'Charts', sortOrder: 1),
      ];
      expect(await store.lastFileFor(10, files), isNull);

      await store.savePage(1, 3, projectId: 10);
      final later = ReaderStore(database, clock: () => testNow.add(const Duration(minutes: 5)));
      await later.savePage(2, 2, projectId: 10);

      expect(await store.lastFileFor(10, files), 2);
    });
  });

  group('annotations', () {
    test('marks are kept per file fingerprint, in page fractions', () async {
      await store.addAnnotation(
        fileSha256: 'abc',
        page: 2,
        kind: AnnotationKind.highlight,
        points: const [Offset(0.1, 0.2), Offset(0.9, 0.25)],
      );
      final noteId = await store.addAnnotation(
        fileSha256: 'abc',
        page: 3,
        kind: AnnotationKind.note,
        points: const [Offset(0.123456, 0.5)],
        text: 'Switched to 3.75 mm',
      );

      final marks = await store.annotationsFor('abc');
      expect(marks.map((m) => m.kind), [AnnotationKind.highlight, AnnotationKind.note]);
      expect(marks.first.points, const [Offset(0.1, 0.2), Offset(0.9, 0.25)]);
      expect(marks.last.points.single.dx, 0.1235, reason: 'stored to four decimal places');
      expect(await store.annotationsFor('other-file'), isEmpty);

      await store.updateNoteText(noteId, 'Switched to 3.5 mm');
      expect((await store.annotationsFor('abc')).last.text, 'Switched to 3.5 mm');

      await store.deleteAnnotation(noteId);
      expect(await store.annotationsFor('abc'), hasLength(1));
    });
  });

  group('counters', () {
    test('a project starts with a row counter', () async {
      final counters = await store.countersFor(10);
      expect(counters.single.label, 'Rows');
      expect(counters.single.value, 0);
      expect(counters.single.isRepeat, isFalse);
    });

    test('rows never go below zero', () async {
      final rows = (await store.countersFor(10)).single;
      await store.setCounterValue(rows.id, -1);
      expect((await store.countersFor(10)).single.value, 0);
    });

    test('a repeat counter follows the row counter from where it started', () async {
      final rows = (await store.countersFor(10)).single;
      await store.setCounterValue(rows.id, 12);
      await store.addRepeatCounter(projectId: 10, label: 'Decrease every 6 rows', everyNRows: 6, startRow: 12, totalRepeats: 3);

      final repeat = (await store.countersFor(10)).last;
      expect(repeat.repeatsDone(12), 0);
      expect(repeat.rowsUntilNext(12), 6);
      expect(repeat.repeatsDone(20), 1);
      expect(repeat.rowsUntilNext(20), 4);
      expect(repeat.repeatsDone(60), 3, reason: 'never more than the total');
    });
  });

  group('screen awake', () {
    test('stays on for the chosen minutes after the last touch', () {
      fakeAsync((time) {
        final calls = <bool>[];
        final timer = AwakeTimer(setScreenOn: (on) async => calls.add(on));

        timer.start(10);
        expect(calls, [true]);

        time.elapse(const Duration(minutes: 9));
        timer.touched();
        time.elapse(const Duration(minutes: 9));
        expect(calls, [true, true], reason: 'the touch restarted the timer');

        time.elapse(const Duration(minutes: 2));
        expect(calls.last, isFalse);
      });
    });

    test('"while open" never times out, and leaving lets the screen sleep', () {
      fakeAsync((time) {
        final calls = <bool>[];
        final timer = AwakeTimer(setScreenOn: (on) async => calls.add(on));

        timer.start(AwakeTimer.whileOpen);
        time.elapse(const Duration(hours: 5));
        expect(calls, [true]);

        timer.stop();
        expect(calls, [true, false]);
      });
    });

    test('"off" leaves it to the phone', () {
      final calls = <bool>[];
      AwakeTimer(setScreenOn: (on) async => calls.add(on)).start(AwakeTimer.off);
      expect(calls, [false]);
    });
  });
}
