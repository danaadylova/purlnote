import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purlnote/reader/counters_bar.dart';
import 'package:purlnote/reader/row_ruler.dart';

void main() {
  Widget floating(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

  testWidgets('the floating row counter counts up and down', (tester) async {
    var rows = 14;
    await tester.pumpWidget(floating(CompactRowCounter(rows: rows, onChanged: (value) => rows = value)));

    expect(find.text('14'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add));
    expect(rows, 15);
    await tester.tap(find.byIcon(Icons.remove));
    expect(rows, 13);
  });

  testWidgets('the ruler is just a band: the rest of the page is not dimmed', (tester) async {
    double? grabbed;
    await tester.pumpWidget(
      floating(
        SizedBox(
          width: 300,
          height: 400,
          child: RulerOverlay(
            ruler: const RulerPosition(page: 1, top: 0.5, height: 0.05, visible: true),
            page: 1,
            dragging: false,
            onPickedUp: (grab) => grabbed = grab,
          ),
        ),
      ),
    );

    expect(find.byType(ColoredBox), findsNothing);

    // Press and hold the band to pick it up; the reader takes over the drag.
    await tester.longPressAt(const Offset(400, 300 + 10));
    expect(grabbed, isNotNull);
  });

  testWidgets('pages without the ruler show nothing over them', (tester) async {
    await tester.pumpWidget(
      floating(
        SizedBox(
          width: 300,
          height: 400,
          child: RulerOverlay(
            ruler: const RulerPosition(page: 2, top: 0.5, height: 0.05, visible: true),
            page: 1,
            dragging: false,
            onPickedUp: (_) {},
          ),
        ),
      ),
    );
    expect(find.byType(Container), findsNothing);
  });

  testWidgets('the compact ruler controls are just the buttons', (tester) async {
    final moves = <int>[];
    final sizes = <int>[];
    await tester.pumpWidget(
      floating(RulerControls(compact: true, onMove: moves.add, onResize: sizes.add)),
    );

    expect(find.text('Ruler'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Move ruler down'));
    await tester.tap(find.byTooltip('Taller ruler'));
    expect(moves, [1]);
    expect(sizes, [1]);
  });
}
