import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderProxyBox;
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../app_session.dart';
import '../library/library_models.dart';
import '../notes/note_sheet.dart';
import '../notes/project_comments.dart';
import '../steps/steps_view.dart';
import '../layout.dart';
import '../theme.dart';
import 'awake_timer.dart';
import 'counters_bar.dart';
import 'page_marks.dart';
import 'reader_store.dart';
import 'row_ruler.dart';

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
  /// The row ruler, if it has been used in this file.
  RulerPosition? _ruler;

  /// While the ruler is being dragged: how far below the band's top edge the
  /// finger is, in pixels. Null when it isn't being dragged.
  double? _rulerGrab;

  /// One key per page on screen, to find where each page is while the ruler
  /// is dragged from one page to another.
  final _pageKeys = <int, GlobalKey>{};
  bool _loading = true;

  /// Showing the Steps view instead of the PDF page.
  ReaderView _view = ReaderView.page;

  /// Whether the bars (or, sideways, the floating controls) are showing.
  /// Tapping the page, or Hide, hides them; the choice is remembered for
  /// the next pattern too.
  bool _controlsShown = true;

  static const _barsHiddenSetting = 'reader_bars_hidden';

  /// The tools tray's height as last laid out, so the page can end just
  /// above it, with only the tray's rounded corners over the page.
  double _trayHeight = 0;

  double get _pageBottomInset {
    final inset = _trayHeight - _ToolsTray.cornerRadius;
    return inset > 0 ? inset : 0;
  }

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

    _controlsShown = await widget.session.database.setting(_barsHiddenSetting) != 'true';

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
    final ruler = await _store.savedRuler(file.id, projectId: _projectId);
    _pageKeys.clear();
    setState(() {
      _file = file;
      _startPage = savedPage ?? 1;
      _page = _startPage;
      _marks = marks;
      _ruler = ruler;
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
    final lastDestination =
        projectId == null ? NoteDestination.pageOnly : await widget.session.noteDestinationFor(projectId);
    if (!mounted) return;
    final result = await showNoteSheet(
      context,
      projectName: projectId == null ? null : widget.session.projectById(projectId)?.name,
      initialDestination: lastDestination,
      tag: tag.text,
      allowComments: projectId != null && widget.session.canCommentOn(projectId),
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

  // Row ruler ----------------------------------------------------------------

  /// Turns the ruler on (where it was left, or on the current page) or off.
  void _toggleRuler() {
    final ruler = _ruler;
    _saveRuler(ruler == null ? RulerPosition.startOn(_page ?? 1) : ruler.copyWith(visible: !ruler.visible));
  }

  /// One small step up (-1) or down (1). Crossing onto another page scrolls
  /// there, so the ruler stays in view.
  void _moveRuler(int direction) {
    final ruler = _ruler;
    if (ruler == null) return;
    final pageCount = _viewer.isReady ? _viewer.pageCount : ruler.page;
    final moved = ruler.movedBy(direction * ruler.step, pageCount: pageCount);
    if (moved.page != ruler.page && _viewer.isReady) _viewer.goToPage(pageNumber: moved.page);
    _saveRuler(moved);
  }

  void _resizeRuler(int direction) {
    final ruler = _ruler;
    if (ruler != null) _saveRuler(ruler.resizedBy(direction * 0.005));
  }

  void _saveRuler(RulerPosition ruler) {
    setState(() => _ruler = ruler);
    _store.saveRuler(_file!.id, ruler, projectId: _projectId);
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

  void _showControls(bool shown) {
    setState(() => _controlsShown = shown);
    widget.session.database.saveSetting(_barsHiddenSetting, shown ? 'false' : 'true');
  }

  /// Scrolls the pattern so the ruler is in the middle of the screen, for
  /// when the knitter has read ahead or zoomed elsewhere.
  void _goToRuler() {
    final ruler = _ruler;
    if (ruler == null || !_viewer.isReady) return;
    final pages = _viewer.layout.pageLayouts;
    if (ruler.page < 1 || ruler.page > pages.length) return;
    final page = pages[ruler.page - 1];
    final middle = page.top + page.height * (ruler.top + ruler.height / 2);
    _viewer.goToArea(
      rect: Rect.fromLTWH(page.left, middle - 1, page.width, 2),
      anchor: PdfPageAnchor.center,
    );
  }

  /// Taps on the page hide or show the bars, unless a tool is in use, so
  /// drawing or pinning a note never hides them by accident.
  VoidCallback? get _pageTap => _tool == ReaderTool.none ? () => _showControls(!_controlsShown) : null;

  Future<void> _setAwake(int minutes) async {
    await widget.session.library.setAwakeMinutes(widget.pattern.key, minutes);
    setState(() => _awake.start(minutes));
  }

  // Layout -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final file = _file;
    final noteCount = _marks.where((mark) => mark.kind == AnnotationKind.note).length;

    if (!_loading && file != null && _isSideways(context)) {
      return Listener(
        onPointerDown: (_) => _awake.touched(),
        child: Scaffold(backgroundColor: PurlnoteColors.desk, body: _sideways(file, noteCount)),
      );
    }

    final view = file == null ? ReaderView.page : _shownView(context);
    final showsPage = view != ReaderView.steps;
    final shown = _controlsShown;

    return Listener(
      // Every touch keeps the screen awake a little longer.
      onPointerDown: (_) => _awake.touched(),
      child: Scaffold(
        backgroundColor: PurlnoteColors.desk,
        body: Stack(
          children: [
            Column(
              children: [
                _Collapsing(
                  shown: shown || file == null,
                  fromTop: true,
                  child: _TopBar(
                    title: widget.pattern.title,
                    subtitle: file == null ? null : '${file.label} · page ${_page ?? 1}',
                    view: file == null ? null : view,
                    offerBoth: isWide(context),
                    onView: (view) => setState(() => _view = view),
                    awake: _AwakeMenu(minutes: _awake.minutes, onChanged: _setAwake, compact: true),
                    noteCount: noteCount,
                    onNotes: _showNotesList,
                    // On the page, the tray below has its own Hide.
                    onHide: file == null || showsPage ? null : () => _showControls(false),
                    files: _files.length > 1 && file != null
                        ? _FileSwitcher(files: _files, current: file, onChanged: (f) => _showFile(f))
                        : null,
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        // The page runs under the tray's rounded corners, so
                        // the pattern shows around them.
                        bottom: file != null && showsPage ? _pageBottomInset : 0,
                        child: SafeArea(
                          // With the top bar hidden, keep the page clear of
                          // the status bar.
                          top: !shown,
                          bottom: !showsPage,
                          child: _loading
                              ? const Center(child: CircularProgressIndicator())
                              : file == null
                                  ? const _NothingDownloaded()
                                  : switch (view) {
                                      ReaderView.page => _pageWithTools(file),
                                      ReaderView.steps => _steps(file, sideBySide: false),
                                      ReaderView.both => Row(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            Expanded(flex: 5, child: _pageWithTools(file)),
                                            const VerticalDivider(width: 1, color: PurlnoteColors.line),
                                            Expanded(flex: 4, child: _steps(file, sideBySide: true)),
                                          ],
                                        ),
                                    },
                        ),
                      ),
                      if (file != null && showsPage)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: _MeasureHeight(
                            onChanged: (height) {
                              if (height != _trayHeight) setState(() => _trayHeight = height);
                            },
                            child: _Collapsing(
                              shown: shown,
                              fromTop: false,
                              child: _ToolsTray(
                                onHide: () => _showControls(false),
                                ruler: _ruler?.visible == true
                                    ? RulerControls(
                                        compact: true,
                                        onDark: true,
                                        onMove: _moveRuler,
                                        onResize: _resizeRuler,
                                      )
                                    : null,
                                onGoToRuler: _goToRuler,
                                tools: _Toolbar(
                                  tool: _tool,
                                  rulerOn: _ruler?.visible == true,
                                  onTool: _chooseTool,
                                  onDark: true,
                                ),
                                counters: _counters.isEmpty
                                    ? null
                                    : CountersBar(
                                        counters: _counters,
                                        onRowsChanged: _setRows,
                                        onAddRepeat: _addRepeatCounter,
                                        onRemove: _removeCounter,
                                        onDark: true,
                                      ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            // With the bars hidden: back, a way to bring them back, and the
            // row counter, floating over the page.
            if (file != null)
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: shown,
                  child: AnimatedOpacity(
                    opacity: shown ? 0 : 1,
                    duration: _Collapsing.duration,
                    child: SafeArea(
                      minimum: const EdgeInsets.all(12),
                      child: Stack(
                        children: [
                          const Positioned(left: 0, top: 0, child: _FloatingBack()),
                          if (showsPage)
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: _FloatingPanel(
                                child: TextButton.icon(
                                  onPressed: () => _showControls(true),
                                  icon: const Icon(Icons.keyboard_arrow_up),
                                  label: const Text('Tools'),
                                ),
                              ),
                            )
                          else
                            Positioned(
                              right: 0,
                              top: 0,
                              child: _FloatingPanel(
                                child: TextButton.icon(
                                  onPressed: () => _showControls(true),
                                  icon: const Icon(Icons.keyboard_arrow_down),
                                  label: const Text('Show bar'),
                                ),
                              ),
                            ),
                          if (showsPage && _counters.isNotEmpty)
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: CompactRowCounter(
                                rows: _counters.first.value,
                                onChanged: _setRows,
                                minusButton: false,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// A phone held sideways: too short for bars above and below the page.
  /// (An iPad has room for them either way.)
  bool _isSideways(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.width > size.height && !isWide(context);
  }

  /// The phone held sideways. The page fills the screen, and the controls
  /// float in its corners: name and back at the top left, tools at the top
  /// right, ruler arrows at the bottom left, the row counter at the bottom
  /// right. Tapping the page hides them for a clear view, and shows them
  /// again.
  Widget _sideways(PatternFile file, int noteCount) {
    final titleBar = _FloatingPanel(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BackButton(),
          Flexible(
            child: Text(
              widget.pattern.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
          const SizedBox(width: 8),
          Text('p. ${_page ?? 1}', style: const TextStyle(fontSize: 12, color: PurlnoteColors.plumMuted)),
          IconButton(
            tooltip: noteCount == 0 ? 'Notes' : '$noteCount notes',
            onPressed: _showNotesList,
            icon: Badge(isLabelVisible: noteCount > 0, label: Text('$noteCount'), child: const Icon(Icons.notes)),
          ),
          _AwakeMenu(minutes: _awake.minutes, onChanged: _setAwake),
        ],
      ),
    );

    if (_shownView(context) == ReaderView.steps) {
      return SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Flexible(child: titleBar),
                  const SizedBox(width: 8),
                  _FloatingPanel(
                    child: TextButton(
                      onPressed: () => setState(() => _view = ReaderView.page),
                      child: const Text('Page'),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _steps(file, sideBySide: false)),
          ],
        ),
      );
    }

    final rulerOn = _ruler?.visible == true;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            // Only while no tool is in use, so drawing and pinning notes
            // never hide the controls by accident.
            onTap: _pageTap,
            child: _buildPages(file),
          ),
        ),
        if (_controlsShown)
          Positioned.fill(
            child: SafeArea(
              minimum: const EdgeInsets.all(8),
              child: Stack(
                children: [
                  Positioned(left: 0, top: 0, right: 330, child: Align(alignment: Alignment.topLeft, child: titleBar)),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: _FloatingPanel(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final option in ReaderTool.values.where((t) => t != ReaderTool.none))
                            _ToolButton(
                              tool: option,
                              compact: true,
                              selected: option == ReaderTool.ruler ? rulerOn : _tool == option,
                              onPressed: () => _chooseTool(option),
                            ),
                          const SizedBox(height: 28, child: VerticalDivider(width: 12, color: PurlnoteColors.line)),
                          TextButton(
                            onPressed: () => setState(() => _view = ReaderView.steps),
                            child: const Text('Steps'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (rulerOn)
                    Positioned(
                      left: 0,
                      bottom: 0,
                      child: _FloatingPanel(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Go to the ruler',
                              onPressed: _goToRuler,
                              icon: const Icon(Icons.my_location),
                            ),
                            RulerControls(compact: true, onMove: _moveRuler, onResize: _resizeRuler),
                          ],
                        ),
                      ),
                    ),
                  if (_counters.isNotEmpty)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: CompactRowCounter(rows: _counters.first.value, onChanged: _setRows),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  void _chooseTool(ReaderTool tool) {
    if (tool == ReaderTool.ruler) {
      _toggleRuler();
    } else {
      setState(() => _tool = _tool == tool ? ReaderTool.none : tool);
    }
  }

  /// The view to show: "Both" needs a wide screen, so after turning an
  /// iPad to a narrow split, it falls back to the page.
  ReaderView _shownView(BuildContext context) {
    if (_view == ReaderView.both && !isWide(context)) return ReaderView.page;
    return _view;
  }

  /// The PDF. Tapping it hides or shows the bars.
  Widget _pageWithTools(PatternFile file) {
    return GestureDetector(onTap: _pageTap, child: _buildPages(file));
  }

  /// The Steps view. Beside the page, "show on the page" turns the page
  /// next to it; on its own, it switches to the page.
  Widget _steps(PatternFile file, {required bool sideBySide}) {
    return StepsView(
      key: ValueKey('steps-${file.id}'),
      session: widget.session,
      fileSha256: file.sha256!,
      pdfPath: file.localPath!,
      projectId: _projectId,
      rows: _counters.isEmpty ? null : _counters.first.value,
      onRowsChanged: _counters.isEmpty ? null : _setRows,
      showRowCounter: !sideBySide,
      onShowPage: (page) {
        if (sideBySide) {
          if (_viewer.isReady) _viewer.goToPage(pageNumber: page);
        } else {
          setState(() {
            _startPage = page;
            _page = page;
            _view = ReaderView.page;
          });
        }
      },
    );
  }

  /// Moves the dragged ruler under the finger at [globalY], onto whichever
  /// page is there. Between two pages, it goes to the nearer one.
  void _dragRulerTo(double globalY) {
    final ruler = _ruler;
    final grab = _rulerGrab;
    if (ruler == null || grab == null) return;
    final bandTop = globalY - grab;
    int? bestPage;
    var bestTop = 0.0;
    var bestHeight = 1.0;
    var bestDistance = double.infinity;
    for (final entry in _pageKeys.entries) {
      final box = entry.value.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached || !box.hasSize) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      final height = box.size.height;
      final distance = bandTop < top
          ? top - bandTop
          : bandTop > top + height
              ? bandTop - top - height
              : 0.0;
      if (distance < bestDistance) {
        bestPage = entry.key;
        bestTop = top;
        bestHeight = height;
        bestDistance = distance;
      }
    }
    if (bestPage == null) return;
    final fraction = ((bandTop - bestTop) / bestHeight).clamp(0.0, 1 - ruler.height);
    if (bestPage != ruler.page) HapticFeedback.selectionClick();
    setState(() => _ruler = ruler.copyWith(page: bestPage, top: fraction));
  }

  void _dropRuler() {
    if (_rulerGrab == null) return;
    setState(() => _rulerGrab = null);
    _saveRuler(_ruler!);
  }

  Widget _buildPages(PatternFile file) {
    // The drag is followed here, above the pages, because it can carry the
    // ruler off the page where it started.
    return Listener(
      onPointerMove: (event) {
        if (_rulerGrab != null) _dragRulerTo(event.position.dy);
      },
      onPointerUp: (_) => _dropRuler(),
      onPointerCancel: (_) => _dropRuler(),
      child: _pages(file),
    );
  }

  Widget _pages(PatternFile file) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            PdfViewer.file(
              file.localPath!,
              key: ValueKey(file.id),
              controller: _viewer,
              // Opening at the current page keeps the place when switching
              // between Page and Both rebuilds the viewer.
              initialPageNumber: _page ?? _startPage,
              params: PdfViewerParams(
                backgroundColor: PurlnoteColors.desk,
                // While drawing, touches on the page draw instead of scrolling.
                panEnabled: !_tool.drawsOnPage,
                scaleEnabled: !_tool.drawsOnPage,
                onPageChanged: _pageChanged,
                pageOverlaysBuilder: (context, pageRect, page) => [
                  // Marks where this page is on screen, for dragging the ruler.
                  IgnorePointer(
                    child: SizedBox.expand(key: _pageKeys.putIfAbsent(page.pageNumber, GlobalKey.new)),
                  ),
                  if (_ruler?.visible == true)
                    RulerOverlay(
                      ruler: _ruler!,
                      page: page.pageNumber,
                      dragging: _rulerGrab != null,
                      onPickedUp: (grab) => setState(() => _rulerGrab = grab),
                    ),
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
          ],
        );
      },
    );
  }
}

/// What the reader shows: the PDF page, the Steps view, or (on an iPad)
/// both side by side.
enum ReaderView { page, both, steps }

/// Switches between Page, Steps and, with room for them, Both.
class _ViewSwitch extends StatelessWidget {
  const _ViewSwitch({required this.view, required this.offerBoth, required this.onChanged, this.compact = false});

  final ReaderView view;
  final bool offerBoth;
  final ValueChanged<ReaderView> onChanged;

  /// Words only, small enough to sit in the top bar.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return SegmentedButton<ReaderView>(
        showSelectedIcon: false,
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)),
          side: const WidgetStatePropertyAll(BorderSide(color: PurlnoteColors.barEdge)),
          foregroundColor: const WidgetStatePropertyAll(PurlnoteColors.plum),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? Colors.white : PurlnoteColors.barLilacDeep,
          ),
        ),
        segments: [
          const ButtonSegment(value: ReaderView.page, label: Text('Page')),
          if (offerBoth) const ButtonSegment(value: ReaderView.both, label: Text('Both')),
          const ButtonSegment(value: ReaderView.steps, label: Text('Steps')),
        ],
        selected: {view},
        onSelectionChanged: (selection) => onChanged(selection.first),
      );
    }
    return Container(
      color: Colors.white,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SegmentedButton<ReaderView>(
          showSelectedIcon: false,
          segments: [
            const ButtonSegment(
              value: ReaderView.page,
              label: Text('Page'),
              icon: Icon(Icons.picture_as_pdf_outlined),
            ),
            if (offerBoth)
              const ButtonSegment(
                value: ReaderView.both,
                label: Text('Both'),
                icon: Icon(Icons.vertical_split_outlined),
              ),
            const ButtonSegment(
              value: ReaderView.steps,
              label: Text('Steps'),
              icon: Icon(Icons.format_list_numbered),
            ),
          ],
          selected: {view},
          onSelectionChanged: (selection) => onChanged(selection.first),
        ),
      ),
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
  const _Toolbar({required this.tool, required this.rulerOn, required this.onTool, this.onDark = false});

  final ReaderTool tool;
  final bool rulerOn;
  final ValueChanged<ReaderTool> onTool;

  /// Cream tools with a marigold pill for the chosen one, on the plum tray.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: onDark ? null : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          for (final option in ReaderTool.values.where((t) => t != ReaderTool.none))
            Expanded(
              child: _ToolButton(
                tool: option,
                selected: option == ReaderTool.ruler ? rulerOn : tool == option,
                onPressed: () => onTool(option),
                onDark: onDark,
              ),
            ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.tool,
    required this.selected,
    required this.onPressed,
    this.compact = false,
    this.onDark = false,
  });

  final ReaderTool tool;
  final bool selected;
  final VoidCallback onPressed;
  final bool onDark;

  /// Icon only, for the floating tools when the phone is sideways.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Tooltip(
        message: tool.label,
        child: Semantics(
          button: true,
          selected: selected,
          label: tool.label,
          excludeSemantics: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onPressed,
            child: Container(
              width: 44,
              height: 40,
              decoration: BoxDecoration(
                color: selected ? PurlnoteColors.blush : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(tool.icon, size: 22, color: PurlnoteColors.plum),
            ),
          ),
        ),
      );
    }
    // On the plum tray the chosen tool is a marigold pill with plum on it,
    // and the others are cream.
    final selectedColor = onDark ? PurlnoteColors.marigold : PurlnoteColors.blush;
    final foreground = onDark && !selected ? PurlnoteColors.cream : PurlnoteColors.plum;
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
            color: selected ? selectedColor : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(tool.icon, size: 22, color: foreground),
              const SizedBox(height: 2),
              Text(
                tool.label,
                style: TextStyle(
                  fontSize: 11,
                  color: foreground,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Slides its child away (up for a top bar, down for a bottom one) and
/// gives the room back to the page, or slides it back in.
class _Collapsing extends StatelessWidget {
  const _Collapsing({required this.shown, required this.fromTop, required this.child});

  final bool shown;
  final bool fromTop;
  final Widget child;

  static const duration = Duration(milliseconds: 260);

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedAlign(
        duration: duration,
        curve: Curves.easeOutCubic,
        alignment: fromTop ? Alignment.bottomCenter : Alignment.topCenter,
        heightFactor: shown ? 1 : 0,
        child: AnimatedOpacity(duration: duration, opacity: shown ? 1 : 0.4, child: child),
      ),
    );
  }
}

/// The reader's top bar: back, the pattern and page, Page/Steps, keep
/// awake, notes and, in Steps, a button that hides the bar. A pale lilac
/// with a fine line under it, so it sits quietly above the page.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.subtitle,
    required this.view,
    required this.offerBoth,
    required this.onView,
    required this.awake,
    required this.noteCount,
    required this.onNotes,
    required this.onHide,
    required this.files,
  });

  final String title;
  final String? subtitle;
  final ReaderView? view;
  final bool offerBoth;
  final ValueChanged<ReaderView> onView;
  final Widget awake;
  final int noteCount;
  final VoidCallback onNotes;
  final VoidCallback? onHide;

  /// Tabs for a pattern with several PDFs.
  final Widget? files;

  @override
  Widget build(BuildContext context) {
    final view = this.view;
    return Material(
      color: PurlnoteColors.barLilac,
      shape: const Border(bottom: BorderSide(color: PurlnoteColors.barEdge)),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
              child: Row(
                children: [
                  const BackButton(),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: PurlnoteColors.plumMuted),
                          ),
                      ],
                    ),
                  ),
                  if (view != null) _ViewSwitch(view: view, offerBoth: offerBoth, onChanged: onView, compact: true),
                  awake,
                  IconButton(
                    tooltip: noteCount == 0 ? 'Notes' : '$noteCount notes',
                    onPressed: onNotes,
                    icon: Badge(
                      isLabelVisible: noteCount > 0,
                      label: Text('$noteCount'),
                      child: const Icon(Icons.notes),
                    ),
                  ),
                  if (onHide != null)
                    IconButton(tooltip: 'Hide the bars', onPressed: onHide, icon: const Icon(Icons.fullscreen)),
                ],
              ),
            ),
            if (files != null) files!,
          ],
        ),
      ),
    );
  }
}

/// The tools under the page, in a plum tray with rounded corners so it's
/// clear where the page ends, and marigold for what can be pressed: the ruler arrows (while the ruler is
/// on), the drawing tools and the counters. Hide, or a swipe down on its
/// handle, slides it away.
class _ToolsTray extends StatelessWidget {
  const _ToolsTray({
    required this.onHide,
    required this.ruler,
    required this.onGoToRuler,
    required this.tools,
    required this.counters,
  });

  final VoidCallback onHide;
  final Widget? ruler;

  /// Scrolls the pattern back to where the ruler is.
  final VoidCallback onGoToRuler;
  final Widget tools;
  final Widget? counters;

  static const cornerRadius = 24.0;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: plumGlowBand,
        borderRadius: BorderRadius.vertical(top: Radius.circular(cornerRadius)),
        boxShadow: [BoxShadow(color: Color(0x553B1C34), blurRadius: 16, offset: Offset(0, -2))],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragEnd: (details) {
                    if ((details.primaryVelocity ?? 0) > 0) onHide();
                  },
                  child: SizedBox(
                    height: 34,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 40,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.28),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: onHide,
                            iconAlignment: IconAlignment.end,
                            icon: const Icon(Icons.keyboard_arrow_down, size: 18),
                            label: const Text('Hide'),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              foregroundColor: PurlnoteColors.marigold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (ruler != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'ROW RULER',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                              color: PurlnoteColors.cream,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Go to the ruler',
                          onPressed: onGoToRuler,
                          icon: const Icon(Icons.my_location, color: PurlnoteColors.marigold),
                        ),
                        ruler!,
                      ],
                    ),
                  ),
                tools,
                if (counters != null) counters!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Reports its child's height whenever it changes, such as while the tray
/// slides in or out.
class _MeasureHeight extends SingleChildRenderObjectWidget {
  const _MeasureHeight({required this.onChanged, required super.child});

  final ValueChanged<double> onChanged;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMeasureHeight(onChanged);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasureHeight renderObject) {
    renderObject.onChanged = onChanged;
  }
}

class _RenderMeasureHeight extends RenderProxyBox {
  _RenderMeasureHeight(this.onChanged);

  ValueChanged<double> onChanged;
  double? _last;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (height == _last) return;
    _last = height;
    // Not during layout: the page's size depends on this.
    WidgetsBinding.instance.addPostFrameCallback((_) => onChanged(height));
  }
}

/// The back button floating over the page while the bars are hidden.
class _FloatingBack extends StatelessWidget {
  const _FloatingBack();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.95),
      shape: const CircleBorder(),
      elevation: 3,
      shadowColor: const Color(0x553B1C34),
      child: const BackButton(),
    );
  }
}

/// A small white panel floating over the page, for the sideways layout.
class _FloatingPanel extends StatelessWidget {
  const _FloatingPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.95),
      elevation: 3,
      shadowColor: const Color(0x553B1C34),
      borderRadius: BorderRadius.circular(14),
      child: Padding(padding: const EdgeInsets.all(4), child: child),
    );
  }
}

/// The chip that shows and changes how long the screen stays awake.
class _AwakeMenu extends StatelessWidget {
  const _AwakeMenu({required this.minutes, required this.onChanged, this.compact = false});

  final int minutes;
  final ValueChanged<int> onChanged;

  /// Just the sun icon, on blush while the screen is kept awake.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: 'Keep screen awake: ${AwakeTimer.describe(minutes)}',
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final choice in AwakeTimer.choices)
          CheckedPopupMenuItem(value: choice, checked: choice == minutes, child: Text(AwakeTimer.describe(choice))),
      ],
      child: compact ? _compactChip() : _chip(),
    );
  }

  Widget _compactChip() {
    return Container(
      width: 36,
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: minutes == AwakeTimer.off ? Colors.transparent : PurlnoteColors.blush,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.light_mode_outlined, size: 20),
    );
  }

  Widget _chip() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Chip(
        avatar: const Icon(Icons.light_mode_outlined, size: 16),
        label: Text(minutes == AwakeTimer.off ? 'Awake off' : 'Awake · ${AwakeTimer.describe(minutes)}'),
        backgroundColor: PurlnoteColors.blush,
        side: BorderSide.none,
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
