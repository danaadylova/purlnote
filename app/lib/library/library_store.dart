import 'package:sqflite/sqflite.dart';

import '../data/local_database.dart';
import 'library_models.dart';

/// Reads and writes the library: Ravelry purchases (synced into the
/// database as library volumes) and imported PDFs, with their files.
class LibraryStore {
  LibraryStore(this.database);

  final LocalDatabase database;

  Database get _db => database.sqlite;

  /// Every pattern, purchases and imports together.
  Future<List<LibraryPattern>> patterns() async {
    final filesByPattern = <String, List<PatternFile>>{};
    for (final row in await _db.query('pattern_file', orderBy: 'pattern_key, sort_order')) {
      final file = PatternFile.fromRow(row);
      filesByPattern.putIfAbsent(file.patternKey, () => []).add(file);
    }
    final lastOpened = await _lastOpenedByPattern();

    final purchases = [
      for (final volume in await database.records(RecordType.libraryVolume))
        _purchase(volume, filesByPattern, lastOpened),
    ];
    final imports = [
      for (final row in await _db.query('imported_pattern'))
        LibraryPattern(
          key: LibraryPattern.importKey(row['id'] as int),
          title: row['title'] as String,
          source: PatternSource.imported,
          files: filesByPattern[LibraryPattern.importKey(row['id'] as int)] ?? const [],
          addedAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
          lastOpenedAt: lastOpened[LibraryPattern.importKey(row['id'] as int)],
        ),
    ];
    return [...purchases, ...imports];
  }

  LibraryPattern _purchase(
    Map<String, dynamic> volume,
    Map<String, List<PatternFile>> filesByPattern,
    Map<String, DateTime> lastOpened,
  ) {
    final key = LibraryPattern.volumeKey(volume['id'] as int);
    final created = volume['created_at'] as String?;
    return LibraryPattern(
      key: key,
      title: (volume['title'] as String?)?.trim().isNotEmpty == true ? volume['title'] as String : 'Untitled pattern',
      author: volume['author_name'] as String?,
      coverUrl: (volume['square_image_url'] ?? volume['small_image_url']) as String?,
      ravelryPatternId: (volume['pattern_id'] as num?)?.toInt(),
      hasDownloads: volume['has_downloads'] == true,
      source: PatternSource.ravelry,
      files: filesByPattern[key] ?? const [],
      addedAt: created == null ? null : DateTime.tryParse(created.replaceAll('/', '-').split(' ').first),
      lastOpenedAt: lastOpened[key],
    );
  }

  /// When each pattern was last read, from the saved reading spots.
  Future<Map<String, DateTime>> _lastOpenedByPattern() async {
    final rows = await _db.rawQuery('''
      SELECT pattern_file.pattern_key AS pattern_key, MAX(reading_position.saved_at) AS last_read
      FROM reading_position JOIN pattern_file ON pattern_file.id = reading_position.file_id
      GROUP BY pattern_file.pattern_key
    ''');
    return {
      for (final row in rows)
        row['pattern_key'] as String: DateTime.fromMillisecondsSinceEpoch(row['last_read'] as int),
    };
  }

  Future<List<PatternFile>> filesFor(String patternKey) async {
    final rows = await _db.query('pattern_file', where: 'pattern_key = ?', whereArgs: [patternKey], orderBy: 'sort_order');
    return rows.map(PatternFile.fromRow).toList();
  }

  Future<PatternFile?> file(int id) async {
    final rows = await _db.query('pattern_file', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : PatternFile.fromRow(rows.first);
  }

  /// Records a purchase's files from Ravelry, in Ravelry's order. Files
  /// already known keep their downloads; new ones are added, not downloaded.
  Future<void> rememberAttachments(String patternKey, List<({int attachmentId, String label})> attachments) async {
    final known = {for (final file in await filesFor(patternKey)) file.attachmentId: file};
    for (var index = 0; index < attachments.length; index++) {
      final attachment = attachments[index];
      final existing = known[attachment.attachmentId];
      if (existing == null) {
        await _db.insert('pattern_file', {
          'pattern_key': patternKey,
          'label': attachment.label,
          'sort_order': index,
          'attachment_id': attachment.attachmentId,
          'added_at': DateTime.now().millisecondsSinceEpoch,
        });
      } else {
        await _db.update('pattern_file', {'sort_order': index}, where: 'id = ?', whereArgs: [existing.id]);
      }
    }
  }

  /// Marks a file as on the phone.
  Future<void> saveDownload(int fileId, {required String path, required String sha256, required int bytes}) async {
    await _db.update(
      'pattern_file',
      {'local_path': path, 'sha256': sha256, 'bytes': bytes},
      where: 'id = ?',
      whereArgs: [fileId],
    );
  }

  /// Adds an imported PDF as a new pattern, or as another file of [patternKey].
  /// Returns the pattern's key.
  Future<String> addImportedFile({
    required String label,
    required String path,
    required String sha256,
    required int bytes,
    String? patternKey,
  }) async {
    final key = patternKey ??
        LibraryPattern.importKey(
          await _db.insert('imported_pattern', {'title': label, 'created_at': DateTime.now().millisecondsSinceEpoch}),
        );
    final existing = await filesFor(key);
    await _db.insert('pattern_file', {
      'pattern_key': key,
      'label': existing.isEmpty ? 'Pattern' : label,
      'sort_order': existing.length,
      'local_path': path,
      'sha256': sha256,
      'bytes': bytes,
      'added_at': DateTime.now().millisecondsSinceEpoch,
    });
    return key;
  }

  /// A file already on the phone with this fingerprint, if any.
  Future<PatternFile?> fileWithSha256(String sha256) async {
    final rows = await _db.query('pattern_file', where: 'sha256 = ?', whereArgs: [sha256], limit: 1);
    return rows.isEmpty ? null : PatternFile.fromRow(rows.first);
  }

  Future<void> renameFile(int fileId, String label) async {
    await _db.update('pattern_file', {'label': label}, where: 'id = ?', whereArgs: [fileId]);
  }

  Future<void> renameImportedPattern(String patternKey, String title) async {
    final id = int.parse(patternKey.substring('import:'.length));
    await _db.update('imported_pattern', {'title': title}, where: 'id = ?', whereArgs: [id]);
  }

  // Per-pattern settings and links ---------------------------------------

  /// Minutes the screen stays awake after the last touch for this pattern;
  /// null means the app default. 0 means "off", -1 "while the pattern is open".
  Future<int?> awakeMinutes(String patternKey) async {
    final rows = await _db.query('pattern_setting', where: 'pattern_key = ?', whereArgs: [patternKey]);
    return rows.isEmpty ? null : rows.first['awake_minutes'] as int?;
  }

  Future<void> setAwakeMinutes(String patternKey, int minutes) async {
    await _db.insert(
      'pattern_setting',
      {'pattern_key': patternKey, 'awake_minutes': minutes},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// The pattern a project was linked to on the phone, if any.
  Future<String?> linkedPatternKey(int projectId) async {
    final rows = await _db.query('project_pattern', where: 'project_id = ?', whereArgs: [projectId]);
    return rows.isEmpty ? null : rows.first['pattern_key'] as String;
  }

  Future<void> linkProject(int projectId, String patternKey) async {
    await _db.insert(
      'project_pattern',
      {'project_id': projectId, 'pattern_key': patternKey},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
