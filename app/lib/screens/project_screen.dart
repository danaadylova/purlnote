import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_session.dart';
import '../data/local_database.dart';
import '../ravelry/models.dart';
import '../theme.dart';
import '../widgets/edit_widgets.dart';
import '../widgets/project_widgets.dart';
import '../library/library_models.dart';
import '../notes/project_comments.dart';
import '../projects/project_notes.dart';
import '../reader/reader_screen.dart';
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
          _PhotoStrip(session: session, project: project),
          const SizedBox(height: 16),
          Semantics(header: true, child: Text(project.name, style: text.headlineMedium)),
          if (status != null || project.isOnPhoneOnly) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (status != null) StatusChip(status: status),
                if (project.isOnPhoneOnly) const StatusChip(status: 'On this phone'),
              ],
            ),
          ],
          if (progress != null) ...[
            const SizedBox(height: 20),
            ProgressRow(percent: progress),
          ],
          const SizedBox(height: 20),
          _OpenPatternButton(session: session, project: project),
          const SizedBox(height: 12),
          _Detail(label: 'Pattern', value: project.patternName),
          _Detail(label: 'Craft', value: project.craftName),
          _Detail(label: 'Size', value: project.size),
          _Detail(label: 'Started', value: _formatDate(context, project.started)),
          _Detail(label: 'Finished', value: _formatDate(context, project.completed)),
          const SizedBox(height: 16),
          _NotesSection(session: session, project: project),
          const SizedBox(height: 24),
          if (session.canCommentOn(project.id)) _CommentsSection(session: session, project: project),
          if (project.isOnPhoneOnly) _PhoneOnlyActions(session: session, project: project),
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

/// Opens the project's pattern in the reader, with this project's counters
/// and saved spot. If the pattern isn't known, offers to pick one from the
/// library (for example a PDF bought elsewhere and imported).
class _OpenPatternButton extends StatelessWidget {
  const _OpenPatternButton({required this.session, required this.project});

  final AppSession session;
  final Project project;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LibraryPattern?>(
      future: session.patternForProject(project),
      builder: (context, snapshot) {
        final pattern = snapshot.data;
        if (pattern != null && pattern.isOnPhone) {
          return FilledButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => ReaderScreen(session: session, pattern: pattern, projectId: project.id),
            )),
            icon: const Icon(Icons.menu_book_outlined),
            label: const Text('Open pattern'),
          );
        }
        return OutlinedButton.icon(
          onPressed: () => _choosePattern(context),
          icon: const Icon(Icons.link),
          label: Text(pattern == null ? 'Choose the pattern PDF' : 'Download the pattern in Library'),
        );
      },
    );
  }

  Future<void> _choosePattern(BuildContext context) async {
    final onPhone = session.patterns.where((pattern) => pattern.isOnPhone).toList();
    final chosen = await showModalBottomSheet<LibraryPattern>(
      context: context,
      builder: (context) => SafeArea(
        child: onPhone.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No patterns on this phone yet. Download or import one in Library first.'),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  const ListTile(title: Text('Which pattern is this project using?')),
                  for (final pattern in onPhone)
                    ListTile(title: Text(pattern.title), onTap: () => Navigator.pop(context, pattern)),
                ],
              ),
      ),
    );
    if (chosen != null) await session.linkProjectToPattern(project.id, chosen.key);
  }
}

/// The project's comments: ones still waiting to post (with Cancel), and
/// the ones on Ravelry. A comment made from a pattern note starts with a tag
/// like "[Charts p.2 · row 31]"; tapping it opens the pattern at that page.
class _CommentsSection extends StatefulWidget {
  const _CommentsSection({required this.session, required this.project});

  final AppSession session;
  final Project project;

  @override
  State<_CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<_CommentsSection> {
  List<RavelryComment>? _comments;
  List<ProjectCommentRecord> _unsent = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final comments = await widget.session.loadComments(widget.project.id);
    final unsent = await widget.session.unsentComments(widget.project.id);
    if (!mounted) return;
    setState(() {
      _comments = comments;
      _unsent = unsent;
      _loaded = true;
    });
  }

  Future<void> _openAt(NoteTag tag) async {
    final pattern = await widget.session.patternForProject(widget.project);
    if (!mounted) return;
    if (pattern == null || !pattern.isOnPhone) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The pattern PDF isn\'t on this phone yet.')),
      );
      return;
    }
    final file = pattern.files.where((f) => f.isDownloaded && (tag.fileLabel == null || f.label == tag.fileLabel));
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ReaderScreen(
        session: widget.session,
        pattern: pattern,
        projectId: widget.project.id,
        startFileId: file.firstOrNull?.id,
        startPage: tag.page,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final comments = _comments;
    final username = widget.session.user?.username;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text('Comments', style: Theme.of(context).textTheme.titleMedium)),
        for (final waiting in _unsent)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(waiting.state == CommentState.failed ? Icons.error_outline : Icons.schedule),
            title: Text(waiting.body),
            subtitle: Text(waiting.problem ?? 'Waiting to send'),
            trailing: TextButton(
              onPressed: () async {
                await widget.session.cancelComment(waiting);
                await _load();
              },
              child: const Text('Cancel'),
            ),
          ),
        if (!_loaded)
          const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator())
        else if (comments == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Comments show when you\'re online.', style: TextStyle(color: PurlnoteColors.plumMuted)),
          )
        else if (comments.isEmpty && _unsent.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No comments yet. Notes you make on the pattern can be posted here.',
              style: TextStyle(color: PurlnoteColors.plumMuted),
            ),
          )
        else
          for (final comment in comments) _CommentTile(
            comment: comment,
            isMine: comment.author == username,
            onOpenPattern: _openAt,
            onDelete: () async {
              final problem = await widget.session.deleteComment(comment.id);
              if (problem != null && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
              }
              await _load();
            },
          ),
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.isMine,
    required this.onOpenPattern,
    required this.onDelete,
  });

  final RavelryComment comment;
  final bool isMine;
  final ValueChanged<NoteTag> onOpenPattern;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tag = NoteTag.parse(comment.body);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: PurlnoteColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    comment.author ?? 'Someone',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
                if (isMine)
                  IconButton(
                    tooltip: 'Delete comment',
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: onDelete,
                  ),
              ],
            ),
            Text(comment.body, style: const TextStyle(fontSize: 15, height: 1.4)),
            if (tag != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => onOpenPattern(tag),
                  icon: const Icon(Icons.menu_book_outlined, size: 18),
                  label: Text('Open at page ${tag.page}'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// For a project kept on this phone: add it to Ravelry (when an account is
/// connected), or delete it.
class _PhoneOnlyActions extends StatelessWidget {
  const _PhoneOnlyActions({required this.session, required this.project});

  final AppSession session;
  final Project project;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (session.connected)
          OutlinedButton.icon(
            onPressed: () async {
              final problem = await session.addProjectToRavelry(project.id);
              if (!context.mounted) return;
              if (problem != null) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
              } else {
                Navigator.of(context).pop();
              }
            },
            icon: const Icon(Icons.cloud_upload_outlined),
            label: const Text('Add this project to Ravelry'),
          ),
        TextButton.icon(
          onPressed: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Delete this project?'),
                content: const Text('Its counters and place in the pattern are removed. The pattern PDF and its notes stay.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                  TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
                ],
              ),
            );
            if (confirmed != true || !context.mounted) return;
            Navigator.of(context).pop();
            await session.deleteLocalProject(project.id);
          },
          icon: const Icon(Icons.delete_outline),
          label: const Text('Delete project'),
        ),
      ],
    );
  }
}

/// The project's photos in a row, with a tile to add one. Tap a photo to see
/// it large and delete it.
class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({required this.session, required this.project});

  final AppSession session;
  final Project project;

  static const size = 112.0;

  Future<void> _add(BuildContext context) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from Photos'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    // Ravelry keeps photos at up to 1600 px, so larger ones are scaled first.
    final picked = await ImagePicker().pickImage(source: source, maxWidth: 2000, maxHeight: 2000, imageQuality: 88);
    if (picked == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (!project.isOnPhoneOnly) messenger.showSnackBar(const SnackBar(content: Text('Adding the photo to Ravelry…')));
    final problem = await session.addProjectPhoto(project.id, await picked.readAsBytes(), picked.name);
    messenger.hideCurrentSnackBar();
    if (problem != null) messenger.showSnackBar(SnackBar(content: Text(problem)));
  }

  Future<void> _open(BuildContext context, ProjectPicture picture) async {
    final delete = await Navigator.of(context).push<bool>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          actions: [
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete'),
            ),
          ],
        ),
        body: Center(child: InteractiveViewer(child: _image(picture, large: true))),
      ),
    ));
    if (delete != true || !context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this photo?'),
        content: Text(project.isOnPhoneOnly ? 'It\'s removed from this phone.' : 'It\'s removed from the project on Ravelry.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final problem = await session.deleteProjectPhoto(project.id, picture);
    if (problem != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
    }
  }

  static Widget _image(ProjectPicture picture, {bool large = false}) {
    const missing = ColoredBox(color: PurlnoteColors.sand, child: Center(child: Icon(Icons.image_not_supported_outlined)));
    final path = picture.localPath;
    if (path != null) {
      return Image.file(File(path), fit: large ? BoxFit.contain : BoxFit.cover, errorBuilder: (context, error, stack) => missing);
    }
    final url = large ? picture.url : (picture.thumbnailUrl ?? picture.url);
    if (url == null) return missing;
    return Image.network(url, fit: large ? BoxFit.contain : BoxFit.cover, errorBuilder: (context, error, stack) => missing);
  }

  @override
  Widget build(BuildContext context) {
    final pictures = project.pictures;
    return SizedBox(
      height: size,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i < pictures.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Semantics(
                button: true,
                label: 'Photo ${i + 1} of ${pictures.length}. Open or delete.',
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: () => _open(context, pictures[i]),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox.square(dimension: size, child: _image(pictures[i])),
                  ),
                ),
              ),
            ),
          Semantics(
            button: true,
            label: 'Add a photo',
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _add(context),
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: PurlnoteColors.inputBorder),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_a_photo_outlined, color: PurlnoteColors.moss),
                    SizedBox(height: 4),
                    Text('Add photo', style: TextStyle(color: PurlnoteColors.moss, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The project's notes, one entry at a time, with Add note. Tap a note to
/// change or delete it.
class _NotesSection extends StatelessWidget {
  const _NotesSection({required this.session, required this.project});

  final AppSession session;
  final Project project;

  Future<String?> _askForText(BuildContext context, {required String title, String? initial, bool canDelete = false}) {
    final text = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: text,
          autofocus: true,
          minLines: 3,
          maxLines: 10,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'Tried on after the yoke; body length +2 cm',
            helperText: project.isOnPhoneOnly ? null : 'Project notes are public on Ravelry.',
          ),
        ),
        actions: [
          if (canDelete) TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('Delete')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, text.text), child: const Text('Save')),
        ],
      ),
    );
  }

  Future<void> _add(BuildContext context) async {
    final text = await _askForText(context, title: 'New note');
    if (text == null || text.trim().isEmpty || !context.mounted) return;
    _report(context, await session.addProjectNote(project.id, text));
  }

  Future<void> _edit(BuildContext context, int index, String entry) async {
    final text = await _askForText(context, title: 'Note', initial: entry, canDelete: true);
    if (text == null || !context.mounted) return;
    _report(context, await session.editProjectNote(project.id, index, text.isEmpty ? null : text));
  }

  void _report(BuildContext context, String? problem) {
    if (problem != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = noteEntries(project.notes);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text('Notes · ${entries.length}', style: Theme.of(context).textTheme.titleMedium),
              ),
            ),
            TextButton.icon(onPressed: () => _add(context), icon: const Icon(Icons.add), label: const Text('Add note')),
          ],
        ),
        if (entries.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text('No notes yet.', style: TextStyle(color: PurlnoteColors.plumMuted)),
          ),
        for (var i = 0; i < entries.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: PurlnoteColors.line),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _edit(context, i, entries[i]),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: double.infinity,
                    child: Text(entries[i], style: const TextStyle(fontSize: 15, height: 1.4)),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
