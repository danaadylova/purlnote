import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../theme.dart';
import 'reader_store.dart';

/// The reader's tools. With [none], the page scrolls and zooms as usual;
/// with any other tool, touches on the page draw or place marks instead.
enum ReaderTool {
  none('Read', Icons.pan_tool_alt_outlined),
  highlight('Highlight', Icons.border_color_outlined),
  pen('Pen', Icons.gesture),
  note('Note', Icons.push_pin_outlined),
  ruler('Row ruler', Icons.straighten),
  erase('Erase', Icons.cleaning_services_outlined);

  const ReaderTool(this.label, this.icon);

  final String label;
  final IconData icon;

  /// Tools that need touches on the page, so the viewer must stop panning.
  bool get drawsOnPage => this == highlight || this == pen || this == note || this == erase;
}

/// Everything drawn on one page: highlights, pen strokes and note pins, and
/// the gestures for the active tool. Positions are fractions of the page.
class PageMarks extends StatefulWidget {
  const PageMarks({
    super.key,
    required this.page,
    required this.marks,
    required this.tool,
    required this.onAdd,
    required this.onErase,
    required this.onOpenNote,
    required this.onPlaceNote,
  });

  final int page;

  /// This page's annotations.
  final List<Annotation> marks;
  final ReaderTool tool;

  /// A new highlight or pen stroke, in page fractions.
  final void Function(AnnotationKind kind, List<Offset> points) onAdd;
  final ValueChanged<Annotation> onErase;
  final ValueChanged<Annotation> onOpenNote;

  /// Where on the page a new note should go.
  final ValueChanged<Offset> onPlaceNote;

  @override
  State<PageMarks> createState() => _PageMarksState();
}

class _PageMarksState extends State<PageMarks> {
  /// The stroke or highlight being drawn right now, in page fractions.
  List<Offset> _drawing = const [];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        Offset fraction(Offset local) => Offset(
              (local.dx / size.width).clamp(0.0, 1.0),
              (local.dy / size.height).clamp(0.0, 1.0),
            );

        final notes = widget.marks.where((mark) => mark.kind == AnnotationKind.note);

        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _MarksPainter(marks: widget.marks, drawing: _drawing, tool: widget.tool)),
              ),
            ),
            if (widget.tool.drawsOnPage)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (details) => _tap(fraction(details.localPosition)),
                  onPanStart: (details) => setState(() => _drawing = [fraction(details.localPosition)]),
                  onPanUpdate: (details) => setState(() => _drawing = [..._drawing, fraction(details.localPosition)]),
                  onPanEnd: (_) => _finishDrawing(),
                ),
              ),
            for (final note in notes)
              Positioned(
                left: note.points.first.dx * size.width - _NotePin.size / 2,
                top: note.points.first.dy * size.height - _NotePin.size,
                child: _NotePin(
                  number: notes.toList().indexOf(note) + 1,
                  text: note.text ?? '',
                  onTap: () => widget.tool == ReaderTool.erase ? widget.onErase(note) : widget.onOpenNote(note),
                ),
              ),
          ],
        );
      },
    );
  }

  void _tap(Offset at) {
    switch (widget.tool) {
      case ReaderTool.note:
        widget.onPlaceNote(at);
      case ReaderTool.erase:
        final hit = _markAt(at);
        if (hit != null) widget.onErase(hit);
      default:
        break;
    }
  }

  void _finishDrawing() {
    final points = _drawing;
    setState(() => _drawing = const []);
    if (points.length < 2) return;
    switch (widget.tool) {
      case ReaderTool.highlight:
        widget.onAdd(AnnotationKind.highlight, [points.first, points.last]);
      case ReaderTool.pen:
        widget.onAdd(AnnotationKind.ink, points);
      default:
        break;
    }
  }

  /// The highlight or stroke under a tap, for the eraser.
  Annotation? _markAt(Offset at) {
    const reach = 0.02;
    for (final mark in widget.marks.reversed) {
      if (mark.kind == AnnotationKind.highlight) {
        if (Rect.fromPoints(mark.points.first, mark.points.last).inflate(reach).contains(at)) return mark;
      } else if (mark.kind == AnnotationKind.ink) {
        if (mark.points.any((point) => (point - at).distance < reach)) return mark;
      }
    }
    return null;
  }
}

class _MarksPainter extends CustomPainter {
  _MarksPainter({required this.marks, required this.drawing, required this.tool});

  final List<Annotation> marks;
  final List<Offset> drawing;
  final ReaderTool tool;

  static final _highlight = Paint()..color = PurlnoteColors.marigold.withValues(alpha: 0.35);
  static final _ink = Paint()
    ..color = PurlnoteColors.marigoldDark
    ..strokeWidth = 2.5
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;

  @override
  void paint(Canvas canvas, Size size) {
    Offset onPage(Offset fraction) => Offset(fraction.dx * size.width, fraction.dy * size.height);

    void drawHighlight(List<Offset> points) =>
        canvas.drawRect(Rect.fromPoints(onPage(points.first), onPage(points.last)), _highlight);

    void drawInk(List<Offset> points) {
      final path = Path()..moveTo(onPage(points.first).dx, onPage(points.first).dy);
      for (final point in points.skip(1)) {
        path.lineTo(onPage(point).dx, onPage(point).dy);
      }
      canvas.drawPath(path, _ink);
    }

    for (final mark in marks) {
      if (mark.kind == AnnotationKind.highlight) drawHighlight(mark.points);
      if (mark.kind == AnnotationKind.ink) drawInk(mark.points);
    }
    if (drawing.length >= 2) {
      if (tool == ReaderTool.highlight) drawHighlight([drawing.first, drawing.last]);
      if (tool == ReaderTool.pen) drawInk(drawing);
    }
  }

  @override
  bool shouldRepaint(_MarksPainter old) => old.marks != marks || old.drawing != drawing || old.tool != tool;
}

/// A numbered pin for a note. The note's text is its spoken label, and the
/// notes panel lists every pin so they can be reached without seeing the page.
class _NotePin extends StatelessWidget {
  const _NotePin({required this.number, required this.text, required this.onTap});

  static const size = 34.0;
  final int number;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Note $number: $text',
      excludeSemantics: true,
      // Lets the viewer tell a tap on the pin from a pan of the page.
      child: PdfOverlayInteractionRegion(
        onTap: (_) {
          onTap();
          return true;
        },
        child: Container(
          // 44 points to touch, even though the pin looks smaller.
          width: 44,
          height: 44,
          alignment: Alignment.topLeft,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: PurlnoteColors.marigold,
              border: Border.all(color: Colors.white, width: 2),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(17),
                topRight: Radius.circular(17),
                bottomRight: Radius.circular(17),
                bottomLeft: Radius.circular(4),
              ),
              boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2))],
            ),
            alignment: Alignment.center,
            child: Text('$number', style: const TextStyle(fontWeight: FontWeight.w700, color: PurlnoteColors.plum)),
          ),
        ),
      ),
    );
  }
}
