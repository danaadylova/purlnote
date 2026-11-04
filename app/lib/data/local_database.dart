import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'pending_edit.dart';

/// Kinds of Ravelry records kept on the phone.
enum RecordType { user, project, queuedProject, stash, projectStatus }

/// The on-phone database every screen reads from.
///
/// Screens never wait on the network: they show what is stored here, and the
/// sync engine updates it in the background. Ravelry stays the source of
/// truth; this is a cache of the knitter's records plus each list's version
/// tag (ETag) so refreshes are cheap. The knitter's own edits wait in the
/// pending_edit table until they reach Ravelry.
class LocalDatabase {
  LocalDatabase._(this._db);

  final Database _db;

  static const _fileName = 'purlnote.db';
  static const _version = 2;

  /// Opens (and if needed creates) the database.
  ///
  /// Tests pass an in-memory [factory] and [path].
  static Future<LocalDatabase> open({DatabaseFactory? factory, String? path}) async {
    final dbFactory = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await dbFactory.getDatabasesPath(), _fileName);
    final db = await dbFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: _version,
        onCreate: (db, version) async {
          await _createVersion1(db);
          await _addPendingEdits(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) await _addPendingEdits(db);
        },
      ),
    );
    return LocalDatabase._(db);
  }

  static Future<void> _createVersion1(Database db) async {
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

  /// Version 2: edits waiting to be sent to Ravelry, oldest first.
  static Future<void> _addPendingEdits(Database db) async {
    await db.execute('''
      CREATE TABLE pending_edit (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        record_type     TEXT    NOT NULL,
        ravelry_id      INTEGER NOT NULL,
        changes         TEXT    NOT NULL,
        baseline        TEXT    NOT NULL,
        their_values    TEXT,
        state           TEXT    NOT NULL,
        attempts        INTEGER NOT NULL DEFAULT 0,
        next_attempt_at INTEGER,
        problem         TEXT,
        created_at      INTEGER NOT NULL
      )
    ''');
  }

  /// Replaces every stored record of [type] with [records], in Ravelry's
  /// order. Done in one transaction so screens never see a half-updated list.
  ///
  /// List replies leave out some fields (a project's notes, for example), so
  /// fields already stored from a record's own page are kept unless the list
  /// reply has a newer value.
  Future<void> replaceRecords(RecordType type, List<Map<String, dynamic>> records, DateTime now) async {
    await _db.transaction((txn) async {
      final stored = {
        for (final row in await txn.query('ravelry_record', where: 'type = ?', whereArgs: [type.name]))
          row['ravelry_id'] as int: jsonDecode(row['body'] as String) as Map<String, dynamic>,
      };
      await txn.delete('ravelry_record', where: 'type = ?', whereArgs: [type.name]);
      final batch = txn.batch();
      for (var index = 0; index < records.length; index++) {
        final record = records[index];
        final id = record['id'] as int;
        batch.insert('ravelry_record', {
          'type': type.name,
          'ravelry_id': id,
          'body': jsonEncode({...?stored[id], ...record}),
          'sort_order': index,
          'fetched_at': now.millisecondsSinceEpoch,
        });
      }
      await batch.commit(noResult: true);
    });
  }

  /// One stored record, or null if it isn't on the phone.
  Future<Map<String, dynamic>?> record(RecordType type, int ravelryId) async {
    final rows = await _db.query(
      'ravelry_record',
      columns: ['body'],
      where: 'type = ? AND ravelry_id = ?',
      whereArgs: [type.name, ravelryId],
    );
    return rows.isEmpty ? null : jsonDecode(rows.first['body'] as String) as Map<String, dynamic>;
  }

  /// Merges [fields] into one stored record, keeping its place in the list.
  /// Does nothing if the record isn't stored.
  Future<void> updateRecord(RecordType type, int ravelryId, Map<String, Object?> fields, DateTime now) async {
    final current = await record(type, ravelryId);
    if (current == null) return;
    await _db.update(
      'ravelry_record',
      {
        'body': jsonEncode({...current, ...fields}),
        'fetched_at': now.millisecondsSinceEpoch
      },
      where: 'type = ? AND ravelry_id = ?',
      whereArgs: [type.name, ravelryId],
    );
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

  /// All pending edits, oldest first.
  Future<List<PendingEdit>> pendingEdits() async {
    final rows = await _db.query('pending_edit', orderBy: 'id');
    return rows.map(PendingEdit.fromRow).toList();
  }

  /// The pending edit for one record, if there is one.
  Future<PendingEdit?> pendingEditFor(RecordType type, int ravelryId) async {
    final rows = await _db.query(
      'pending_edit',
      where: 'record_type = ? AND ravelry_id = ?',
      whereArgs: [type.name, ravelryId],
    );
    return rows.isEmpty ? null : PendingEdit.fromRow(rows.first);
  }

  Future<void> insertPendingEdit({
    required RecordType type,
    required int ravelryId,
    required Map<String, Object?> changes,
    required Map<String, Object?> baseline,
    required DateTime now,
  }) async {
    await _db.insert('pending_edit', {
      'record_type': type.name,
      'ravelry_id': ravelryId,
      'changes': jsonEncode(changes),
      'baseline': jsonEncode(baseline),
      'state': PendingEditState.waiting.name,
      'created_at': now.millisecondsSinceEpoch,
    });
  }

  /// Updates the given columns of one pending edit. Maps are stored as JSON;
  /// times as milliseconds.
  Future<void> updatePendingEdit(
    int id, {
    Map<String, Object?>? changes,
    Map<String, Object?>? baseline,
    Map<String, Object?>? theirValues,
    PendingEditState? state,
    int? attempts,
    DateTime? nextAttemptAt,
    bool clearNextAttempt = false,
    String? problem,
    bool clearProblem = false,
  }) async {
    await _db.update(
      'pending_edit',
      {
        if (changes != null) 'changes': jsonEncode(changes),
        if (baseline != null) 'baseline': jsonEncode(baseline),
        if (theirValues != null) 'their_values': jsonEncode(theirValues),
        if (state != null) 'state': state.name,
        if (attempts != null) 'attempts': attempts,
        if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt.millisecondsSinceEpoch,
        if (clearNextAttempt) 'next_attempt_at': null,
        if (problem != null) 'problem': problem,
        if (clearProblem) 'problem': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deletePendingEdit(int id) => _db.delete('pending_edit', where: 'id = ?', whereArgs: [id]);

  /// Removes everything that came from Ravelry, and any edits not yet sent.
  /// The Ravelry records come back on the next sign-in.
  Future<void> clearRavelryData() async {
    await _db.delete('ravelry_record');
    await _db.delete('sync_state');
    await _db.delete('pending_edit');
  }

  Future<void> close() => _db.close();
}
