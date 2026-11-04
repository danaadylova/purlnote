import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purlnote/data/local_database.dart';
import 'package:purlnote/steps/rule_splitter.dart';
import 'package:purlnote/steps/size_text.dart';
import 'package:purlnote/steps/step_builder.dart';
import 'package:purlnote/steps/step_models.dart';
import 'package:purlnote/steps/steps_store.dart';

import 'support/fakes.dart';

const samplePattern = '''
Harbour Raglan
Sizes: XS (S, M, L, XL)

Body
Cast on 160 (176, 192, 208, 224) sts. Join to work in the round.
Rnd 1: *K2, p2; rep from * to end.
Rows 2–3 (WS): Purl.

Waist shaping
Row 4 (RS): K1, ssk, knit to last 3 sts, k2tog, k1.
Row 5 (WS): Purl.
Repeat rows 4-5 two more times.
Bind off all sts.
''';

void main() {
  group('sizes', () {
    test('finds the sizes a pattern names', () {
      expect(findSizeNames(samplePattern), ['XS', 'S', 'M', 'L', 'XL']);
      expect(findSizeNames('No sizes here'), isEmpty);
    });

    test('picks one size\'s number from each group', () {
      const text = 'Cast on 160 (176, 192, 208, 224) sts.';
      expect(textForSize(text, 0), 'Cast on 160 sts.');
      expect(textForSize(text, 2), 'Cast on 192 sts.');
      expect(textForSize(text, 9), text, reason: 'a size the group doesn\'t have leaves it as written');
      expect(sizeCountIn(text), 5);
    });

    test('a dash for "not this size" is kept', () {
      expect(textForSize('Work 4 (-, 6) rows.', 1), 'Work - rows.');
    });

    test('row sides in parentheses aren\'t mistaken for sizes', () {
      expect(sizeCountIn('Row 4 (RS): K1.'), 0);
    });

    test('reads every common way of writing sizes', () {
      expect(textForSize('Cast on 88 (96) (104) (112) sts.', 3), 'Cast on 112 sts.');
      expect(textForSize('Cast on 88 (96, 104) [112, 120] sts.', 4), 'Cast on 120 sts.');
      expect(textForSize('Knit 32 (36/40/44) rows.', 2), 'Knit 40 rows.');
      expect(textForSize('Work 4½ (5, 5½) in.', 2), 'Work 5½ in.');
      expect(sizeCountIn('Cast on 88 (96, 104) [112, 120] sts.'), 5);
    });

    test('finds all size names, even when the list wraps or uses several brackets', () {
      expect(findSizeNames('Sizes: XS (S, M,\nL, XL, 2XL)'), ['XS', 'S', 'M', 'L', 'XL', '2XL']);
      expect(findSizeNames('Size: S (M) (L) (XL)'), ['S', 'M', 'L', 'XL']);
      expect(findSizeNames('SIZES 1 (2, 3) [4, 5]'), ['1', '2', '3', '4', '5']);
      expect(findSizeNames('Sizes: XS (S/M/L)'), ['XS', 'S', 'M', 'L']);
    });

    test('offers as many sizes as the numbers have, even if the names list is shorter', () {
      const text = 'Sizes: S (M)\nCast on 80 (88, 96, 104) sts.';
      expect(sizeNamesFor(text), ['S', 'M', 'Size 3', 'Size 4']);
      expect(sizeNamesFor('Cast on 80 sts.'), isEmpty);
    });
  });

  group('splitting with rules', () {
    late List<PatternStep> steps;

    setUp(() => steps = const RuleSplitter().split([samplePattern]));

    test('rows become steps with their label and side', () {
      final row4 = steps.firstWhere((s) => s.label == 'Row 4');
      expect(row4.side, 'RS');
      expect(row4.text, 'K1, ssk, knit to last 3 sts, k2tog, k1.');
      expect(row4.section, 'Waist shaping');
      expect(steps.firstWhere((s) => s.label == 'Rnd 1').text, '*K2, p2; rep from * to end.');
      expect(steps.firstWhere((s) => s.label == 'Rows 2–3').side, 'WS');
    });

    test('headings become sections, not steps', () {
      expect(steps.any((s) => s.text == 'Body'), isFalse);
      expect(steps.firstWhere((s) => s.text.startsWith('Cast on')).section, 'Body');
    });

    test('"repeat rows 4-5 two more times" is written out as counted steps', () {
      final shaping = steps.where((s) => s.label == 'Row 4' || s.label == 'Row 5').toList();
      expect(shaping, hasLength(6));
      expect(shaping.map((s) => s.repeatIndex), [1, 1, 2, 2, 3, 3]);
      expect(shaping.every((s) => s.repeatTotal == 3), isTrue);
      expect(steps.any((s) => s.text.toLowerCase().startsWith('repeat')), isFalse);
      expect(steps.last.text, 'Bind off all sts.');
    });

    test('a repeat that can\'t be matched stays as written', () {
      final odd = const RuleSplitter().split(['Row 1: Knit.\nRepeat rows 7-8 three times.']);
      expect(odd.last.text, 'Repeat rows 7-8 three times.');
    });

    test('a row that wraps onto the next line stays one step', () {
      final wrapped = const RuleSplitter().split(['Row 1: K2, *p2, k2; rep from *\nto end of row.\nRow 2: Purl.']);
      expect(wrapped.first.text, 'K2, *p2, k2; rep from * to end of row.');
      expect(wrapped, hasLength(2));
    });

    test('each step knows its page', () {
      final twoPages = const RuleSplitter().split(['Row 1: Knit.', 'Row 2: Purl.']);
      expect(twoPages.map((s) => s.sourcePage), [1, 2]);
    });

    test('short title lines are headings, instructions are not', () {
      expect(RuleSplitter.isHeading('SLEEVES'), isTrue);
      expect(RuleSplitter.isHeading('Yoke:'), isTrue);
      expect(RuleSplitter.isHeading('Knit'), isFalse);
      expect(RuleSplitter.isHeading('Cast on 88 sts.'), isFalse);
    });
  });

  group('building and storing steps', () {
    late LocalDatabase database;
    late StepsStore store;

    setUp(() async {
      database = await emptyDatabase();
      store = StepsStore(database);
    });

    tearDown(() => database.close());

    test('without the on-device model, rules make the steps', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final builder = StepBuilder(store: store, readText: (_) async => [samplePattern, '']);

      final result = await builder.build(fileSha256: 'abc', pdfPath: 'unused.pdf');

      expect(result.madeBy, StepMaker.rules);
      expect(result.pagesWithoutText, [2]);
      final stored = await store.stepsFor('abc');
      expect(stored, hasLength(result.stepCount));
      expect(stored.every((s) => s.madeBy == StepMaker.rules), isTrue);
    });

    test('with the on-device model, its steps are used and repeats written out', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel('purlnote/steps');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'isAvailable') return true;
        return [
          {'section': 'Body', 'label': 'Row 1', 'side': 'RS', 'text': 'Knit.'},
          {'section': 'Body', 'label': 'Row 2', 'side': 'ws', 'text': 'Purl.'},
          {'section': 'Body', 'label': '', 'side': '', 'text': 'Repeat rows 1-2 one more time.'},
          {'section': 'Body', 'label': '', 'side': '', 'text': ''},
        ];
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));

      final pages = <int>[];
      final builder = StepBuilder(store: store, readText: (_) async => ['Row 1 ...']);
      final result = await builder.build(fileSha256: 'abc', pdfPath: 'unused.pdf', onPage: (page, _) => pages.add(page));

      expect(result.madeBy, StepMaker.model);
      expect(pages, [1]);
      final stored = await store.stepsFor('abc');
      expect(stored.map((s) => s.label), ['Row 1', 'Row 2', 'Row 1', 'Row 2']);
      expect(stored[1].side, 'WS');
      expect(stored.last.repeatIndex, 2);
    });

    test('the knitter can edit, join, split and hide steps', () async {
      await store.replaceSteps('abc', const RuleSplitter().split(['Row 1: Knit.\nRow 2: Purl.\nRow 3: Knit.']));
      var steps = await store.stepsFor('abc');

      await store.join(steps[0], steps[1]);
      steps = await store.stepsFor('abc');
      expect(steps.first.text, 'Knit. Purl.');
      expect(steps.first.madeBy, StepMaker.edited);

      await store.split('abc', steps.first, 'Knit.'.length);
      steps = await store.stepsFor('abc');
      expect(steps.map((s) => s.text), ['Knit.', 'Purl.', 'Knit.']);
      expect(steps[1].isRow, isFalse, reason: 'a split-off part doesn\'t move the row counter');

      await store.hide(steps.last);
      await store.editText(steps.first, 'Knit all sts.');
      steps = await store.stepsFor('abc');
      expect(steps.last.hidden, isTrue);
      expect(steps.first.text, 'Knit all sts.');
    });

    test('each project keeps its own place and size', () async {
      expect((await store.progress(10, 'abc')).sizeIndex, isNull);
      await store.saveProgress(10, 'abc', const StepProgress(currentStep: 7, sizeIndex: 2, nextMovesCounter: false));

      final saved = await store.progress(10, 'abc');
      expect(saved.currentStep, 7);
      expect(saved.sizeIndex, 2);
      expect(saved.nextMovesCounter, isFalse);
      expect((await store.progress(11, 'abc')).currentStep, 0);
    });
  });

  test('long pages are sent to the model in pieces, split between lines', () {
    final text = List.generate(10, (i) => 'Line $i ${'x' * 40}').join('\n');
    final chunks = chunksOf(text, 120);
    expect(chunks.every((c) => c.length <= 120), isTrue);
    expect(chunks.join('\n'), text);
    expect(chunksOf('   ', 100), isEmpty);
  });
}
