import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Kinds of Ravelry records kept on the phone.
enum RecordType { user, project, queuedProject, stash }

/// The on-phone database every screen reads from.
///
/// Screens never wait on the network: they show what is stored here, and the
/// sync engine updates it in the background. Ravelry stays the source of
/// truth; this is a cache of the knitter's records plus each list's version
/// tag (ETag) so refreshes are cheap.
class LocalDatabase {
  LocalDatabase._(this._db);

  final Database _db;

  static const _fileName = 'purlnote.db';
  static const _version = 1;

  /// Opens (and if needed creates) the database.
  ///
  /// Tests pass an in-memory [factory] and [path].
  static Future<LocalDatabase> open({DatabaseFactory? factory, String? path}) async {
    final dbFactory = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await dbFactory.getDatabasesPath(), _fileName);
    final db = await dbFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(version: _version, onCreate: _createTables),
    );
    return LocalDatabase._(db);
  }

  static Future<void> _createTables(Database db, int version) async {
    // One row per Ravelry record. The full JSON is kept so screens can show
    // more fields later without another sync.
    await db.execute('''
      CREATE TABLE ravelry_record (
        type       TEXT    NOT NULL,
        ravelry_id INTEGER NOT NULL,
        body       TEXT    NOT NULL,
        sort_order INTEGER NOT NULL,
        fetched_at INTEGER NOT NULL,
        PRIMARY KEY (type, ravelry_id)
      )
    ''');
    // One row per list we sync, such as "projects".
    await db.execute('''
      CREATE TABLE sync_state (
        list_name TEXT PRIMARY KEY,
        etag      TEXT,
        synced_at INTEGER NOT NULL
      )
    ''');
  }

  /// Replaces every stored record of [type] with [records], in Ravelry's
  /// order. Done in one transaction so screens never see a half-updated list.
  Future<void> replaceRecords(RecordType type, List<Map<String, dynamic>> records, DateTime now) async {
    await _db.transaction((txn) async {
      await txn.delete('ravelry_record', where: 'type = ?', whereArgs: [type.name]);
      final batch = txn.batch();
      for (var index = 0; index < records.length; index++) {
        final record = records[index];
        batch.insert('ravelry_record', {
          'type': type.name,
          'ravelry_id': record['id'] as int,
          'body': jsonEncode(record),
          'sort_order': index,
          'fetched_at': now.millisecondsSinceEpoch,
        });
      }
      await batch.commit(noResult: true);
    });
  }

  /// All stored records of [type], in the order Ravelry gave them.
  Future<List<Map<String, dynamic>>> records(RecordType type) async {
    final rows = await _db.query(
      'ravelry_record',
      columns: ['body'],
      where: 'type = ?',
      whereArgs: [type.name],
      orderBy: 'sort_order',
    );
    return [for (final row in rows) jsonDecode(row['body'] as String) as Map<String, dynamic>];
  }

  /// The version tag Ravelry sent for [listName] last time, if any.
  Future<String?> etagFor(String listName) async {
    final rows = await _db.query('sync_state', where: 'list_name = ?', whereArgs: [listName]);
    return rows.isEmpty ? null : rows.first['etag'] as String?;
  }

  /// Remembers that [listName] was synced, and its version tag.
  Future<void> markSynced(String listName, String? etag, DateTime now) async {
    await _db.insert(
      'sync_state',
      {'list_name': listName, 'etag': etag, 'synced_at': now.millisecondsSinceEpoch},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// When the most recent list finished syncing, or null if never.
  Future<DateTime?> lastSyncedAt() async {
    final rows = await _db.rawQuery('SELECT MAX(synced_at) AS latest FROM sync_state');
    final latest = rows.first['latest'] as int?;
    return latest == null ? null : DateTime.fromMillisecondsSinceEpoch(latest);
  }

  /// Removes everything that came from Ravelry. It all comes back on the
  /// next sign-in.
  Future<void> clearRavelryData() async {
    await _db.delete('ravelry_record');
    await _db.delete('sync_state');
  }

  Future<void> close() => _db.close();
}
