import 'package:flutter/material.dart';

import '../app_session.dart';
import '../data/local_database.dart';
import '../ravelry/models.dart';
import '../theme.dart';
import '../widgets/edit_widgets.dart';
import '../widgets/project_widgets.dart';
import 'edit_conflict_screen.dart';
import 'project_edit_screen.dart';

/// One project: its details, and an Edit button.
///
/// Opens with what's stored on the phone, then loads the full project (notes
/// and size aren't in Ravelry's project list) when online.
class ProjectScreen extends StatefulWidget {
  const ProjectScreen({super.key, required this.session, required this.projectId});

  final AppSession session;
  final int projectId;

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> {
  @override
  void initState() {
    super.initState();
    widget.session.loadFullRecord(RecordType.project, widget.projectId);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) {
        final project = widget.session.projectById(widget.projectId);
        if (project == null) {
          return Scaffold(appBar: AppBar(), body: const Center(child: Text('This project is no longer on Ravelry.')));
        }
        return _ProjectDetails(session: widget.session, project: project);
      },
    );
  }
}

class _ProjectDetails extends StatelessWidget {
  const _ProjectDetails({required this.session, required this.project});

  final AppSession session;
  final Project project;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final status = project.statusName;
    final progress = project.progressPercent;
    final pendingEdit = session.pendingEditFor(RecordType.project, project.id);

    return Scaffold(
      appBar: AppBar(
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => ProjectEditScreen(session: session, project: project),
            )),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          if (pendingEdit != null) ...[
            PendingEditNotice(
              edit: pendingEdit,
              onResolve: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => EditConflictScreen(session: session, edit: pendingEdit),
              )),
              onDiscard: () => session.discardEdit(pendingEdit),
            ),
            const SizedBox(height: 16),
          ],
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
          _Detail(label: 'Size', value: project.size),
          _Detail(label: 'Started', value: _formatDate(context, project.started)),
          _Detail(label: 'Finished', value: _formatDate(context, project.completed)),
          if (project.notes != null) ...[
            const SizedBox(height: 16),
            Semantics(header: true, child: Text('Notes', style: text.titleMedium)),
            const SizedBox(height: 6),
            Text(project.notes!, style: const TextStyle(fontSize: 16, height: 1.45)),
          ],
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
