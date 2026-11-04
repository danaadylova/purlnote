import 'package:flutter/material.dart';

import '../app_session.dart';
import '../data/pending_edit.dart';
import '../ravelry/models.dart';
import '../theme.dart';

/// Ravelry's date format for sending, such as "2026/11/04".
String ravelryDate(DateTime? date) {
  if (date == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${date.year}/${two(date.month)}/${two(date.day)}';
}

/// A date the knitter can pick or clear, like "Started".
class DateField extends StatelessWidget {
  const DateField({super.key, required this.label, required this.value, required this.onChanged});

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    final shown = value == null ? 'Not set' : MaterialLocalizations.of(context).formatMediumDate(value!);
    return Row(
      children: [
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _pick(context),
            child: InputDecorator(
              decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
              child: Text(shown),
            ),
          ),
        ),
        if (value != null)
          IconButton(
            tooltip: 'Clear $label',
            onPressed: () => onChanged(null),
            icon: const Icon(Icons.close),
          ),
      ],
    );
  }

  Future<void> _pick(BuildContext context) async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: value ?? today,
      firstDate: DateTime(1950),
      lastDate: DateTime(today.year + 1),
      helpText: label,
    );
    if (picked != null) onChanged(picked);
  }
}

/// A short line on a record that has an unsent edit: waiting, needs a
/// choice, or refused. Says what to do, never relies on color alone.
class PendingEditNotice extends StatelessWidget {
  const PendingEditNotice({super.key, required this.edit, this.onResolve, this.onDiscard});

  final PendingEdit edit;
  final VoidCallback? onResolve;
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    final (icon, message, color) = switch (edit.state) {
      PendingEditState.waiting => (
          Icons.schedule,
          'Changes saved on this phone. Waiting to send to Ravelry.',
          PurlnoteColors.sand,
        ),
      PendingEditState.conflict => (
          Icons.call_split,
          'This was also changed on Ravelry. Choose which version to keep.',
          PurlnoteColors.blush,
        ),
      PendingEditState.failed => (
          Icons.error_outline,
          edit.problem ?? 'Ravelry refused this change.',
          PurlnoteColors.blush,
        ),
    };

    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: PurlnoteColors.plum),
                const SizedBox(width: 10),
                Expanded(child: Text(message, style: const TextStyle(fontSize: 15, height: 1.35))),
              ],
            ),
            if (edit.state == PendingEditState.conflict && onResolve != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: onResolve, child: const Text('Choose')),
              ),
            if (edit.state == PendingEditState.failed && onDiscard != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: onDiscard, child: const Text('Undo my change')),
              ),
          ],
        ),
      ),
    );
  }
}

/// What to call an edited field on screen.
String fieldLabel(String field) {
  return switch (field) {
    'name' => 'Name',
    'project_status_id' => 'Status',
    'progress' => 'Progress',
    'started' => 'Started',
    'completed' => 'Finished',
    'size' => 'Size',
    'notes' => 'Notes',
    'location' => 'Where it is',
    'dye_lot' => 'Dye lot',
    'stash_status_id' => 'Status',
    _ => field,
  };
}

/// A field's value in words, for comparing two versions.
String describeValue(String field, Object? value, AppSession session) {
  if (value == null || (value is String && value.trim().isEmpty)) return '(empty)';
  return switch (field) {
    'project_status_id' =>
      session.projectStatuses.where((status) => status.id == value).firstOrNull?.name ?? 'Status $value',
    'stash_status_id' => StashStatus.fromId((value as num).toInt()).label,
    'progress' => '$value%',
    _ => value.toString(),
  };
}

/// Fields where "Keep both" makes sense.
bool isFreeText(String field) => field == 'notes';
