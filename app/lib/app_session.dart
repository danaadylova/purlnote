import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_paths.dart';
import 'auth/auth_service.dart';
import 'data/local_database.dart';
import 'data/local_projects.dart';
import 'data/outbox.dart';
import 'data/pending_edit.dart';
import 'data/sync_engine.dart';
import 'library/library_models.dart';
import 'library/library_store.dart';
import 'library/pdf_files.dart';
import 'projects/project_notes.dart';
import 'projects/project_photos.dart';
import 'notes/note_sheet.dart';
import 'notes/notes_backup.dart';
import 'notes/project_comments.dart';
import 'ravelry/models.dart';
import 'ravelry/ravelry_client.dart';
import 'reader/reader_store.dart';
import 'steps/step_builder.dart';
import 'steps/steps_store.dart';

/// Which part of the app the knitter sees.
enum AppStage {
  /// Reading the database at launch.
  starting,

  /// No Ravelry account on this phone yet: show Welcome.
  signedOut,

  /// Just signed in and copying records for the first time.
  firstSync,

  /// Everything is on the phone: show the Notebook.
  ready,
}

/// Holds the app's state and the actions screens can take.
///
/// Screens listen to this and rebuild when it changes. They read only what is
/// stored here (loaded from the local database), so they work offline.
class AppSession extends ChangeNotifier {
  AppSession({
    required this.auth,
    required this.database,
    required this.sync,
    this.pdfAuth,
    this.pdfFiles,
    this.comments,
    this.backup,
    StepBuilder? stepBuilder,
  })  : library = LibraryStore(database),
        reader = ReaderStore(database),
        steps = StepsStore(database),
        localProjects = LocalProjects(database) {
    this.stepBuilder = stepBuilder ?? StepBuilder(store: steps);
    photos = ProjectPhotos(ravelry: sync.ravelry, database: database, localProjects: localProjects);
  }

  /// Adds and removes project photos.
  late final ProjectPhotos photos;

  /// Projects kept on this phone only.
  final LocalProjects localProjects;

  /// Whether a Ravelry account is connected. Purlnote works fully without
  /// one; an account adds projects, stash and purchases from Ravelry.
  bool connected = false;

  static const _withoutRavelrySetting = 'use_without_ravelry';

  /// Step-by-step instructions made from each PDF.
  final StepsStore steps;
  late final StepBuilder stepBuilder;

  /// Posts notes as project comments. Null in tests that don't need it.
  final ProjectComments? comments;

  /// Backs up notes to the knitter's Ravelry account. Null in some tests.
  final NotesBackup? backup;

  final AuthService auth;
  final LocalDatabase database;
  final SyncEngine sync;

  Outbox get outbox => sync.outbox;

  /// The separate sign-in for downloading purchased PDFs.
  final AuthService? pdfAuth;

  /// Downloads and imports PDFs. Null in tests that don't need it.
  final PdfFiles? pdfFiles;

  final LibraryStore library;
  final ReaderStore reader;

  /// Every pattern in the library, purchases and imports together.
  List<LibraryPattern> patterns = const [];

  AppStage stage = AppStage.starting;

  RavelryUser? user;
  List<Project> projects = const [];
  List<QueuedProject> queue = const [];
  List<StashYarn> stash = const [];
  List<ProjectStatus> projectStatuses = const [];

  /// The knitter's edits that haven't reached Ravelry yet.
  List<PendingEdit> pendingEdits = const [];
  DateTime? lastSyncedAt;

  /// True while a sync is running.
  bool isSyncing = false;

  /// Steps finished during the first sync, with how many records each stored.
  final Map<SyncStep, int> firstSyncProgress = {};

  /// A short message about the last failed sync, or null if it worked.
  String? syncProblem;

  /// A short message about the last failed sign-in, or null.
  String? signInProblem;

  /// Decides where to start when the app opens.
  Future<void> start() async {
    if (!await auth.isSignedIn()) {
      if (await database.setting(_withoutRavelrySetting) == 'true') {
        await _loadFromDatabase();
        _moveTo(AppStage.ready);
      } else {
        _moveTo(AppStage.signedOut);
      }
      return;
    }
    connected = true;
    await _loadFromDatabase();
    if (user == null) {
      // Signed in, but the first sync never finished.
      await _runFirstSync();
    } else {
      _moveTo(AppStage.ready);
      await refresh();
    }
  }

  /// Starts using Purlnote with everything kept on this phone. A Ravelry
  /// account can be connected later from You.
  Future<void> startWithoutRavelry() async {
    await database.saveSetting(_withoutRavelrySetting, 'true');
    await _loadFromDatabase();
    _moveTo(AppStage.ready);
  }

  /// Opens Ravelry's sign-in, then copies the knitter's records.
  Future<void> signIn() async {
    signInProblem = null;
    notifyListeners();
    try {
      await auth.signIn();
    } on SignInCancelled {
      return;
    } on SignInFailed catch (failure) {
      signInProblem = failure.message;
      notifyListeners();
      return;
    }
    connected = true;
    await _runFirstSync();
  }

  Future<void> _runFirstSync() async {
    firstSyncProgress.clear();
    _moveTo(AppStage.firstSync);
    await _sync(onProgress: (step, count) {
      firstSyncProgress[step] = count;
      notifyListeners();
    });
    // Bring back notes and counters backed up from an earlier install.
    try {
      await backup?.restore();
    } on Exception {
      // Offline or not allowed: the backup stays on Ravelry for next time.
    }
  }

  /// Tries the first sync again after it failed, for example offline.
  Future<void> retryFirstSync() => _runFirstSync();

  /// Whether the knitter can leave the first-sync screen. Projects are what
  /// the Notebook opens on, so the rest can finish in the background.
  bool get canLeaveFirstSync => firstSyncProgress.containsKey(SyncStep.projects);

  /// Moves from the first-sync screen to the Notebook.
  void finishFirstSync() => _moveTo(AppStage.ready);

  /// Pull-to-refresh, and the refresh on every launch.
  Future<void> refresh() => _sync();

  Future<void> _sync({SyncProgress? onProgress}) async {
    // Without a Ravelry account there is nothing to sync.
    if (isSyncing || !connected) return;
    isSyncing = true;
    syncProblem = null;
    notifyListeners();

    try {
      await sync.syncEverything(onProgress: onProgress);
      final username = (await database.records(RecordType.user)).first['username'] as String;
      await comments?.sendAll(username: username);
      // A backup problem shouldn't look like a sync problem; it tries again
      // next time.
      await backUpNotes();
    } on SignInExpired {
      await signOut();
      signInProblem = 'Your Ravelry sign-in ended. Please sign in again.';
    } on RavelryUnreachable {
      syncProblem = "You're offline. Showing what's on this phone.";
    } on RavelryError catch (error) {
      syncProblem = 'Ravelry had a problem (${error.statusCode}). Showing what\'s on this phone.';
    } on SignInFailed catch (failure) {
      syncProblem = failure.message;
    } finally {
      isSyncing = false;
      await _loadFromDatabase();
      notifyListeners();
    }
  }

  /// Forgets the Ravelry sign-in, the copied records and any unsent edits on
  /// this phone. The Ravelry records come back on the next sign-in.
  ///
  /// Purlnote keeps working afterwards with what's on the phone: phone-only
  /// projects, PDFs, notes and counters stay.
  Future<void> signOut() async {
    await auth.signOut();
    await pdfAuth?.signOut();
    await database.clearRavelryData();
    await database.saveSetting(_withoutRavelrySetting, 'true');
    connected = false;
    await _loadFromDatabase();
    _moveTo(AppStage.ready);
  }

  Future<void> _loadFromDatabase() async {
    final users = await database.records(RecordType.user);
    user = users.isEmpty ? null : RavelryUser.fromJson(users.first);
    projects = [
      ...(await database.records(RecordType.project)).map(Project.fromJson),
      ...(await localProjects.all()).map(Project.fromJson),
    ];
    queue = (await database.records(RecordType.queuedProject)).map(QueuedProject.fromJson).toList();
    stash = (await database.records(RecordType.stash)).map(StashYarn.fromJson).toList();
    projectStatuses = (await database.records(RecordType.projectStatus)).map(ProjectStatus.fromJson).toList();
    if (projectStatuses.isEmpty) {
      // Not synced from Ravelry (yet): offer the common statuses by name.
      projectStatuses = [
        for (var i = 0; i < LocalProjects.statusNames.length; i++)
          ProjectStatus(id: i + 1, name: LocalProjects.statusNames[i]),
      ];
    }
    pendingEdits = await database.pendingEdits();
    lastSyncedAt = await database.lastSyncedAt();
    patterns = await library.patterns();
  }

  // Editing ---------------------------------------------------------------

  Project? projectById(int id) => projects.where((project) => project.id == id).firstOrNull;

  StashYarn? stashById(int id) => stash.where((yarn) => yarn.id == id).firstOrNull;

  /// The unsent edit for one record, if any.
  PendingEdit? pendingEditFor(RecordType type, int ravelryId) {
    return pendingEdits.where((edit) => edit.recordType == type && edit.ravelryId == ravelryId).firstOrNull;
  }

  /// Edits that need the knitter to choose between their version and Ravelry's.
  List<PendingEdit> get conflicts => pendingEdits.where((edit) => edit.state == PendingEditState.conflict).toList();

  /// Edits Ravelry refused for good.
  List<PendingEdit> get failedEdits => pendingEdits.where((edit) => edit.state == PendingEditState.failed).toList();

  /// Loads a project's or yarn's full details (notes, size and so on) before
  /// showing or editing it. Offline, the stored copy is used as it is.
  Future<void> loadFullRecord(RecordType type, int ravelryId) async {
    if (!connected || LocalProjects.isLocal(ravelryId)) return;
    try {
      await sync.refreshRecord(type, ravelryId);
    } on RavelryUnreachable {
      return;
    } on RavelryError {
      return;
    } on SignInFailed {
      return;
    } on SignInExpired {
      return;
    }
    await _loadFromDatabase();
    notifyListeners();
  }

  /// Saves an edit on the phone at once, then tries to send it to Ravelry.
  /// See [Outbox.saveEdit] for [changes] and [displayFields].
  Future<void> saveEdit(
    RecordType type,
    int ravelryId,
    Map<String, Object?> changes, {
    Map<String, Object?> displayFields = const {},
  }) async {
    if (changes.isEmpty) return;
    if (type == RecordType.project && LocalProjects.isLocal(ravelryId)) {
      // A phone-only project is simply saved; there's nothing to send.
      await localProjects.update(ravelryId, {...changes, ...displayFields});
      await _loadFromDatabase();
      notifyListeners();
      return;
    }
    await outbox.saveEdit(type: type, ravelryId: ravelryId, changes: changes, displayFields: displayFields);
    await _loadFromDatabase();
    notifyListeners();
    // The knitter can carry on while it sends.
    unawaited(refresh());
  }

  /// Applies the knitter's choices for a conflict, then sends the result.
  Future<void> resolveConflict(PendingEdit edit, Map<String, ConflictChoice> choices) async {
    await outbox.resolveConflict(edit, choices);
    await _loadFromDatabase();
    notifyListeners();
    unawaited(refresh());
  }

  /// Drops an edit that won't be sent, putting the old values back.
  Future<void> discardEdit(PendingEdit edit) async {
    await outbox.discard(edit);
    await _loadFromDatabase();
    notifyListeners();
  }

  /// Projects with status "In progress", for the top of the Notebook.
  List<Project> get onTheNeedles => projects.where((project) => project.isOnTheNeedles).toList();

  /// Every other project, newest change first.
  List<Project> get otherProjects {
    final others = projects.where((project) => !project.isOnTheNeedles).toList();
    others.sort((a, b) => (b.updatedAt ?? DateTime(0)).compareTo(a.updatedAt ?? DateTime(0)));
    return others;
  }

  // Library ---------------------------------------------------------------

  LibraryPattern? patternByKey(String key) => patterns.where((pattern) => pattern.key == key).firstOrNull;

  /// The library pattern a project is knitting: one linked on this phone, or
  /// a purchase of the same Ravelry pattern.
  Future<LibraryPattern?> patternForProject(Project project) async {
    final linkedKey = await library.linkedPatternKey(project.id);
    if (linkedKey != null) return patternByKey(linkedKey);
    final patternId = project.patternId;
    if (patternId == null) return null;
    return patterns.where((pattern) => pattern.ravelryPatternId == patternId).firstOrNull;
  }

  /// Ties an imported pattern (or any library pattern) to a project, so the
  /// project opens it.
  Future<void> linkProjectToPattern(int projectId, String patternKey) async {
    await library.linkProject(projectId, patternKey);
    notifyListeners();
  }

  /// Fetches the list of PDFs in a purchase. Offline, keeps what's known.
  Future<void> loadPurchaseFiles(LibraryPattern pattern) async {
    final volumeId = LibraryPattern.volumeIdOf(pattern.key);
    final files = pdfFiles;
    if (volumeId == null || files == null) return;
    try {
      await files.loadPurchaseFiles(volumeId);
    } on RavelryUnreachable {
      return;
    } on RavelryError {
      return;
    } on SignInExpired {
      return;
    }
    await _reloadLibrary();
  }

  /// Whether the knitter has allowed Purlnote to download purchased PDFs.
  Future<bool> canDownloadPdfs() async => await pdfAuth?.isSignedIn() ?? false;

  /// Asks Ravelry for permission to download purchased PDFs. Returns a
  /// message to show if it didn't work, or null if it did.
  Future<String?> allowPdfDownloads() async {
    final pdfSignIn = pdfAuth;
    if (pdfSignIn == null) return 'PDF downloads aren\'t available in this build.';
    try {
      await pdfSignIn.signIn();
      return null;
    } on SignInCancelled {
      return 'PDF downloads weren\'t allowed.';
    } on SignInFailed catch (failure) {
      return failure.message;
    }
  }

  /// Downloads one purchased PDF. Returns a message to show if it couldn't.
  Future<String?> downloadFile(PatternFile file) async {
    final files = pdfFiles;
    if (files == null) return 'PDF downloads aren\'t available in this build.';
    try {
      await files.download(file);
    } on DownloadLimitReached {
      return 'Ravelry\'s daily download limit is reached. Try again tomorrow; files already on this phone still open.';
    } on NeedsPdfPermission {
      return 'Allow PDF downloads first.';
    } on RavelryUnreachable {
      return 'You\'re offline. Download it when you\'re connected.';
    } on RavelryError catch (error) {
      return 'Ravelry couldn\'t provide this file (error ${error.statusCode}).';
    } finally {
      await _reloadLibrary();
    }
    return null;
  }

  /// Imports a PDF from Files. Returns the pattern it went into, or null if
  /// cancelled. Throws [ImportRefused] with a message for bad files.
  Future<LibraryPattern?> importPdf({String? addToPattern}) async {
    final files = pdfFiles;
    if (files == null) return null;
    final key = await files.importFromFiles(addToPattern: addToPattern);
    await _reloadLibrary();
    return key == null ? null : patternByKey(key);
  }

  Future<void> renameImportedPattern(String key, String title) async {
    await library.renameImportedPattern(key, title);
    await _reloadLibrary();
  }

  Future<void> renameFile(int fileId, String label) async {
    await library.renameFile(fileId, label);
    await _reloadLibrary();
  }

  Future<void> _reloadLibrary() async {
    patterns = await library.patterns();
    notifyListeners();
  }

  // Phone-only projects -----------------------------------------------------

  /// Starts a project on this phone, optionally with a pattern from the
  /// library. Returns its ID.
  Future<int> createProject({required String name, String? patternKey}) async {
    final pattern = patternKey == null ? null : patternByKey(patternKey);
    final id = await localProjects.create(name: name, patternName: pattern?.title);
    if (patternKey != null) await library.linkProject(id, patternKey);
    await _loadFromDatabase();
    notifyListeners();
    return id;
  }

  Future<void> deleteLocalProject(int projectId) async {
    await localProjects.delete(projectId);
    await _loadFromDatabase();
    notifyListeners();
  }

  /// Creates a phone-only project on Ravelry and moves its counters, reading
  /// spots and steps over. Returns a message to show if it couldn't.
  Future<String?> addProjectToRavelry(int projectId) async {
    final username = user?.username;
    final project = await localProjects.byId(projectId);
    if (!connected || username == null || project == null) return 'Connect a Ravelry account first.';
    final statusId =
        projectStatuses.where((status) => status.name == project['status_name']).firstOrNull?.id;
    try {
      final reply = await sync.ravelry.post('/projects/${Uri.encodeComponent(username)}/create.json', {
        'name': project['name'],
        if (project['pattern_name'] != null) 'personal_pattern_name': project['pattern_name'],
        if (statusId != null) 'project_status_id': statusId,
        if (project['progress'] != null) 'progress': project['progress'],
        if (project['started'] != null) 'started': project['started'],
        if (project['completed'] != null) 'completed': project['completed'],
        if (project['size'] != null) 'size': project['size'],
        if (project['notes'] != null) 'notes': project['notes'],
      });
      final ravelryId = (reply['project'] as Map<String, dynamic>?)?['id'] as int?;
      if (ravelryId == null) return 'Ravelry didn\'t confirm the new project.';
      final localPhotos = (project['local_photos'] as List<dynamic>? ?? const []).cast<String>();
      await localProjects.moveTo(projectId, ravelryId);
      // Photos kept on the phone go to the new Ravelry project too.
      for (final saved in localPhotos) {
        final file = File(AppPaths.resolve(saved));
        if (!await file.exists()) continue;
        try {
          await photos.add(projectId: ravelryId, username: username, bytes: await file.readAsBytes(), fileName: saved);
        } on Exception {
          // A photo that can't be added is left on the phone, not lost.
          continue;
        }
        await file.delete();
      }
    } on RavelryUnreachable {
      return 'You\'re offline. Add it to Ravelry when you\'re connected.';
    } on RavelryError catch (error) {
      return 'Ravelry couldn\'t create the project (error ${error.statusCode}).';
    }
    await refresh();
    await _loadFromDatabase();
    notifyListeners();
    return null;
  }

  // Notes to projects ------------------------------------------------------

  /// Where new notes for [projectId] go: the last choice made for that
  /// project, or "keep on the page" the first time.
  Future<NoteDestination> noteDestinationFor(int projectId) async {
    final saved = await database.setting('note_destination:$projectId');
    return NoteDestination.values.where((d) => d.name == saved).firstOrNull ?? NoteDestination.pageOnly;
  }

  /// Whether the knitter has allowed Purlnote to post comments.
  Future<bool> canPostComments() => auth.hasScope('message-write');

  /// Asks Ravelry for the comment permission. Returns a message to show if
  /// it didn't work, or null if it did.
  Future<String?> allowComments() async {
    try {
      await auth.signIn(extraScopes: const ['message-write']);
      return await canPostComments() ? null : 'Ravelry didn\'t grant permission to post comments.';
    } on SignInCancelled {
      return 'Comments weren\'t allowed. The note stays on the page.';
    } on SignInFailed catch (failure) {
      return failure.message;
    }
  }

  /// Sends a note to the project: as a comment (posted at the next sync, so
  /// it works offline), or as a dated line in the project's notes.
  Future<void> sendNoteToProject({
    required int projectId,
    required String text,
    required NoteDestination destination,
    required NoteTag tag,
    int? annotationId,
  }) async {
    await database.saveSetting('note_destination:$projectId', destination.name);
    switch (destination) {
      case NoteDestination.pageOnly:
        return;
      case NoteDestination.projectComment:
        await comments?.queue(projectId: projectId, body: tag.commentBody(text), annotationId: annotationId);
        notifyListeners();
        unawaited(refresh());
      case NoteDestination.projectNotes:
        await addProjectNote(projectId, tag.commentBody(text));
    }
  }

  // Project notes and photos -------------------------------------------------

  /// Adds a dated note to a project's notes. Returns a message to show if it
  /// couldn't be added.
  Future<String?> addProjectNote(int projectId, String text) {
    return _changeProjectNotes(projectId, (entries) => [...entries, datedNote(text, DateTime.now())]);
  }

  /// Changes one note ([text]) or removes it ([text] null).
  Future<String?> editProjectNote(int projectId, int index, String? text) {
    return _changeProjectNotes(projectId, (entries) {
      final changed = [...entries];
      if (index < 0 || index >= changed.length) return changed;
      if (text == null || text.trim().isEmpty) {
        changed.removeAt(index);
      } else {
        changed[index] = text.trim();
      }
      return changed;
    });
  }

  Future<String?> _changeProjectNotes(int projectId, List<String> Function(List<String> entries) change) async {
    await loadFullRecord(RecordType.project, projectId);
    final project = projectById(projectId);
    if (project == null) return 'This project is no longer here.';
    // Ravelry keeps all notes in one field; changing it without having read
    // it first would replace notes written on the website.
    if (!project.notesLoaded) {
      return 'This project\'s notes haven\'t loaded from Ravelry yet. Try again when you\'re online.';
    }
    await saveEdit(RecordType.project, projectId, {'notes': joinNoteEntries(change(noteEntries(project.notes)))});
    return null;
  }

  /// Adds a photo to a project. Returns a message to show if it couldn't.
  Future<String?> addProjectPhoto(int projectId, Uint8List bytes, String fileName) async {
    try {
      await photos.add(projectId: projectId, username: user?.username, bytes: bytes, fileName: fileName);
    } on RavelryUnreachable {
      return 'You\'re offline. Photos go to Ravelry, so add it when you\'re connected.';
    } on RavelryError catch (error) {
      return 'Ravelry couldn\'t add the photo (error ${error.statusCode}).';
    } on SignInExpired {
      return 'Your Ravelry sign-in ended. Sign in again from You.';
    }
    if (!LocalProjects.isLocal(projectId)) {
      // Ravelry takes a few seconds to process a new photo before it lists it.
      await Future<void>.delayed(const Duration(seconds: 4));
      await loadFullRecord(RecordType.project, projectId);
    }
    await _loadFromDatabase();
    notifyListeners();
    return null;
  }

  /// Removes a photo. Returns a message to show if it couldn't.
  Future<String?> deleteProjectPhoto(int projectId, ProjectPicture picture) async {
    try {
      final path = picture.localPath;
      final photoId = picture.ravelryId;
      if (path != null) {
        await photos.deleteFromPhone(projectId: projectId, path: path);
      } else if (photoId != null) {
        await photos.deleteFromRavelry(projectId: projectId, photoId: photoId);
      }
    } on RavelryUnreachable {
      return 'You\'re offline. Delete the photo when you\'re connected.';
    } on RavelryError catch (error) {
      return 'Ravelry couldn\'t delete the photo (error ${error.statusCode}).';
    }
    await _loadFromDatabase();
    notifyListeners();
    return null;
  }

  /// Comments on a project from Ravelry, or null when offline.
  Future<List<RavelryComment>?> loadComments(int projectId) async {
    if (!connected || LocalProjects.isLocal(projectId)) return null;
    final username = user?.username;
    final service = comments;
    if (username == null || service == null) return null;
    try {
      return await service.load(username: username, projectId: projectId);
    } on RavelryUnreachable {
      return null;
    } on RavelryError {
      return null;
    }
  }

  /// Comments from notes that haven't reached Ravelry yet.
  Future<List<ProjectCommentRecord>> unsentComments(int projectId) async =>
      await comments?.unsent(projectId) ?? const [];

  Future<void> cancelComment(ProjectCommentRecord comment) async {
    await comments?.cancel(comment.id);
    notifyListeners();
  }

  /// The comment a note was posted as, if it was.
  Future<ProjectCommentRecord?> commentForNote(int annotationId) async => comments?.forAnnotation(annotationId);

  /// Deletes one of the knitter's comments on Ravelry. Returns a message to
  /// show if it couldn't.
  Future<String?> deleteComment(int ravelryCommentId) async {
    try {
      await comments?.deletePosted(ravelryCommentId);
      notifyListeners();
      return null;
    } on RavelryUnreachable {
      return 'You\'re offline. Delete the comment when you\'re connected.';
    } on RavelryError catch (error) {
      return 'Ravelry couldn\'t delete the comment (error ${error.statusCode}).';
    }
  }

  // Notes backup -------------------------------------------------------------

  Future<bool> isBackupEnabled() async => connected && (await backup?.isEnabled() ?? false);

  /// Whether notes on a project can go to its Ravelry comments.
  bool canCommentOn(int projectId) => connected && !LocalProjects.isLocal(projectId);

  /// Turning the backup off deletes it from Ravelry. Returns a message to
  /// show if that couldn't be done now.
  Future<String?> setBackupEnabled(bool enabled) async {
    try {
      await backup?.setEnabled(enabled);
      if (enabled) await backup?.backUp();
      notifyListeners();
      return null;
    } on RavelryUnreachable {
      return enabled
          ? 'Backup is on. It runs when you\'re connected.'
          : 'Backup is off, but the copy on Ravelry couldn\'t be deleted offline. Turn it on and off again when connected.';
    } on RavelryError catch (error) {
      return 'Ravelry had a problem (error ${error.statusCode}).';
    }
  }

  /// Backs up now, for example when leaving the reader. Quietly does nothing
  /// offline; the next sync tries again.
  Future<void> backUpNotes() async {
    try {
      await backup?.backUp();
    } on Exception {
      return;
    }
  }

  void _moveTo(AppStage next) {
    stage = next;
    notifyListeners();
  }
}
