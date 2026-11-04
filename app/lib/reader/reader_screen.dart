import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../app_session.dart';
import '../library/library_models.dart';
import '../notes/note_sheet.dart';
import '../notes/project_comments.dart';
import '../theme.dart';
import 'awake_timer.dart';
import 'counters_bar.dart';
import 'page_marks.dart';
import 'reader_store.dart';

/// The pattern reader: a pattern's PDFs with the knitter's marks on top,
/// the project's counters underneath, and the screen kept awake.
///
/// Opens where the knitter left off: the project's last file and page, or
/// for reading outside a project, the last page read in that file.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.session,
    required this.pattern,
    this.projectId,
    this.startFileId,
    this.startPage,
  });

  final AppSession session;
  final LibraryPattern pattern;

  /// The project being knitted, if opened from one. Counters and the saved
  /// spot belong to it.
  final int? projectId;

  /// Opens this file and page instead of the saved spot (for example, from
  /// a comment tagged with a page).
  final int? startFileId;
  final int? startPage;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final _viewer = PdfViewerController();
  final _awake = AwakeTimer();

  ReaderStore get _store => widget.session.reader;
  int get _projectId => widget.projectId ?? ReaderStore.noProject;

  List<PatternFile> _files = const [];
  PatternFile? _file;
  int _startPage = 1;
  int? _page;
  List<Annotation> _marks = const [];
  List<ProjectCounter> _counters = const [];
  ReaderTool _tool = ReaderTool.none;
  bool _rulerOn = false;

  /// Where the row ruler sits, as a fraction of the reading area's height.
  double _rulerAt = 0.4;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    _awake.stop();
    widget.session.backUpNotes();
    super.dispose();
  }

  Future<void> _open() async {
    final files = widget.pattern.files.where((file) => file.isDownloaded).toList();
    final lastFileId = widget.startFileId ??
        (widget.projectId == null ? null : await _store.lastFileFor(_projectId, files));
    final file = files.where((f) => f.id == lastFileId).firstOrNull ?? files.firstOrNull;

    final awakeSetting = await widget.session.library.awakeMinutes(widget.pattern.key);
    _awake.start(awakeSetting ?? AwakeTimer.defaultMinutes);

    final counters = widget.projectId == null ? <ProjectCounter>[] : await _store.countersFor(_projectId);
    setState(() {
      _files = files;
      _counters = counters;
    });
    if (file != null) await _showFile(file, page: widget.startPage);
    setState(() => _loading = false);
  }

  Future<void> _showFile(PatternFile file, {int? page}) async {
    final savedPage = page ?? await _store.savedPage(file.id, projectId: _projectId);
    final marks = await _store.annotationsFor(file.sha256!);
    setState(() {
      _file = file;
      _startPage = savedPage ?? 1;
      _page = _startPage;
      _marks = marks;
    });
    if (savedPage != null && page == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Back where you left off · page $savedPage'), duration: const Duration(seconds: 2)),
      );
    }
  }

  Future<void> _reloadMarks() async {
    final marks = await _store.annotationsFor(_file!.sha256!);
    setState(() => _marks = marks);
  }

  void _pageChanged(int? page) {
    if (page == null || _file == null) return;
    setState(() => _page = page);
    _store.savePage(_file!.id, page, projectId: _projectId);
  }

  // Marks ------------------------------------------------------------------

  Future<void> _addMark(int page, AnnotationKind kind, List<Offset> points) async {
    await _store.addAnnotation(fileSha256: _file!.sha256!, page: page, kind: kind, points: points);
    await _reloadMarks();
  }

  Future<void> _erase(Annotation mark) async {
    await _store.deleteAnnotation(mark.id);
    await _reloadMarks();
  }

  /// Where in the pattern a note is: page, file (if there are several) and
  /// the row counter.
  NoteTag _tagFor(int page) {
    return NoteTag(
      page: page,
      fileLabel: _files.length > 1 ? _file!.label : null,
      row: _counters.isEmpty ? null : _counters.first.value,
    );
  }

  Future<void> _placeNote(int page, Offset at) async {
    final projectId = widget.projectId;
    final tag = _tagFor(page);
    final result = await showNoteSheet(
      context,
      projectName: projectId == null ? null : widget.session.projectById(projectId)?.name,
      initialDestination:
          projectId == null ? NoteDestination.pageOnly : await widget.session.noteDestinationFor(projectId),
      tag: tag.text,
    );
    if (result == null) return;

    // The note always stays on the page, wherever else it goes.
    final noteId = await _store.addAnnotation(
      fileSha256: _file!.sha256!,
      page: page,
      kind: AnnotationKind.note,
      points: [at],
      text: result.text,
    );
    await _reloadMarks();
    if (projectId == null) return;

    var destination = result.destination;
    if (destination == NoteDestination.projectComment && !await _ensureCommentPermission()) {
      destination = NoteDestination.pageOnly;
    }
    await widget.session.sendNoteToProject(
      projectId: projectId,
      text: result.text,
      destination: destination,
      tag: tag,
      annotationId: noteId,
    );
    if (destination == NoteDestination.projectComment && mounted) {
      _say('Saved. It posts to the project when you\'re online.');
    }
  }

  /// Asks for the comment permission the first time. False if not granted.
  Future<bool> _ensureCommentPermission() async {
    if (await widget.session.canPostComments()) return true;
    if (!mounted || !await explainCommentPermission(context)) return false;
    final problem = await widget.session.allowComments();
    if (problem != null && mounted) _say(problem);
    return problem == null;
  }

  Future<void> _openNote(Annotation note) async {
    final text = await _editNoteText(context, title: 'Note on page ${note.page}', initial: note.text, canDelete: true);
    if (text == null) return;
    final comment = await widget.session.commentForNote(note.id);

    if (text.isEmpty) {
      await _store.deleteAnnotation(note.id);
      await _reloadMarks();
      if (comment != null) await _deleteCommentToo(comment);
      return;
    }

    final newText = text.trim();
    if (newText == note.text) return;
    await _store.updateNoteText(note.id, newText);
    await _reloadMarks();
    if (comment != null) await _updateComment(note, comment, newText);
  }

  Future<void> _deleteCommentToo(ProjectCommentRecord comment) async {
    if (comment.state != CommentState.posted) {
      await widget.session.cancelComment(comment);
      return;
    }
    final alsoRavelry = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete the comment on Ravelry too?'),
        content: const Text('This note was posted as a comment on the project.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep the comment')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete it')),
        ],
      ),
    );
    if (alsoRavelry == true) {
      final problem = await widget.session.deleteComment(comment.postedCommentId!);
      if (problem != null && mounted) _say(problem);
    }
  }

  /// Ravelry comments can't be edited, only deleted, so an edited note offers
  /// to replace the comment or add a correction.
  Future<void> _updateComment(Annotation note, ProjectCommentRecord comment, String newText) async {
    final projectId = comment.projectId;
    final tag = NoteTag.parse(comment.body) ?? _tagFor(note.page);

    if (comment.state != CommentState.posted) {
      // Not posted yet: just send the new text instead.
      await widget.session.cancelComment(comment);
      await widget.session.sendNoteToProject(
        projectId: projectId,
        text: newText,
        destination: NoteDestination.projectComment,
        tag: tag,
        annotationId: note.id,
      );
      return;
    }

    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Update the comment on Ravelry?'),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text('Ravelry comments can\'t be edited, only deleted.'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'replace'),
            child: const Text('Delete it and post the new text'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'correct'),
            child: const Text('Keep it and post a correction'),
          ),
          SimpleDialogOption(onPressed: () => Navigator.pop(context), child: const Text('Only change it here')),
        ],
      ),
    );
    if (choice == null) return;
    if (choice == 'replace') {
      final problem = await widget.session.deleteComment(comment.postedCommentId!);
      if (problem != null) {
        if (mounted) _say(problem);
        return;
      }
    }
    await widget.session.sendNoteToProject(
      projectId: projectId,
      text: choice == 'correct' ? 'Correction: $newText' : newText,
      destination: NoteDestination.projectComment,
      tag: tag,
      annotationId: note.id,
    );
  }

  void _say(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showNotesList() {
    final notes = _marks.where((mark) => mark.kind == AnnotationKind.note).toList()
      ..sort((a, b) => a.page.compareTo(b.page));
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: notes.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No notes in this file yet. Choose Note, then tap the page.'),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final note in notes)
                    ListTile(
                      leading: const Icon(Icons.push_pin_outlined),
                      title: Text(note.text ?? ''),
                      subtitle: Text('Page ${note.page}'),
                      onTap: () {
                        Navigator.pop(context);
                        _viewer.goToPage(pageNumber: note.page);
                      },
                    ),
                ],
              ),
      ),
    );
  }

  // Counters and screen awake ------------------------------------------------

  Future<void> _setRows(int rows) async {
    await _store.setCounterValue(_counters.first.id, rows);
    final counters = await _store.countersFor(_projectId);
    setState(() => _counters = counters);
  }

  Future<void> _addRepeatCounter() async {
    final details = await askForRepeatCounter(context);
    if (details == null) return;
    await _store.addRepeatCounter(
      projectId: _projectId,
      label: details.label,
      everyNRows: details.every,
      totalRepeats: details.times,
      startRow: _counters.first.value,
    );
    final counters = await _store.countersFor(_projectId);
    setState(() => _counters = counters);
  }

  Future<void> _removeCounter(ProjectCounter counter) async {
    await _store.deleteCounter(counter.id);
    final counters = await _store.countersFor(_projectId);
    setState(() => _counters = counters);
  }

  Future<void> _setAwake(int minutes) async {
    await widget.session.library.setAwakeMinutes(widget.pattern.key, minutes);
    setState(() => _awake.start(minutes));
  }

  // Layout -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final file = _file;
    final noteCount = _marks.where((mark) => mark.kind == AnnotationKind.note).length;

    return Listener(
      // Every touch keeps the screen awake a little longer.
      onPointerDown: (_) => _awake.touched(),
      child: Scaffold(
        backgroundColor: PurlnoteColors.sand,
        appBar: AppBar(
          backgroundColor: Colors.white,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(header: true, child: Text(widget.pattern.title, style: const TextStyle(fontSize: 16))),
              if (file != null)
                Text(
                  '${file.label} · page ${_page ?? 1}',
                  style: const TextStyle(fontSize: 12, color: PurlnoteColors.plumMuted),
                ),
            ],
          ),
          actions: [
            _AwakeMenu(minutes: _awake.minutes, onChanged: _setAwake),
            IconButton(
              tooltip: noteCount == 0 ? 'Notes' : '$noteCount notes',
              onPressed: _showNotesList,
              icon: Badge(isLabelVisible: noteCount > 0, label: Text('$noteCount'), child: const Icon(Icons.notes)),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : file == null
                ? const _NothingDownloaded()
                : Column(
                    children: [
                      if (_files.length > 1)
                        _FileSwitcher(files: _files, current: file, onChanged: (f) => _showFile(f)),
                      Expanded(child: _buildPages(file)),
                      _Toolbar(
                        tool: _tool,
                        rulerOn: _rulerOn,
                        onTool: (tool) => setState(() {
                          if (tool == ReaderTool.ruler) {
                            _rulerOn = !_rulerOn;
                          } else {
                            _tool = _tool == tool ? ReaderTool.none : tool;
                          }
                        }),
                      ),
                      if (_counters.isNotEmpty)
                        Container(
                          color: Colors.white,
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                          child: SafeArea(
                            top: false,
                            child: CountersBar(
                              counters: _counters,
                              onRowsChanged: _setRows,
                              onAddRepeat: _addRepeatCounter,
                              onRemove: _removeCounter,
                            ),
                          ),
                        ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildPages(PatternFile file) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            PdfViewer.file(
              file.localPath!,
              key: ValueKey(file.id),
              controller: _viewer,
              initialPageNumber: _startPage,
              params: PdfViewerParams(
                backgroundColor: PurlnoteColors.sand,
                // While drawing, touches on the page draw instead of scrolling.
                panEnabled: !_tool.drawsOnPage,
                scaleEnabled: !_tool.drawsOnPage,
                onPageChanged: _pageChanged,
                pageOverlaysBuilder: (context, pageRect, page) => [
                  PageMarks(
                    page: page.pageNumber,
                    marks: _marks.where((mark) => mark.page == page.pageNumber).toList(),
                    tool: _tool,
                    onAdd: (kind, points) => _addMark(page.pageNumber, kind, points),
                    onErase: _erase,
                    onOpenNote: _openNote,
                    onPlaceNote: (at) => _placeNote(page.pageNumber, at),
                  ),
                ],
              ),
            ),
            if (_rulerOn)
              _RowRuler(
                top: _rulerAt * constraints.maxHeight,
                height: constraints.maxHeight,
                onMoved: (dy) => setState(() {
                  _rulerAt = ((_rulerAt * constraints.maxHeight + dy) / constraints.maxHeight).clamp(0.0, 0.95);
                }),
              ),
          ],
        );
      },
    );
  }
}

/// Tabs for up to three files; past three, a menu.
class _FileSwitcher extends StatelessWidget {
  const _FileSwitcher({required this.files, required this.current, required this.onChanged});

  final List<PatternFile> files;
  final PatternFile current;
  final ValueChanged<PatternFile> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      width: double.infinity,
      child: files.length <= 3
          ? SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                for (final file in files)
                  ButtonSegment(value: file.id, label: Text(file.label, overflow: TextOverflow.ellipsis)),
              ],
              selected: {current.id},
              onSelectionChanged: (ids) => onChanged(files.firstWhere((file) => file.id == ids.first)),
            )
          : DropdownButtonFormField<int>(
              initialValue: current.id,
              decoration: const InputDecoration(labelText: 'File', border: OutlineInputBorder()),
              items: [for (final file in files) DropdownMenuItem(value: file.id, child: Text(file.label))],
              onChanged: (id) => onChanged(files.firstWhere((file) => file.id == id)),
            ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.tool, required this.rulerOn, required this.onTool});

  final ReaderTool tool;
  final bool rulerOn;
  final ValueChanged<ReaderTool> onTool;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          for (final option in ReaderTool.values.where((t) => t != ReaderTool.none))
            Expanded(
              child: _ToolButton(
                tool: option,
                selected: option == ReaderTool.ruler ? rulerOn : tool == option,
                onPressed: () => onTool(option),
              ),
            ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.tool, required this.selected, required this.onPressed});

  final ReaderTool tool;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: tool.label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onPressed,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: selected ? PurlnoteColors.blush : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(tool.icon, size: 22, color: PurlnoteColors.plum),
              const SizedBox(height: 2),
              Text(
                tool.label,
                style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.w700 : FontWeight.w400),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A band across the page that dims everything but the current row. Drag it
/// up or down.
class _RowRuler extends StatelessWidget {
  const _RowRuler({required this.top, required this.height, required this.onMoved});

  final double top;
  final double height;
  final ValueChanged<double> onMoved;

  static const bandHeight = 40.0;
  static const _dim = Color(0x66FFF8EE);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(top: 0, left: 0, right: 0, height: top, child: const IgnorePointer(child: ColoredBox(color: _dim))),
        Positioned(
          top: top + bandHeight,
          left: 0,
          right: 0,
          bottom: 0,
          child: const IgnorePointer(child: ColoredBox(color: _dim)),
        ),
        Positioned(
          top: top,
          left: 0,
          right: 0,
          height: bandHeight,
          child: Semantics(
            label: 'Row ruler. Drag up or down.',
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onVerticalDragUpdate: (details) => onMoved(details.delta.dy),
              child: Container(
                decoration: const BoxDecoration(
                  border: Border.symmetric(horizontal: BorderSide(color: PurlnoteColors.marigoldDark, width: 2)),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The chip that shows and changes how long the screen stays awake.
class _AwakeMenu extends StatelessWidget {
  const _AwakeMenu({required this.minutes, required this.onChanged});

  final int minutes;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: 'Keep screen awake: ${AwakeTimer.describe(minutes)}',
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final choice in AwakeTimer.choices)
          CheckedPopupMenuItem(value: choice, checked: choice == minutes, child: Text(AwakeTimer.describe(choice))),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Chip(
          avatar: const Icon(Icons.light_mode_outlined, size: 16),
          label: Text(minutes == AwakeTimer.off ? 'Awake off' : 'Awake · ${AwakeTimer.describe(minutes)}'),
          backgroundColor: PurlnoteColors.blush,
          side: BorderSide.none,
        ),
      ),
    );
  }
}

class _NothingDownloaded extends StatelessWidget {
  const _NothingDownloaded();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'None of this pattern\'s PDFs are on this phone yet. Download them from the Library.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

/// Asks for a note's text. Returns null if cancelled, and an empty string if
/// the knitter chose Delete.
Future<String?> _editNoteText(BuildContext context, {required String title, String? initial, bool canDelete = false}) {
  final text = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: text,
        autofocus: true,
        minLines: 2,
        maxLines: 6,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Switched to 3.75 mm here'),
      ),
      actions: [
        if (canDelete) TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('Delete')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, text.text), child: const Text('Save')),
      ],
    ),
  );
}
