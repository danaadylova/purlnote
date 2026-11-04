import 'dart:async';

import 'package:flutter/foundation.dart';

import 'auth/auth_service.dart';
import 'data/local_database.dart';
import 'data/outbox.dart';
import 'data/pending_edit.dart';
import 'data/sync_engine.dart';
import 'ravelry/models.dart';
import 'ravelry/ravelry_client.dart';

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
  AppSession({required this.auth, required this.database, required this.sync});

  final AuthService auth;
  final LocalDatabase database;
  final SyncEngine sync;

  Outbox get outbox => sync.outbox;

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
      _moveTo(AppStage.signedOut);
      return;
    }
    await _loadFromDatabase();
    if (user == null) {
      // Signed in, but the first sync never finished.
      await _runFirstSync();
    } else {
      _moveTo(AppStage.ready);
      await refresh();
    }
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
    await _runFirstSync();
  }

  Future<void> _runFirstSync() async {
    firstSyncProgress.clear();
    _moveTo(AppStage.firstSync);
    await _sync(onProgress: (step, count) {
      firstSyncProgress[step] = count;
      notifyListeners();
    });
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
    if (isSyncing) return;
    isSyncing = true;
    syncProblem = null;
    notifyListeners();

    try {
      await sync.syncEverything(onProgress: onProgress);
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
  Future<void> signOut() async {
    await auth.signOut();
    await database.clearRavelryData();
    await _loadFromDatabase();
    _moveTo(AppStage.signedOut);
  }

  Future<void> _loadFromDatabase() async {
    final users = await database.records(RecordType.user);
    user = users.isEmpty ? null : RavelryUser.fromJson(users.first);
    projects = (await database.records(RecordType.project)).map(Project.fromJson).toList();
    queue = (await database.records(RecordType.queuedProject)).map(QueuedProject.fromJson).toList();
    stash = (await database.records(RecordType.stash)).map(StashYarn.fromJson).toList();
    projectStatuses = (await database.records(RecordType.projectStatus)).map(ProjectStatus.fromJson).toList();
    pendingEdits = await database.pendingEdits();
    lastSyncedAt = await database.lastSyncedAt();
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

  void _moveTo(AppStage next) {
    stage = next;
    notifyListeners();
  }
}
