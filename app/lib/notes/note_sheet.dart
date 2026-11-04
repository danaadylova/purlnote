import 'package:flutter/material.dart';

import '../theme.dart';

/// Where a note on the pattern goes.
enum NoteDestination {
  /// Only on the page, on this phone.
  pageOnly('Keep on the page only', 'Only you see it, on this phone.'),

  /// Posted as a comment on the project. Public.
  projectComment('Project comment', 'Posted on the project. Anyone who can see the project can read it.'),

  /// Added as a dated line to the project's notes. Public.
  projectNotes('Project notes', 'Added as a dated line in the project\'s notes on Ravelry.');

  const NoteDestination(this.label, this.explanation);

  final String label;
  final String explanation;
}

/// What the knitter wrote, and where it should go.
typedef NoteResult = ({String text, NoteDestination destination});

/// The New note sheet: the note's text and where it goes.
///
/// [projectName] is null when reading outside a project; then the note can
/// only stay on the page. [initialDestination] is the last choice made for
/// this project.
Future<NoteResult?> showNoteSheet(
  BuildContext context, {
  required String? projectName,
  required NoteDestination initialDestination,
  required String tag,
}) {
  return showModalBottomSheet<NoteResult>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _NoteSheet(projectName: projectName, initialDestination: initialDestination, tag: tag),
  );
}

class _NoteSheet extends StatefulWidget {
  const _NoteSheet({required this.projectName, required this.initialDestination, required this.tag});

  final String? projectName;
  final NoteDestination initialDestination;
  final String tag;

  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  final _text = TextEditingController();
  late NoteDestination _destination =
      widget.projectName == null ? NoteDestination.pageOnly : widget.initialDestination;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final projectName = widget.projectName;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(header: true, child: Text('New note', style: Theme.of(context).textTheme.titleLarge)),
            const SizedBox(height: 4),
            Text(widget.tag, style: const TextStyle(color: PurlnoteColors.plumMuted)),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              autofocus: true,
              minLines: 2,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Switched to 3.75 mm here',
                border: OutlineInputBorder(),
              ),
            ),
            if (projectName != null) ...[
              const SizedBox(height: 16),
              Text('Notes go to project: $projectName', style: const TextStyle(fontWeight: FontWeight.w700)),
              RadioGroup<NoteDestination>(
                groupValue: _destination,
                onChanged: (value) => setState(() => _destination = value ?? _destination),
                child: Column(
                  children: [
                    for (final destination in NoteDestination.values)
                      RadioListTile<NoteDestination>(
                        value: destination,
                        contentPadding: EdgeInsets.zero,
                        title: Text(destination.label),
                        subtitle: Text(destination.explanation),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                final text = _text.text.trim();
                if (text.isEmpty) return;
                Navigator.pop(context, (text: text, destination: _destination));
              },
              child: Text(_destination == NoteDestination.projectComment ? 'Save and post' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Explains, before the first note goes to a project, why Ravelry will ask to
/// "write messages". Returns true to go ahead.
Future<bool> explainCommentPermission(BuildContext context) async {
  final goAhead = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Allow posting comments'),
      content: const Text(
        'To post notes as project comments, Ravelry needs to give Purlnote its "write messages" permission. '
        'Ravelry groups comments and private messages together; Purlnote only posts the comments you send '
        'and never sends private messages.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep on the page')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue to Ravelry')),
      ],
    ),
  );
  return goAhead ?? false;
}
