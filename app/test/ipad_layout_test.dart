import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purlnote/app_session.dart';
import 'package:purlnote/data/local_database.dart';
import 'package:purlnote/screens/home_screen.dart';
import 'package:purlnote/theme.dart';

import 'support/fake_ravelry.dart';
import 'support/fakes.dart';

void main() {
  /// A session that has finished its first sync from a fake Ravelry.
  Future<AppSession> syncedSession(LocalDatabase database) async {
    final ravelry = FakeRavelry();
    final auth = await signedInAuth();
    final session = AppSession(
      auth: auth,
      database: database,
      sync: syncEngineFor(ravelryHttp: ravelry.client, database: database, auth: auth),
    );
    await session.start();
    session.finishFirstSync();
    return session;
  }

  Future<void> showHome(WidgetTester tester, Size size) async {
    useScreenSize(tester, size);
    late AppSession session;
    late LocalDatabase database;
    await tester.runAsync(() async {
      database = await emptyDatabase();
      session = await syncedSession(database);
    });
    addTearDown(() => tester.runAsync(database.close));
    await tester.pumpWidget(MaterialApp(theme: buildPurlnoteTheme(), home: HomeScreen(session: session)));
    // Let the project cards look up their patterns and counters.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
  }

  testWidgets('an iPad gets the side rail, and stash and queue beside the projects', (tester) async {
    await showHome(tester, const Size(1376, 1032));

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.bySemanticsLabel('Library'), findsOneWidget, reason: 'the rail, and no tab bar as well');

    // Everything on the Notebook fits on one screen, side by side.
    expect(find.text('Harbour Raglan'), findsOneWidget);
    expect(find.text('Petal Drop Socks'), findsOneWidget);
    expect(find.text('Queue · 1'), findsOneWidget);
    final project = tester.getCenter(find.text('Harbour Raglan'));
    final queue = tester.getCenter(find.text('Queue · 1'));
    expect(queue.dx, greaterThan(project.dx), reason: 'the queue sits in the column on the right');

    // No dots: the cards sit in a row instead of being swiped one by one.
    expect(find.bySemanticsLabel(RegExp('Swipe for more')), findsNothing);
  });

  testWidgets('an iPhone keeps the tabs along the bottom', (tester) async {
    await showHome(tester, const Size(430, 932));

    expect(find.byType(NavigationRail), findsNothing);
    expect(find.bySemanticsLabel('Library'), findsOneWidget, reason: 'the floating tab bar');
    expect(find.text('Harbour Raglan'), findsOneWidget);
  });

  testWidgets('a big iPhone held sideways keeps the phone layout', (tester) async {
    await showHome(tester, const Size(932, 430));

    expect(find.byType(NavigationRail), findsNothing);
    expect(find.bySemanticsLabel('Library'), findsOneWidget);
  });

  testWidgets('the rail switches sections on an iPad', (tester) async {
    await showHome(tester, const Size(1376, 1032));

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.text('Send feedback'), findsOneWidget);
    // Apple asks for the privacy policy to be reachable inside the app.
    expect(find.text('Privacy policy'), findsOneWidget);
  });
}
