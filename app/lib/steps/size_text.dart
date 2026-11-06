/// Patterns write every size's number at once, in several styles:
///   "Cast on 88 (96, 104, 112)"     commas in one bracket
///   "88 (96) (104) (112)"           a bracket per size
///   "88 (96, 104) [112, 120]"       sizes split across brackets
///   "88 (96/104/112)"               slashes
///   "117 (127) 138 (142) 153"       every other size in brackets, common in
///                                   Scandinavian patterns
///   "4½ (5, 5½)"                    fractions
///   "31 33 35"                      one number per size, no brackets (often
///                                   in coloured type that loses its colour
///                                   when the PDF's text is read)
/// These helpers find the sizes a pattern offers and pick out one size's
/// numbers, so a step can say just "Cast on 104".
library;

/// One number in a size list, a range such as "650-700", or a dash for "not
/// for this size".
const _value = r'(?:\d+(?:\.\d+)?(?:[-–]\d+(?:\.\d+)?)?\s?[½¼¾⅓⅔⅛]?|[½¼¾⅓⅔⅛]|[-–—])';

/// A number outside brackets, which may use a decimal comma ("19,5"). Inside
/// brackets a comma separates sizes, so there it can't.
const _plain = r'\d+(?:\.\d+|,\d{1,2}(?!\d))?(?:[-–]\d+(?:\.\d+)?)?';

/// The first number of a size list.
const _lead = '(?:$_plain\\s?[½¼¾⅓⅔⅛]?|[½¼¾⅓⅔⅛]|[-–—])';

/// A bracketed list of values: "(96, 104)", "[112; 120]", "{96/104}".
const _bracket = r'[\(\[\{]\s*' + _value + r'(?:\s*[,;/]\s*' + _value + r')*\s*[\)\]\}]';

/// A number standing between two brackets, as in "117 (127) 138 (142)":
/// after spaces or a line break where the PDF wrapped the line, and not the
/// start of a word like "8th".
const _between = '(?:[ \\t]+|[ \\t]*\\n[ \\t]*)$_plain[½¼¾⅓⅔⅛]?(?![\\w.½¼¾⅓⅔⅛])';

/// A first value followed by one or more brackets of values, with numbers
/// between the brackets allowed: "88 (96, 104)" or "117 (127) 138 (142)".
final _sizeGroup = RegExp('($_lead)((?:\\s*$_bracket(?:$_between)?)+)');

/// A bracket or a number between brackets, in the order they're written.
final _groupParts = RegExp('$_bracket|$_plain[½¼¾⅓⅔⅛]?');
final _separators = RegExp(r'[,;/]');

/// The values of one size group, first size first.
List<String> _valuesOf(Match group) {
  final values = [group.group(1)!.trim()];
  for (final part in _groupParts.allMatches(group.group(2)!)) {
    final text = part.group(0)!;
    if ('([{'.contains(text[0])) {
      values.addAll(text.substring(1, text.length - 1).split(_separators).map((value) => value.trim()));
    } else {
      values.add(text.trim());
    }
  }
  return values;
}

/// Words that name a size on their own, for size lists written without
/// brackets ("Sizes: S M L XL").
final _sizeWord = RegExp(r'^(?:\d?X{0,3}[SL]|M|\d+(?:\.\d+)?|\d+-\d+(?:m|y|yrs)?)$', caseSensitive: false);

/// A size name written between brackets: a size word, or a single capital
/// letter for patterns that name sizes A (B) C (D).
final _nameBetween = RegExp(r'^(?:\d?X{0,3}[SL]|M|\d+(?:\.\d+)?|\d+-\d+(?:m|y|yrs)?|[A-Z])$');

bool _isNumber(String word) => RegExp(r'^\d+(?:\.\d+)?$').hasMatch(word);

/// The sizes a pattern names, such as ["XS", "S", "M", "L"], from a line like
/// "Sizes: XS (S, M, L)", "Size: S (M) (L)" or "Sizes: S M L". Lines broken
/// inside the brackets are joined first. Empty if no such line is found.
List<String> findSizeNames(String patternText) {
  final bracketed = _findBracketedSizeNames(patternText);
  if (bracketed.isNotEmpty) return bracketed;
  final plain = RegExp(r'\bsizes?\b\s*[:\-–]?\s*([^\n]{1,160})', caseSensitive: false);
  // A list that ends a line with a comma goes on on the next line.
  final joined = patternText.replaceAll(RegExp(r',[ \t]*\n'), ', ');
  for (final match in plain.allMatches(joined)) {
    final words = match.group(1)!.split(RegExp(r'[\s,/]+')).where((word) => word.isNotEmpty).toList();
    final names = words.takeWhile(_sizeWord.hasMatch).toList();
    // "XXS 65, XS 76, S 84": each size followed by its measurement. Keep
    // the names.
    if (names.length >= 4 && names.length.isEven) {
      final odd = [for (var i = 1; i < names.length; i += 2) names[i]];
      final even = [for (var i = 0; i < names.length; i += 2) names[i]];
      if (odd.every(_isNumber) && !even.any(_isNumber)) return even;
    }
    if (names.length >= 2) return names;
  }
  return const [];
}

List<String> _findBracketedSizeNames(String patternText) {
  final joined = _joinBrokenBrackets(patternText);
  // Brackets, with names allowed between them: "XS (S) M (L) XL" and
  // "A (B) C (D), E (F) G (H)".
  final line = RegExp(
    r'\bsizes?\b\s*[:\-–]?\s*([^\n\(\[\{:]{1,24}?)\s*((?:[\(\[\{][^\)\]\}\n]*[\)\]\}][ \t,]*(?:[^\s\(\[\{\)\]\},]{1,8}[ \t,]*)?)+)',
    caseSensitive: false,
  );
  final part = RegExp(r'[\(\[\{]([^\)\]\}]*)[\)\]\}]|([^\s\(\[\{\)\]\},]+)');
  for (final match in line.allMatches(joined)) {
    final first = match.group(1)!.trim();
    final rest = <String>[];
    for (final piece in part.allMatches(match.group(2)!)) {
      final between = piece.group(2);
      if (between != null) {
        // A word after the list ("XS (S) M are …") ends it.
        if (!_nameBetween.hasMatch(between)) break;
        rest.add(between);
        continue;
      }
      rest.addAll(
        piece.group(1)!.split(RegExp(r'[,;]|\s/\s|/(?=\D)')).map((name) => name.trim()).where((n) => n.isNotEmpty),
      );
    }
    final names = [first, ...rest];
    if (first.isNotEmpty && names.length >= 2 && names.every((name) => name.length <= 16)) return names;
  }
  return const [];
}

/// Text with line breaks inside brackets turned into spaces, so a size list
/// that wraps onto the next line in the PDF reads as one.
String _joinBrokenBrackets(String text) {
  final out = StringBuffer();
  var depth = 0;
  for (final char in text.split('')) {
    if ('([{'.contains(char)) depth++;
    if (')]}'.contains(char) && depth > 0) depth--;
    out.write(char == '\n' && depth > 0 ? ' ' : char);
  }
  return out.toString();
}

/// The largest number of sizes any group in [text] offers.
int sizeCountIn(String text) {
  var most = 0;
  for (final match in _sizeGroup.allMatches(_joinBrokenBrackets(text))) {
    final count = _valuesOf(match).length;
    if (count > most) most = count;
  }
  return most;
}

/// The size names for a pattern: the names it lists, padded with "Size 5"
/// and so on if its numbers offer more sizes than the list names. Empty for
/// a pattern with only one size.
List<String> sizeNamesFor(String patternText) {
  final names = [...findSizeNames(patternText)];
  var count = sizeCountIn(patternText);
  if (count < 2) count = plainRunSizeCount(patternText);
  for (var i = names.length; i < count; i++) {
    names.add('Size ${i + 1}');
  }
  return names.length < 2 ? const [] : names;
}

/// A run of exactly [count] numbers separated only by spaces or slashes,
/// such as "31 33 35" for three sizes. Only used once the pattern's number of
/// sizes is known, so ordinary numbers aren't mistaken for sizes.
RegExp _plainRun(int count) {
  const number = r'\d+(?:\.\d+)?[½¼¾]?';
  return RegExp('(?<![\\d.,/])(?<!\\d[ \\t])(?<!\\d[ \\t]/)($number(?:[ \\t]*[ /][ \\t]*$number){${count - 1}})(?![\\d.½¼¾]|[ \\t]*/?[ \\t]*\\d)');
}

/// [text] with each size group replaced by the number for [sizeIndex]
/// (0 is the first size). Groups with fewer sizes are left as written, so a
/// misread group is never silently replaced with the wrong number.
///
/// With [sizeCount] (the pattern's number of sizes), runs of exactly that
/// many numbers without brackets ("31 33 35") are treated as size groups too.
String textForSize(String text, int sizeIndex, {int sizeCount = 0}) {
  var result = _joinBrokenBrackets(text).replaceAllMapped(_sizeGroup, (match) {
    final values = _valuesOf(match);
    if (sizeIndex < 0 || sizeIndex >= values.length) return match.group(0)!;
    // More numbers than the pattern has sizes: two groups written side by
    // side, so leave them rather than guess.
    if (sizeCount >= 2 && values.length > sizeCount) return match.group(0)!;
    return values[sizeIndex];
  });
  if (sizeCount >= 2 && sizeIndex >= 0 && sizeIndex < sizeCount) {
    result = result.replaceAllMapped(_plainRun(sizeCount), (match) {
      final values = match.group(1)!.split(RegExp(r'[ \t]*[ /][ \t]*'));
      return values.length == sizeCount ? values[sizeIndex] : match.group(0)!;
    });
  }
  return result;
}

/// Whether [text] has a size group, with brackets or (given [sizeCount]) as
/// a plain run of numbers.
bool hasSizeGroup(String text, {int sizeCount = 0}) {
  if (sizeCountIn(text) > 1) return true;
  return sizeCount >= 2 && _plainRun(sizeCount).hasMatch(text);
}

/// The most numbers in a row without brackets, for patterns that write one
/// number per size ("31 33 35"). Counted only on lines that look like
/// instructions with stitch counts, to avoid tables of measurements.
int plainRunSizeCount(String text) {
  final counts = <int, int>{};
  final run = RegExp(r'(?<![\d.,/])\d+(?:[ \t]+\d+){1,8}(?=\s*(?:sts|stitches|rows|rnds|rounds|times|cm|in)\b)', caseSensitive: false);
  for (final match in run.allMatches(text)) {
    final size = match.group(0)!.split(RegExp(r'[ \t]+')).length;
    counts[size] = (counts[size] ?? 0) + 1;
  }
  if (counts.isEmpty) return 0;
  // The most common run length is the number of sizes.
  return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}
