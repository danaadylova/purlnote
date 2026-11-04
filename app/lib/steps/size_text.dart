/// Patterns write every size's number at once, in several styles:
///   "Cast on 88 (96, 104, 112)"     commas in one bracket
///   "88 (96) (104) (112)"           a bracket per size
///   "88 (96, 104) [112, 120]"       sizes split across brackets
///   "88 (96/104/112)"               slashes
///   "4½ (5, 5½)"                    fractions
///   "31 33 35"                      one number per size, no brackets (often
///                                   in coloured type that loses its colour
///                                   when the PDF's text is read)
/// These helpers find the sizes a pattern offers and pick out one size's
/// numbers, so a step can say just "Cast on 104".
library;

/// One number in a size list, or a dash for "not for this size".
const _value = r'(?:\d+(?:\.\d+)?\s?[½¼¾⅓⅔⅛]?|[½¼¾⅓⅔⅛]|[-–—])';

/// A bracketed list of values: "(96, 104)", "[112; 120]", "{96/104}".
const _bracket = r'[\(\[\{]\s*' + _value + r'(?:\s*[,;/]\s*' + _value + r')*\s*[\)\]\}]';

/// A first value followed by one or more brackets of values.
final _sizeGroup = RegExp('($_value)((?:\\s*$_bracket)+)');

final _brackets = RegExp(_bracket);
final _separators = RegExp(r'[,;/]');

/// The values of one size group, first size first.
List<String> _valuesOf(Match group) {
  final values = [group.group(1)!.trim()];
  for (final bracket in _brackets.allMatches(group.group(2)!)) {
    final inside = bracket.group(0)!.substring(1, bracket.group(0)!.length - 1);
    values.addAll(inside.split(_separators).map((value) => value.trim()));
  }
  return values;
}

/// Words that name a size on their own, for size lists written without
/// brackets ("Sizes: S M L XL").
final _sizeWord = RegExp(r'^(?:\d?X{0,3}[SL]|M|\d+(?:\.\d+)?|\d+-\d+(?:m|y|yrs)?)$', caseSensitive: false);

/// The sizes a pattern names, such as ["XS", "S", "M", "L"], from a line like
/// "Sizes: XS (S, M, L)", "Size: S (M) (L)" or "Sizes: S M L". Lines broken
/// inside the brackets are joined first. Empty if no such line is found.
List<String> findSizeNames(String patternText) {
  final bracketed = _findBracketedSizeNames(patternText);
  if (bracketed.isNotEmpty) return bracketed;
  final plain = RegExp(r'\bsizes?\b\s*[:\-–]?\s*([^\n]{1,80})', caseSensitive: false);
  for (final match in plain.allMatches(patternText)) {
    final words = match.group(1)!.split(RegExp(r'[\s,/]+')).where((word) => word.isNotEmpty).toList();
    final names = words.takeWhile(_sizeWord.hasMatch).toList();
    if (names.length >= 2) return names;
  }
  return const [];
}

List<String> _findBracketedSizeNames(String patternText) {
  final joined = _joinBrokenBrackets(patternText);
  final line = RegExp(
    r'\bsizes?\b\s*[:\-–]?\s*([^\n\(\[\{:]{1,24}?)\s*((?:[\(\[\{][^\)\]\}\n]*[\)\]\}]\s*)+)',
    caseSensitive: false,
  );
  for (final match in line.allMatches(joined)) {
    final first = match.group(1)!.trim();
    final rest = RegExp(r'[\(\[\{]([^\)\]\}]*)[\)\]\}]')
        .allMatches(match.group(2)!)
        .expand((bracket) => bracket.group(1)!.split(RegExp(r'[,;]|\s/\s|/(?=\D)')))
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty);
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
