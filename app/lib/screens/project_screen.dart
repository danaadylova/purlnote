import 'package:flutter/material.dart';

import '../ravelry/models.dart';
import '../theme.dart';
import '../widgets/project_widgets.dart';

/// One project, read-only. Editing arrives in milestone 2.
class ProjectScreen extends StatelessWidget {
  const ProjectScreen({super.key, required this.project, this.username});

  final Project project;
  final String? username;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final status = project.statusName;
    final progress = project.progressPercent;

    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          ProjectPhoto(url: project.photoUrl, size: 120),
          const SizedBox(height: 16),
          Semantics(header: true, child: Text(project.name, style: text.headlineMedium)),
          if (status != null) ...[
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerLeft, child: StatusChip(status: status)),
          ],
          if (progress != null) ...[
            const SizedBox(height: 20),
            ProgressRow(percent: progress),
          ],
          const SizedBox(height: 20),
          _Detail(label: 'Pattern', value: project.patternName),
          _Detail(label: 'Craft', value: project.craftName),
          _Detail(label: 'Started', value: _formatDate(context, project.started)),
          _Detail(label: 'Finished', value: _formatDate(context, project.completed)),
        ],
      ),
    );
  }

  String? _formatDate(BuildContext context, DateTime? date) {
    if (date == null) return null;
    return MaterialLocalizations.of(context).formatMediumDate(date);
  }
}

/// A label and value on one row. Hidden when there is no value.
class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    if (value == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: const TextStyle(color: PurlnoteColors.plumMuted, fontSize: 15)),
          ),
          Expanded(child: Text(value!, style: const TextStyle(fontSize: 16))),
        ],
      ),
    );
  }
}
