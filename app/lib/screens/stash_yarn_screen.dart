import 'package:flutter/material.dart';

import '../app_session.dart';
import '../data/local_database.dart';
import '../ravelry/models.dart';
import '../theme.dart';
import '../widgets/edit_widgets.dart';
import 'edit_conflict_screen.dart';

/// One stash yarn: what it is, and the parts the knitter keeps up to date
/// (where it is, its status, dye lot and notes).
class StashYarnScreen extends StatefulWidget {
  const StashYarnScreen({super.key, required this.session, required this.yarnId});

  final AppSession session;
  final int yarnId;

  @override
  State<StashYarnScreen> createState() => _StashYarnScreenState();
}

class _StashYarnScreenState extends State<StashYarnScreen> {
  final _location = TextEditingController();
  final _dyeLot = TextEditingController();
  final _notes = TextEditingController();
  StashStatus _status = StashStatus.inStash;

  /// The yarn as it was when the form was last filled in.
  StashYarn? _shown;

  @override
  void initState() {
    super.initState();
    _fillForm();
    widget.session.loadFullRecord(RecordType.stash, widget.yarnId).then((_) {
      // Fill again with the full details, unless the knitter already started typing.
      if (mounted && !_hasChanges) setState(_fillForm);
    });
  }

  void _fillForm() {
    final yarn = widget.session.stashById(widget.yarnId);
    if (yarn == null) return;
    _shown = yarn;
    _location.text = yarn.location ?? '';
    _dyeLot.text = yarn.dyeLot ?? '';
    _notes.text = yarn.notes ?? '';
    _status = yarn.status;
  }

  @override
  void dispose() {
    _location.dispose();
    _dyeLot.dispose();
    _notes.dispose();
    super.dispose();
  }

  Map<String, Object?> _changes() {
    final before = _shown!;
    return {
      if (_location.text.trim() != (before.location ?? '')) 'location': _location.text.trim(),
      if (_dyeLot.text.trim() != (before.dyeLot ?? '')) 'dye_lot': _dyeLot.text.trim(),
      if (_notes.text.trim() != (before.notes ?? '')) 'notes': _notes.text.trim(),
      if (_status != before.status) 'stash_status_id': _status.ravelryId,
    };
  }

  bool get _hasChanges => _shown != null && _changes().isNotEmpty;

  Future<void> _save() async {
    await widget.session.saveEdit(RecordType.stash, widget.yarnId, _changes());
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild when the session changes, for example when the edit is sent.
    return ListenableBuilder(listenable: widget.session, builder: (context, _) => _buildScreen(context));
  }

  Widget _buildScreen(BuildContext context) {
    final yarn = widget.session.stashById(widget.yarnId);
    if (yarn == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('This yarn is no longer in your stash.')));
    }
    final pendingEdit = widget.session.pendingEditFor(RecordType.stash, yarn.id);
    final about = [yarn.companyName, yarn.weightName].whereType<String>().join(' · ');

    return Scaffold(
      appBar: AppBar(actions: [TextButton(onPressed: _save, child: const Text('Save'))]),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          if (pendingEdit != null) ...[
            PendingEditNotice(
              edit: pendingEdit,
              onResolve: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => EditConflictScreen(session: widget.session, edit: pendingEdit),
              )),
              onDiscard: () => widget.session.discardEdit(pendingEdit).then((_) => setState(_fillForm)),
            ),
            const SizedBox(height: 16),
          ],
          Semantics(header: true, child: Text(yarn.name, style: Theme.of(context).textTheme.headlineMedium)),
          if (about.isNotEmpty) Text(about, style: const TextStyle(color: PurlnoteColors.plumMuted, fontSize: 15)),
          if (yarn.colorway != null) ...[
            const SizedBox(height: 4),
            Text('Colorway: ${yarn.colorway}', style: const TextStyle(fontSize: 16)),
          ],
          const SizedBox(height: 24),
          DropdownButtonFormField<StashStatus>(
            initialValue: _status,
            decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
            items: [for (final status in StashStatus.values) DropdownMenuItem(value: status, child: Text(status.label))],
            onChanged: (status) => setState(() => _status = status ?? _status),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _location,
            decoration: const InputDecoration(
              labelText: 'Where it is',
              hintText: 'Blue bin under the bed',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _dyeLot,
            decoration: const InputDecoration(labelText: 'Dye lot', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _notes,
            minLines: 3,
            maxLines: 10,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Notes', alignLabelWithHint: true, border: OutlineInputBorder()),
          ),
          const SizedBox(height: 24),
          const Text(
            'Changes save on this phone right away and go to Ravelry when you\'re online.',
            style: TextStyle(color: PurlnoteColors.plumMuted),
          ),
        ],
      ),
    );
  }
}
