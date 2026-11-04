/// Patterns write every size's number at once: "Cast on 88 (96, 104, 112)".
/// These helpers find the sizes a pattern offers and pick out one size's
/// numbers, so a step can say just "Cast on 104".
library;

/// A group of numbers, one per size: the first outside the parentheses, the
/// rest inside, separated by commas. Dashes stand for "not for this size".
final _sizeGroup = RegExp(r'(\d+(?:\.\d+)?|[-–—])\s*\(\s*((?:(?:\d+(?:\.\d+)?|[-–—])\s*[,;]\s*)*(?:\d+(?:\.\d+)?|[-–—]))\s*\)');

/// The sizes a pattern names, such as ["XS", "S", "M", "L"], from a line like
/// "Sizes: XS (S, M, L)". Empty if no such line is found.
List<String> findSizeNames(String patternText) {
  final line = RegExp(r'^\s*(?:finished\s+)?sizes?\s*[:\-–]?\s*(.+)$', caseSensitive: false, multiLine: true);
  for (final match in line.allMatches(patternText)) {
    final rest = match.group(1)!;
    final parts = RegExp(r'^([^()]+?)\s*\(([^()]+)\)').firstMatch(rest);
    if (parts == null) continue;
    final names = [parts.group(1)!, ...parts.group(2)!.split(RegExp(r'[,;]'))]
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toList();
    if (names.length >= 2 && names.every((name) => name.length <= 16)) return names;
  }
  return const [];
}

/// The largest number of sizes any group in [text] offers.
int sizeCountIn(String text) {
  var most = 0;
  for (final match in _sizeGroup.allMatches(text)) {
    final count = 1 + match.group(2)!.split(RegExp(r'[,;]')).length;
    if (count > most) most = count;
  }
  return most;
}

/// [text] with each size group replaced by the number for [sizeIndex]
/// (0 is the first size). Groups with fewer sizes are left as written, so a
/// misread group is never silently replaced with the wrong number.
String textForSize(String text, int sizeIndex) {
  return text.replaceAllMapped(_sizeGroup, (match) {
    final values = [match.group(1)!, ...match.group(2)!.split(RegExp(r'[,;]')).map((v) => v.trim())];
    if (sizeIndex < 0 || sizeIndex >= values.length) return match.group(0)!;
    return values[sizeIndex];
  });
}

/// One size group as it appears in a step, for showing every size on tap.
class SizeGroup {
  const SizeGroup({required this.start, required this.end, required this.values});

  final int start;
  final int end;
  final List<String> values;
}

/// Where the size groups are in [text].
List<SizeGroup> sizeGroupsIn(String text) {
  return [
    for (final match in _sizeGroup.allMatches(text))
      SizeGroup(
        start: match.start,
        end: match.end,
        values: [match.group(1)!, ...match.group(2)!.split(RegExp(r'[,;]')).map((v) => v.trim())],
      ),
  ];
}
