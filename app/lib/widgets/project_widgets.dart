import 'package:flutter/material.dart';

import '../ravelry/models.dart';
import '../theme.dart';

/// A project's status in words, never by color alone.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final inProgress = status == 'In progress';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: inProgress ? PurlnoteColors.mossLight : PurlnoteColors.sand,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: inProgress ? PurlnoteColors.mossDark : PurlnoteColors.plum,
        ),
      ),
    );
  }
}

/// A project's progress bar with its percentage written out.
class ProgressRow extends StatelessWidget {
  const ProgressRow({super.key, required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    final clamped = percent.clamp(0, 100);
    return Semantics(
      label: 'Progress $clamped percent',
      excludeSemantics: true,
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: clamped / 100, minHeight: 8),
            ),
          ),
          const SizedBox(width: 10),
          Text('$clamped%', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        ],
      ),
    );
  }
}

/// The project's first photo, or a plain tile with a yarn icon.
class ProjectPhoto extends StatelessWidget {
  const ProjectPhoto({super.key, required this.url, this.size = 72});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      color: PurlnoteColors.sand,
      alignment: Alignment.center,
      child: const Icon(Icons.gesture, color: PurlnoteColors.plumMuted),
    );

    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: url == null
            ? placeholder
            : Image.network(
                url!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                // Offline, show the placeholder instead of a broken image.
                errorBuilder: (context, error, stack) => placeholder,
              ),
      ),
    );
  }
}

/// A card for a project on the needles: photo, name, pattern and progress.
class ProjectCard extends StatelessWidget {
  const ProjectCard({super.key, required this.project, required this.onTap});

  final Project project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pattern = project.patternName;
    final progress = project.progressPercent;

    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: PurlnoteColors.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ProjectPhoto(url: project.photoUrl),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(project.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    if (pattern != null) ...[
                      const SizedBox(height: 2),
                      Text(pattern, style: const TextStyle(fontSize: 14, color: PurlnoteColors.plumMuted)),
                    ],
                    const SizedBox(height: 10),
                    if (progress != null)
                      ProgressRow(percent: progress)
                    else
                      const Text('No progress set', style: TextStyle(fontSize: 13, color: PurlnoteColors.plumMuted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
