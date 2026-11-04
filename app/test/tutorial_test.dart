import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purlnote/screens/tutorial_screen.dart';
import 'package:purlnote/theme.dart';

void main() {
  Future<void> showTour(WidgetTester tester, void Function() onDone) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(theme: buildPurlnoteTheme(), home: TutorialScreen(onDone: onDone)));
  }

  testWidgets('Next walks through four pages and the last one says Get started', (tester) async {
    var done = 0;
    await showTour(tester, () => done++);

    expect(find.text('Your patterns, always with you'), findsOneWidget);
    for (final title in ['Mark it up', 'Never lose your row', 'One step at a time']) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('Next'), findsNothing);

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
