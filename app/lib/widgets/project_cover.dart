import 'dart:io';

import 'package:flutter/material.dart';

import '../ravelry/models.dart';

/// A project's cover: its first photo, or a knitted-fabric pattern in one
/// of the app's yarn colours when it has none (or the photo can't load).
class ProjectCover extends StatelessWidget {
  const ProjectCover({super.key, required this.project, this.borderRadius = BorderRadius.zero});

  final Project project;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final fabric = KnittedFabric(color: yarnColorFor(project.id));
    final picture = project.pictures.firstOrNull;
    final Widget image;
    if (picture?.localPath != null) {
      image = Image.file(File(picture!.localPath!), fit: BoxFit.cover, errorBuilder: (context, error, stack) => fabric);
    } else if ((picture?.url ?? project.photoUrl) != null) {
      image = Image.network(
        picture?.url ?? project.photoUrl!,
        fit: BoxFit.cover,
        // Offline, show the fabric instead of a broken image.
        errorBuilder: (context, error, stack) => fabric,
      );
    } else {
      image = fabric;
    }
    return ExcludeSemantics(
      child: ClipRRect(borderRadius: borderRadius, child: SizedBox.expand(child: image)),
    );
  }
}

/// Colours for projects without a photo, chosen by project so a project
/// always gets the same one.
const yarnColors = [
  Color(0xFFB5543C), // rust
  Color(0xFF5E7F8C), // fog blue
  Color(0xFF7E8F4E), // moss
  Color(0xFFC9822A), // marigold
  Color(0xFF8C5E7A), // heather
  Color(0xFF4F6B5A), // pine
];

Color yarnColorFor(int projectId) => yarnColors[projectId.abs() % yarnColors.length];

/// Rows of knit stitches (little V's) drawn over a yarn colour.
class KnittedFabric extends StatelessWidget {
  const KnittedFabric({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _StitchPainter(color), child: const SizedBox.expand());
  }
}

class _StitchPainter extends CustomPainter {
  _StitchPainter(this.color);

  final Color color;

  static const _stitchWidth = 14.0;
  static const _rowHeight = 12.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = color);
    final stitch = Paint()
      ..color = Colors.white.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var y = 0.0; y < size.height + _rowHeight; y += _rowHeight) {
      for (var x = 0.0; x < size.width + _stitchWidth; x += _stitchWidth) {
        // Each stitch is two legs meeting at the bottom, like a "V".
        final path = Path()
          ..moveTo(x + 2, y)
          ..lineTo(x + _stitchWidth / 2, y + _rowHeight - 2)
          ..lineTo(x + _stitchWidth - 2, y);
        canvas.drawPath(path, stitch);
      }
    }
  }

  @override
  bool shouldRepaint(_StitchPainter old) => old.color != color;
}
