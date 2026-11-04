import 'package:flutter/material.dart';

import '../app_session.dart';
import '../data/outbox.dart';
import '../data/pending_edit.dart';
import '../theme.dart';
import '../widgets/edit_widgets.dart';

/// Shown when a record was changed both on this phone and on Ravelry. For
/// each field changed on both sides, the knitter picks which version to keep;
/// for notes they can keep both. "Decide later" leaves the edit waiting.
class EditConflictScreen extends StatefulWidget {
  const EditConflictScreen({super.key, required this.session, required this.edit});

  final AppSession session;
  final PendingEdit edit;

  @override
  State<EditConflictScreen> createState() => _EditConflictScreenState();
}

class _EditConflictScreenState extends State<EditConflictScreen> {
  /// Starts on "mine": the knitter made these edits on purpose.
  late final Map<String, ConflictChoice> _choices = {
    for (final field in widget.edit.conflictingFields) field: ConflictChoice.mine,
  };

  Future<void> _save() async {
    await widget.session.resolveConflict(widget.edit, _choices);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final edit = widget.edit;
    return Scaffold(
      appBar: AppBar(title: Semantics(header: true, child: const Text('Choose which to keep'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const Text(
            'You changed these on this phone, and they were also changed on Ravelry. '
            'Pick a version for each.',
            style: TextStyle(fontSize: 16, height: 1.4),
          ),
          const SizedBox(height: 8),
          for (final field in edit.conflictingFields)
            _FieldChoice(
              label: fieldLabel(field),
              mine: describeValue(field, edit.changes[field], widget.session),
              theirs: describeValue(field, edit.theirValues[field], widget.session),
              allowBoth: isFreeText(field),
              choice: _choices[field]!,
              onChanged: (choice) => setState(() => _choices[field] = choice),
            ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('Save my choices')),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Decide later'),
          ),
        ],
      ),
    );
  }
}

/// One field with "On this phone", "On Ravelry" and maybe "Keep both".
class _FieldChoice extends StatelessWidget {
  const _FieldChoice({
    required this.label,
    required this.mine,
    required this.theirs,
    required this.allowBoth,
    required this.choice,
    required this.onChanged,
  });

  final String label;
  final String mine;
  final String theirs;
  final bool allowBoth;
  final ConflictChoice choice;
  final ValueChanged<ConflictChoice> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(header: true, child: Text(label, style: Theme.of(context).textTheme.titleMedium)),
          RadioGroup<ConflictChoice>(
            groupValue: choice,
            onChanged: (value) => onChanged(value ?? choice),
            child: Column(
              children: [
                _option(ConflictChoice.mine, 'On this phone', mine),
                _option(ConflictChoice.theirs, 'On Ravelry', theirs),
                if (allowBoth) _option(ConflictChoice.both, 'Keep both', 'Ravelry\'s text, then yours'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _option(ConflictChoice value, String title, String detail) {
    return RadioListTile<ConflictChoice>(
      value: value,
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(detail, style: const TextStyle(color: PurlnoteColors.plum, fontSize: 15)),
    );
  }
}
