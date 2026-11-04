import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:purlnote/app_session.dart';
import 'package:purlnote/auth/auth_service.dart';
import 'package:purlnote/auth/tokens.dart';
import 'package:purlnote/data/local_database.dart';
import 'package:purlnote/data/local_projects.dart';
import 'package:purlnote/reader/reader_store.dart';
import 'package:purlnote/reader/row_ruler.dart';
import 'package:purlnote/screens/welcome_screen.dart';
import 'package:purlnote/theme.dart';

import 'support/fakes.dart';

void main() {
  late LocalDatabase database;
  late List<http.Request> network;

  setUp(() async {
    database = await emptyDatabase();
    network = [];
  });

  tearDown(() => database.close());

  /// A session with no Ravelry account. Any network use is recorded.
  AppSession phoneOnlySession() {
    final recorder = MockClient((request) async {
      network.add(request);
      return http.Response('offline', 500);
    });
    final auth = AuthService(config: testConfig, tokenStore: MemoryTokenStore(), httpClient: recorder);
    return AppSession(
      auth: auth,
      database: database,
      sync: syncEngineFor(ravelryHttp: recorder, database: database, auth: auth),
    );
  }

  group('using Purlnote without Ravelry', () {
    test('first launch: the tour, then Welcome; after "start on this phone" it opens straight to the app', () async {
      final session = phoneOnlySession();
      await session.start();
      expect(session.stage, AppStage.tutorial);
      await session.finishTutorial();
      expect(session.stage, AppStage.signedOut);

      await session.startWithoutRavelry();
      expect(session.stage, AppStage.ready);
      expect(session.connected, isFalse);

      final nextLaunch = phoneOnlySession();
      await nextLaunch.start();
      expect(nextLaunch.stage, AppStage.ready);
      expect(network, isEmpty, reason: 'nothing leaves the phone without an account');
    });

    test('projects are kept and edited on the phone, never sent anywhere', () async {
      final session = phoneOnlySession();
      await session.startWithoutRavelry();

      final id = await session.createProject(name: 'Harbour Raglan');
      expect(id, isNegative);
      expect(session.projectById(id)!.isOnPhoneOnly, isTrue);
      expect(session.onTheNeedles.single.name, 'Harbour Raglan');

      await session.saveEdit(RecordType.project, id, {'progress': 30, 'notes': 'Using 4 mm'});
      await session.refresh();

      expect(session.projectById(id)!.progressPercent, 30);
      expect(session.projectById(id)!.notes, 'Using 4 mm');
      expect(session.pendingEdits, isEmpty);
      expect(network, isEmpty);
    });

    test('notes can\'t go to comments, but status names are offered', () async {
      final session = phoneOnlySession();
      await session.startWithoutRavelry();
      final id = await session.createProject(name: 'Socks');

      expect(session.canCommentOn(id), isFalse);
      expect(session.projectStatuses.map((s) => s.name), LocalProjects.statusNames);
    });

    testWidgets('the welcome screen offers starting on the phone first', (tester) async {
      late AppSession session;
      await tester.runAsync(() async => session = phoneOnlySession());
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(theme: buildPurlnoteTheme(), home: WelcomeScreen(session: session)));

      final start = tester.getTopLeft(find.text('Start on this phone'));
      final signIn = tester.getTopLeft(find.text('Sign in with Ravelry'));
      expect(start.dy, lessThan(signIn.dy));
    });
  });

  test('a project added to Ravelry keeps its counters and place', () async {
    final projects = LocalProjects(database);
    final reader = ReaderStore(database, clock: () => testNow);
    final id = await projects.create(name: 'Socks');
    final rows = (await reader.countersFor(id)).single;
    await reader.setCounterValue(rows.id, 12);
    await reader.savePage(1, 3, projectId: id);

    await projects.moveTo(id, 777);

    expect((await reader.countersFor(777)).single.value, 12);
    expect(await reader.savedPage(1, projectId: 777), 3);
    expect(await projects.all(), isEmpty);
  });

  group('row ruler', () {
    test('moves in small steps, a quarter of its height', () {
      const ruler = RulerPosition(page: 1, top: 0.5, height: 0.04, visible: true);
      final moved = ruler.movedBy(ruler.step, pageCount: 3);
      expect(moved.top, closeTo(0.51, 1e-9));
      expect(moved.page, 1);
    });

    test('continues onto the next page and back', () {
      const ruler = RulerPosition(page: 1, top: 0.955, height: 0.04, visible: true);
      final down = ruler.movedBy(0.01, pageCount: 2);
      expect(down.page, 2);
      expect(down.top, 0);
      final up = down.movedBy(-0.01, pageCount: 2);
      expect(up.page, 1);
      expect(up.top, closeTo(0.96, 1e-9));
    });

    test('stops at the start and end of the pattern', () {
      expect(const RulerPosition(page: 1, top: 0, height: 0.04, visible: true).movedBy(-0.01, pageCount: 1).top, 0);
      expect(
        const RulerPosition(page: 1, top: 0.96, height: 0.04, visible: true).movedBy(0.01, pageCount: 1).top,
        closeTo(0.96, 1e-9),
      );
    });

    test('comes back where it was left, per file and project', () async {
      final reader = ReaderStore(database);
      expect(await reader.savedRuler(1, projectId: 10), isNull);

      await reader.saveRuler(1, const RulerPosition(page: 2, top: 0.42, height: 0.05, visible: true), projectId: 10);

      final saved = await reader.savedRuler(1, projectId: 10);
      expect(saved!.page, 2);
      expect(saved.top, 0.42);
      expect(saved.height, 0.05);
      expect(saved.visible, isTrue);
      expect(await reader.savedRuler(1, projectId: 11), isNull);
    });
  });
}
