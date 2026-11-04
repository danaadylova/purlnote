import 'step_models.dart';

/// Splits a pattern's text into steps with plain rules, for iPhones without
/// Apple Intelligence. It handles the common layout: headings, lines that
/// start with "Row 3" or "Rnd 3", and paragraphs of written instructions.
/// Charts and odd layouts may split less well; the knitter can fix any step.
class RuleSplitter {
  const RuleSplitter();

  /// "Row 14 (RS): ...", "Rows 3–4: ...", "Rnd 7. ...", "Round 2 ...".
  static final _rowStart = RegExp(
    r'^(rows?|rnds?|rounds?)\s+(\d+)(?:\s*(?:-|–|—|to|and|&)\s*(\d+))?\s*(?:\(\s*(rs|ws)\s*\)|\b(rs|ws)\b)?\s*[:.\-–]?\s*(.*)$',
    caseSensitive: false,
  );

  /// Splits [pages] (the text of each page, first page first) into steps.
  List<PatternStep> split(List<String> pages) {
    final steps = <PatternStep>[];
    String? section;
    _Unit? current;

    void finish() {
      final unit = current;
      if (unit != null && unit.text.trim().isNotEmpty) {
        steps.add(PatternStep(
          section: section,
          label: unit.label,
          side: unit.side,
          text: unit.text.trim(),
          sourcePage: unit.page,
          madeBy: StepMaker.rules,
        ));
      }
      current = null;
    }

    for (var index = 0; index < pages.length; index++) {
      final page = index + 1;
      for (final rawLine in pages[index].split('\n')) {
        final line = rawLine.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (line.isEmpty) {
          // A blank line ends a paragraph, but not a row that wraps.
          if (current?.label == null) finish();
          continue;
        }

        final row = _rowStart.firstMatch(line);
        if (row != null) {
          finish();
          current = _Unit(page: page, label: _label(row), side: (row.group(4) ?? row.group(5))?.toUpperCase())
            ..add(row.group(6) ?? '');
          continue;
        }

        if (isHeading(line)) {
          finish();
          section = line.replaceAll(RegExp(r':$'), '');
          continue;
        }

        final unit = current;
        if (unit == null) {
          current = _Unit(page: page)..add(line);
        } else if (_endsSentence(unit.text) && (unit.label == null || _startsSentence(line))) {
          // A finished sentence closes written instructions. After a row, a
          // new sentence ("Repeat rows 4-5…") is its own step, while a
          // lowercase line is the row wrapping onto the next line.
          finish();
          current = _Unit(page: page)..add(line);
        } else {
          unit.add(line);
        }
      }
    }
    finish();
    return expandRepeats(steps);
  }

  /// "Row 3" or "Rows 3–4", keeping the pattern's word (Row, Rnd, Round).
  static String _label(RegExpMatch row) {
    final word = row.group(1)!;
    final base = word[0].toUpperCase() + word.substring(1).toLowerCase();
    final to = row.group(3);
    if (to == null) return '${base.replaceAll(RegExp(r's$'), '')} ${row.group(2)}';
    final plural = base.endsWith('s') ? base : '${base}s';
    return '$plural ${row.group(2)}–$to';
  }

  static bool _endsSentence(String text) => RegExp(r'[.!?)]$').hasMatch(text.trim());

  static bool _startsSentence(String line) => RegExp(r'^[A-Z]').hasMatch(line);

  /// A short line that names a part of the pattern, such as "Body", "SLEEVES"
  /// or "Yoke:". Lines with instructions or sizes are not headings.
  static bool isHeading(String line) {
    final text = line.replaceAll(RegExp(r':$'), '').trim();
    if (text.isEmpty || text.length > 32) return false;
    if (!RegExp(r'^[A-Z]').hasMatch(text)) return false;
    if (RegExp(r'[.,;()]').hasMatch(text)) return false;
    if (RegExp(r'\d').hasMatch(text)) return false;
    final words = text.split(' ');
    if (words.length > 4) return false;
    // Stitch instructions on their own line ("Knit", "Purl") are steps.
    const stitchWords = {'knit', 'purl', 'repeat', 'work', 'turn', 'bind', 'cast', 'join', 'slip', 'place'};
    return !stitchWords.contains(words.first.toLowerCase());
  }

  /// "Repeat rows 3–4 ten more times" becomes those rows, written out that
  /// many more times, each copy marked "Repeat 2 of 11" and so on. A repeat
  /// that can't be matched to earlier rows stays as written.
  static List<PatternStep> expandRepeats(List<PatternStep> steps) {
    final repeat = RegExp(
      r'^repeat\s+(?:rows?|rnds?|rounds?)\s+(\d+)\s*(?:-|–|—|to|and|&|through)\s*(\d+)\s+(\w+)\s+(more\s+)?times?',
      caseSensitive: false,
    );
    final result = <PatternStep>[];
    for (final step in steps) {
      final match = repeat.firstMatch(step.text.trim());
      final times = match == null ? null : _number(match.group(3)!);
      if (match == null || times == null || step.isRow) {
        result.add(step);
        continue;
      }
      final from = int.parse(match.group(1)!);
      final to = int.parse(match.group(2)!);
      final group = _lastRowsBetween(result, from, to);
      // "N more times" adds N; "N times" means N in all, the first already done.
      final extra = match.group(4) != null ? times : times - 1;
      if (group.isEmpty || extra < 1 || extra > 50) {
        result.add(step);
        continue;
      }
      final total = extra + 1;
      for (var i = result.length - group.length; i < result.length; i++) {
        result[i] = result[i].copyWith(repeatIndex: 1, repeatTotal: total);
      }
      for (var time = 2; time <= total; time++) {
        for (final row in group) {
          result.add(row.copyWith(repeatIndex: time, repeatTotal: total));
        }
      }
    }
    return result;
  }

  /// The run of steps at the end of [steps] whose row numbers fall in
  /// [from]..[to], or empty if the rows just before aren't those rows.
  static List<PatternStep> _lastRowsBetween(List<PatternStep> steps, int from, int to) {
    final group = <PatternStep>[];
    for (var i = steps.length - 1; i >= 0; i--) {
      final numbers = RegExp(r'\d+').allMatches(steps[i].label ?? '').map((m) => int.parse(m.group(0)!)).toList();
      if (numbers.isEmpty || numbers.any((n) => n < from || n > to)) break;
      group.insert(0, steps[i]);
      if (numbers.first == from) break;
    }
    final firstNumber = group.isEmpty ? null : int.parse(RegExp(r'\d+').firstMatch(group.first.label!)!.group(0)!);
    return firstNumber == from ? group : const [];
  }

  static int? _number(String word) {
    const words = [
      'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten',
      'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen', 'twenty',
    ];
    final index = words.indexOf(word.toLowerCase());
    return int.tryParse(word) ?? (index > 0 ? index : null);
  }
}

/// Lines being gathered into one step.
class _Unit {
  _Unit({required this.page, this.label, this.side});

  final int page;
  final String? label;
  final String? side;
  final _parts = <String>[];

  String get text => _parts.join(' ');

  void add(String line) {
    if (line.isNotEmpty) _parts.add(line);
  }
}
