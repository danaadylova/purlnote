/// Who made a step.
enum StepMaker {
  /// Apple's on-device model read it from the PDF text.
  model,

  /// The app's own rules split it (on iPhones without Apple Intelligence).
  rules,

  /// The knitter edited, joined or split it.
  edited,
}

/// One instruction in the Steps view, such as "Row 14 (RS): K1, ssk, …".
class PatternStep {
  const PatternStep({
    required this.text,
    required this.sourcePage,
    this.id,
    this.order = 0,
    this.section,
    this.label,
    this.side,
    this.repeatIndex,
    this.repeatTotal,
    this.madeBy = StepMaker.rules,
    this.hidden = false,
  });

  factory PatternStep.fromRow(Map<String, Object?> row) {
    return PatternStep(
      id: row['id'] as int,
      order: row['step_order'] as int,
      section: row['section'] as String?,
      label: row['label'] as String?,
      side: row['side'] as String?,
      text: row['text'] as String,
      sourcePage: row['source_page'] as int,
      repeatIndex: row['repeat_index'] as int?,
      repeatTotal: row['repeat_total'] as int?,
      madeBy: StepMaker.values.byName(row['made_by'] as String),
      hidden: (row['hidden'] as int) == 1,
    );
  }

  final int? id;
  final int order;

  /// The part of the pattern, such as "Body" or "Sleeves".
  final String? section;

  /// "Row 14", "Rnd 3", "Rows 3–4", or null for instructions that aren't rows.
  final String? label;

  /// "RS" or "WS" when the pattern says.
  final String? side;

  /// The instruction, as the pattern writes it (all sizes included).
  final String text;

  /// The PDF page it came from, so the knitter can check the original.
  final int sourcePage;

  /// For steps made by expanding "repeat rows 3–4 ten more times": which
  /// time through this is, out of how many.
  final int? repeatIndex;
  final int? repeatTotal;
  final StepMaker madeBy;
  final bool hidden;

  /// Whether this step is a row or round, so Next moves the row counter.
  bool get isRow => label != null;

  /// "Row 14 (RS)", or the section name for steps that aren't rows.
  String get heading {
    final side = this.side;
    final label = this.label;
    if (label == null) return section ?? 'Step';
    return side == null ? label : '$label ($side)';
  }

  Map<String, Object?> toRow(String fileSha256, int order) => {
        'file_sha256': fileSha256,
        'step_order': order,
        'section': section,
        'label': label,
        'side': side,
        'text': text,
        'source_page': sourcePage,
        'repeat_index': repeatIndex,
        'repeat_total': repeatTotal,
        'made_by': madeBy.name,
        'hidden': hidden ? 1 : 0,
      };

  PatternStep copyWith({String? text, int? repeatIndex, int? repeatTotal, StepMaker? madeBy, bool? hidden}) {
    return PatternStep(
      id: id,
      order: order,
      section: section,
      label: label,
      side: side,
      text: text ?? this.text,
      sourcePage: sourcePage,
      repeatIndex: repeatIndex ?? this.repeatIndex,
      repeatTotal: repeatTotal ?? this.repeatTotal,
      madeBy: madeBy ?? this.madeBy,
      hidden: hidden ?? this.hidden,
    );
  }
}
