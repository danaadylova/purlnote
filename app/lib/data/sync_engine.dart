import '../ravelry/ravelry_client.dart';
import 'local_database.dart';

/// The parts of a sync, in the order they run.
enum SyncStep {
  profile('Your profile'),
  projects('Projects'),
  queue('Queue'),
  stash('Stash');

  const SyncStep(this.label);

  /// What the first-sync screen calls this step.
  final String label;
}

/// Called after each step with how many records it stored.
typedef SyncProgress = void Function(SyncStep step, int count);

/// Copies the knitter's Ravelry records into the local database.
///
/// This is the only part of the app that reads from Ravelry for the Notebook.
/// Each list remembers Ravelry's version tag (ETag), so when nothing changed a
/// refresh costs one small "unchanged" reply instead of the whole list.
class SyncEngine {
  SyncEngine({required this.ravelry, required this.database, DateTime Function()? clock})
      : _now = clock ?? DateTime.now;

  final RavelryClient ravelry;
  final LocalDatabase database;
  final DateTime Function() _now;

  /// Records per page when a list is long enough to need paging.
  static const pageSize = 100;

  /// Ravelry pages through long lists; stop here so a runaway list can't
  /// loop forever.
  static const maxPages = 50;

  /// Runs every step. Throws [RavelryUnreachable] when offline; what was
  /// stored before stays on screen.
  Future<void> syncEverything({SyncProgress? onProgress}) async {
    final username = await _syncProfile();
    onProgress?.call(SyncStep.profile, 1);

    final listsByStep = {
      SyncStep.projects: _RavelryList(
        name: 'projects',
        path: '/projects/${Uri.encodeComponent(username)}/list.json',
        resultKey: 'projects',
        recordType: RecordType.project,
        extraQuery: const {'sort': 'status started'},
      ),
      SyncStep.queue: _RavelryList(
        name: 'queue',
        path: '/people/${Uri.encodeComponent(username)}/queue/list.json',
        resultKey: 'queued_projects',
        recordType: RecordType.queuedProject,
      ),
      SyncStep.stash: _RavelryList(
        name: 'stash',
        path: '/people/${Uri.encodeComponent(username)}/stash/list.json',
        resultKey: 'stash',
        recordType: RecordType.stash,
      ),
    };

    for (final entry in listsByStep.entries) {
      final count = await _syncList(entry.value);
      onProgress?.call(entry.key, count);
    }
  }

  /// Stores the signed-in knitter and returns their username.
  Future<String> _syncProfile() async {
    const listName = 'profile';
    const path = '/current_user.json';
    var reply = await ravelry.get(path, etag: await database.etagFor(listName));

    if (reply.unchanged) {
      final stored = await database.records(RecordType.user);
      if (stored.isNotEmpty) return stored.first['username'] as String;
      // Ravelry says unchanged but nothing is stored, so ask for it in full.
      reply = await ravelry.get(path);
    }

    final user = reply.body!['user'] as Map<String, dynamic>;
    await database.replaceRecords(RecordType.user, [user], _now());
    await database.markSynced(listName, reply.etag, _now());
    return user['username'] as String;
  }

  /// Fetches every page of [list] and stores it. Returns the record count.
  Future<int> _syncList(_RavelryList list) async {
    final firstPage = await ravelry.get(
      list.path,
      query: list.queryForPage(1),
      etag: await database.etagFor(list.name),
    );

    // Only single-page lists keep a version tag (see below), so "unchanged"
    // means the whole list is unchanged.
    if (firstPage.unchanged) {
      final stored = await database.records(list.recordType);
      await database.markSynced(list.name, firstPage.etag, _now());
      return stored.length;
    }

    final records = list.recordsIn(firstPage.body!);
    final pageCount = _pageCount(firstPage.body!);
    for (var page = 2; page <= pageCount && page <= maxPages; page++) {
      final reply = await ravelry.get(list.path, query: list.queryForPage(page));
      records.addAll(list.recordsIn(reply.body!));
    }

    await database.replaceRecords(list.recordType, records, _now());
    // A tag covers one page only, so for longer lists it can't vouch for the
    // rest; those are fetched in full each time.
    await database.markSynced(list.name, pageCount == 1 ? firstPage.etag : null, _now());
    return records.length;
  }

  int _pageCount(Map<String, dynamic> body) {
    final paginator = body['paginator'] as Map<String, dynamic>?;
    return (paginator?['page_count'] as num?)?.toInt() ?? 1;
  }
}

/// One Ravelry list endpoint and where its records go.
class _RavelryList {
  const _RavelryList({
    required this.name,
    required this.path,
    required this.resultKey,
    required this.recordType,
    this.extraQuery = const {},
  });

  final String name;
  final String path;

  /// The key in Ravelry's reply that holds the records, such as "projects".
  final String resultKey;
  final RecordType recordType;
  final Map<String, String> extraQuery;

  Map<String, String> queryForPage(int page) => {
        ...extraQuery,
        'page': '$page',
        'page_size': '${SyncEngine.pageSize}',
      };

  List<Map<String, dynamic>> recordsIn(Map<String, dynamic> body) {
    final items = body[resultKey] as List<dynamic>? ?? const [];
    return [for (final item in items) item as Map<String, dynamic>];
  }
}
