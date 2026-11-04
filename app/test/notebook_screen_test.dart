import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purlnote/app_session.dart';
import 'package:purlnote/data/local_database.dart';
import 'package:purlnote/screens/notebook_screen.dart';
import 'package:purlnote/screens/welcome_screen.dart';
import 'package:purlnote/theme.dart';

import 'support/fake_ravelry.dart';
import 'support/fakes.dart';

void main() {
  /// A session that has finished its first sync from [ravelry].
  Future<AppSession> syncedSession(FakeRavelry ravelry, LocalDatabase database) async {
    final auth = await signedInAuth();
    final session = AppSession(
      auth: auth,
      database: database,
      sync: syncEngineFor(ravelryHttp: ravelry.client, database: database, auth: auth),
    );
    // A first sign-in waits on the first-sync screen until the knitter taps
    // "Open my notebook".
    await session.start();
    expect(session.stage, AppStage.firstSync);
    expect(session.canLeaveFirstSync, isTrue);
    session.finishFirstSync();
    return session;
  }

  Widget inApp(Widget screen) => MaterialApp(theme: buildPurlnoteTheme(), home: screen);

  testWidgets('the Notebook shows projects on the needles, stash, queue and the rest', (tester) async {
    late AppSession session;
    late LocalDatabase database;
    await tester.runAsync(() async {
      database = await emptyDatabase();
      session = await syncedSession(FakeRavelry(), database);
    });
    expect(session.stage, AppStage.ready);

    await tester.pumpWidget(inApp(NotebookScreen(session: session)));

    expect(find.text('On the needles · 1'), findsOneWidget);
    expect(find.text('Harbour Raglan'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);
    expect(find.text('Stash'), findsOneWidget);
    expect(find.text('1 yarn'), findsOneWidget);
    expect(find.text('Queue · 1'), findsOneWidget);
    expect(find.text('Fennel Socks'), findsOneWidget);
    expect(find.text('Other projects · 1'), findsOneWidget);
    expect(find.text('Finished'), findsOneWidget);

    await tester.runAsync(database.close);
  });

  testWidgets('Welcome offers Ravelry sign-in and shows a sign-in problem', (tester) async {
    late AppSession session;
    late LocalDatabase database;
    await tester.runAsync(() async {
      database = await emptyDatabase();
      session = await syncedSession(FakeRavelry(), database);
    });
    session.signInProblem = 'Your Ravelry sign-in ended. Please sign in again.';
    // A phone-sized screen tall enough to show the whole welcome screen.
    await tester.binding.setSurfaceSize(const Size(430, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(inApp(WelcomeScreen(session: session)));

    expect(find.text('Sign in with Ravelry'), findsOneWidget);
    expect(find.text('Your Ravelry sign-in ended. Please sign in again.'), findsOneWidget);

    await tester.runAsync(database.close);
  });
}
