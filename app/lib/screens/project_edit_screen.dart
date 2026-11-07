import 'package:flutter/material.dart';

import '../app_session.dart';
import '../data/local_database.dart';
import '../layout.dart';
import '../ravelry/models.dart';
import '../theme.dart';
import '../widgets/edit_widgets.dart';

/// Edits a project's name, status, progress, dates, size and notes.
///
/// Saving works offline: the change shows at once and goes to Ravelry when
/// the phone is online. Only fields the knitter actually changed are sent.
class ProjectEditScreen extends StatefulWidget {
  const ProjectEditScreen({super.key, required this.session, required this.project});

  final AppSession session;
  final Project project;

  @override
  State<ProjectEditScreen> createState() => _ProjectEditScreenState();
}

class _ProjectEditScreenState extends State<ProjectEditScreen> {
  late final _name = TextEditingController(text: widget.project.name);
  late final _size = TextEditingController(text: widget.project.size ?? '');
  late final _notes = TextEditingController(text: widget.project.notes ?? '');
  late int? _statusId = widget.project.statusId;
  late int _progress = widget.project.progressPercent ?? 0;
  late DateTime? _started = widget.project.started;
  late DateTime? _finished = widget.project.completed;

  @override
  void dispose() {
    _name.dispose();
    _size.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// The fields that differ from the project as it was, by Ravelry's names.
  Map<String, Object?> _changes() {
    final before = widget.project;
    final name = _name.text.trim();
    return {
      if (name.isNotEmpty && name != before.name) 'name': name,
      if (_statusId != null && _statusId != before.statusId) 'project_status_id': _statusId,
      if (_progress != (before.progressPercent ?? 0)) 'progress': _progress,
      if (!DateUtils.isSameDay(_started, before.started)) 'started': _started == null ? null : ravelryDate(_started),
      if (!DateUtils.isSameDay(_finished, before.completed))
        'completed': _finished == null ? null : ravelryDate(_finished),
      if (_size.text.trim() != (before.size ?? '')) 'size': _size.text.trim(),
      if (_notes.text.trim() != (before.notes ?? '')) 'notes': _notes.text.trim(),
    };
  }

  Future<void> _save() async {
    final changes = _changes();
    final newStatus = widget.session.projectStatuses.where((status) => status.id == _statusId).firstOrNull;
    await widget.session.saveEdit(
      RecordType.project,
      widget.project.id,
      changes,
      displayFields: {
        // The Notebook groups projects by status name, so it changes with the ID.
        if (changes.containsKey('project_status_id') && newStatus != null) 'status_name': newStatus.name,
      },
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final statuses = widget.session.projectStatuses;

    return Scaffold(
      appBar: AppBar(
        title: Semantics(header: true, child: const Text('Edit project')),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: ListView(
        padding: readablePadding(context, const EdgeInsets.fromLTRB(16, 8, 16, 32)),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          if (statuses.isNotEmpty)
            DropdownButtonFormField<int>(
              initialValue: statuses.any((status) => status.id == _statusId) ? _statusId : null,
              decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
              items: [
                for (final status in statuses) DropdownMenuItem(value: status.id, child: Text(status.name)),
              ],
              onChanged: (id) => setState(() => _statusId = id),
            ),
          const SizedBox(height: 20),
          _ProgressSlider(value: _progress, onChanged: (value) => setState(() => _progress = value)),
          const SizedBox(height: 16),
          DateField(label: 'Started', value: _started, onChanged: (date) => setState(() => _started = date)),
          const SizedBox(height: 12),
          DateField(label: 'Finished', value: _finished, onChanged: (date) => setState(() => _finished = date)),
          const SizedBox(height: 16),
          TextField(
            controller: _size,
            decoration: const InputDecoration(labelText: 'Size', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _notes,
            minLines: 4,
            maxLines: 12,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Notes',
              helperText: 'Project notes are public on Ravelry.',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Changes save on this device right away and go to Ravelry when you\'re online.',
            style: TextStyle(color: PurlnoteColors.plumMuted),
          ),
        ],
      ),
    );
  }
}

/// Progress in steps of 5%, with the number written out and spoken.
class _ProgressSlider extends StatelessWidget {
  const _ProgressSlider({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Progress: $value%', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        Slider(
          value: value.toDouble(),
          max: 100,
          divisions: 20,
          label: '$value%',
          semanticFormatterCallback: (value) => '${value.round()} percent',
          onChanged: (newValue) => onChanged(newValue.round()),
        ),
      ],
    );
  }
}
