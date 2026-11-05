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
