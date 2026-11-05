import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purlnote/screens/tutorial_screen.dart';
import 'package:purlnote/theme.dart';

import 'support/fakes.dart';

void main() {
  Future<void> showTour(WidgetTester tester, void Function() onDone) async {
    useScreenSize(tester, const Size(430, 932));
    await tester.pumpWidget(MaterialApp(theme: buildPurlnoteTheme(), home: TutorialScreen(onDone: onDone)));
  }

  testWidgets('Next walks from the hello page through four more, and the last says Get started', (tester) async {
    var done = 0;
    await showTour(tester, () => done++);

    expect(find.text('Hello!'), findsOneWidget);
    expect(find.text('– Dana'), findsOneWidget);
    for (final title in ['Your patterns, always with you', 'Mark it up', 'Never lose your row', 'One step at a time']) {
      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
    }
    expect(find.widgetWithText(FilledButton, 'Next'), findsNothing);

    await tester.tap(find.text('Get started'));
    expect(done, 1);
  });

  testWidgets('Skip leaves from the first page', (tester) async {
    var done = 0;
    await showTour(tester, () => done++);
    await tester.tap(find.text('Skip'));
    expect(done, 1);
  });
}
