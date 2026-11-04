/// A project's notes, as separate entries.
///
/// Ravelry keeps a project's notes as one text field. Purlnote writes each
/// note as its own paragraph starting with the date ("2026-11-04: Switched
/// to 3.75 mm"), separated by a blank line, so they can be shown, added and
/// edited one at a time while staying readable on the Ravelry website.
library;

/// The entries in [notes], in order. Notes written elsewhere without blank
/// lines between them count as one entry.
List<String> noteEntries(String? notes) {
  return (notes ?? '')
      .split(RegExp(r'\n\s*\n'))
      .map((entry) => entry.trim())
      .where((entry) => entry.isNotEmpty)
      .toList();
}

/// The notes field for [entries].
String joinNoteEntries(List<String> entries) => entries.map((entry) => entry.trim()).join('\n\n');

/// A new entry: "2026-11-04: text".
String datedNote(String text, DateTime day) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${day.year}-${two(day.month)}-${two(day.day)}: ${text.trim()}';
}
