import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../data/local_database.dart';
import '../ravelry/ravelry_client.dart';

/// Backs up what only the phone knows (notes, highlights, counters, reading
/// spots, the size and step reached in Steps, and screen-awake settings) to the knitter's own Ravelry account, in
/// the per-app storage Ravelry offers for this.
///
/// PDFs are not backed up (they're large and not ours to copy), and neither
/// are pen strokes. Nothing goes to a Purlnote server.
///
/// Stored under these keys:
/// - `pn_index`: the file keys below, separated by spaces.
/// - `pn_f_` plus the first 16 characters of a PDF's SHA-256: that PDF's
///   marks, reading spots and place in its steps.
/// - `pn_counters`: every project's counters.
/// - `pn_settings`: the screen-awake setting per Ravelry pattern.
/// Only keys whose content changed since the last backup are written.
class NotesBackup {
  NotesBackup({required this.ravelry, required this.database});

  final RavelryClient ravelry;
  final LocalDatabase database;

  Database get _db => database.sqlite;

  static const _enabledSetting = 'notes_backup_enabled';
  static const _indexKey = 'pn_index';
  static const _countersKey = 'pn_counters';
  static const _settingsKey = 'pn_settings';

  /// On unless the knitter turned it off.
  Future<bool> isEnabled() async => await database.setting(_enabledSetting) != 'false';

  /// Turning it off deletes the backup from Ravelry.
  Future<void> setEnabled(bool enabled) async {
    await database.saveSetting(_enabledSetting, '$enabled');
    if (!enabled) await deleteBackup();
  }

  /// Writes every part that changed since the last backup. Returns how many
  /// keys were written. Throws [RavelryUnreachable] offline.
  Future<int> backUp() async {
    if (!await isEnabled()) return 0;
    final values = await _currentValues();
    var written = 0;
    for (final entry in values.entries) {
      final hash = sha256.convert(utf8.encode(entry.value)).toString();
      if (await database.setting('backup_hash:${entry.key}') == hash) continue;
      await ravelry.postForm('/app/data/set.json', {entry.key: entry.value});
      await database.saveSetting('backup_hash:${entry.key}', hash);
      written++;
    }
    return written;
  }

  /// Everything to back up, by key.
  Future<Map<String, String>> _currentValues() async {
    final files = <String, Map<String, Object?>>{};

    for (final row in await _db.query('annotation', where: 'kind != ?', whereArgs: ['ink'], orderBy: 'id')) {
      final sha = row['file_sha256'] as String;
      final entry = files.putIfAbsent(sha, () => {'sha256': sha, 'marks': <Object?>[], 'spots': <String, int>{}});
      (entry['marks'] as List).add({
        'page': row['page'],
        'kind': row['kind'],
        'geometry': jsonDecode(row['geometry'] as String),
        if (row['note_text'] != null) 'text': row['note_text'],
      });
    }

    final spots = await _db.rawQuery('''
      SELECT pattern_file.sha256 AS sha256, reading_position.project_id AS project_id, reading_position.page AS page
      FROM reading_position JOIN pattern_file ON pattern_file.id = reading_position.file_id
      WHERE pattern_file.sha256 IS NOT NULL
    ''');
    for (final row in spots) {
      final sha = row['sha256'] as String;
      final entry = files.putIfAbsent(sha, () => {'sha256': sha, 'marks': <Object?>[], 'spots': <String, int>{}});
      (entry['spots'] as Map<String, int>)['${row['project_id']}'] = row['page'] as int;
    }

    // The size being made and the current step, per project.
    for (final row in await _db.query('step_progress')) {
      final sha = row['file_sha256'] as String;
      final entry = files.putIfAbsent(sha, () => {'sha256': sha, 'marks': <Object?>[], 'spots': <String, int>{}});
      (entry.putIfAbsent('steps', () => <String, Object?>{}) as Map<String, Object?>)['${row['project_id']}'] = {
        'step': row['current_step'],
        'size': row['size_index'],
        'counter': row['next_moves_counter'],
      };
    }

    final counters = <String, List<Object?>>{};
    for (final row in await _db.query('counter', orderBy: 'project_id, sort_order')) {
      counters.putIfAbsent('${row['project_id']}', () => []).add({
        'label': row['label'],
        'value': row['value'],
        if (row['every_n_rows'] != null) 'every': row['every_n_rows'],
        if (row['total_repeats'] != null) 'times': row['total_repeats'],
      });
    }

    // Imported patterns get new local IDs on another phone, so only Ravelry
    // patterns' settings can be matched up again.
    final awake = {
      for (final row in await _db.query('pattern_setting', where: "pattern_key LIKE 'volume:%'"))
        row['pattern_key'] as String: row['awake_minutes'],
    };

    final fileKeys = {for (final sha in files.keys) fileKey(sha): jsonEncode(files[sha])};
    return {
      ...fileKeys,
      _indexKey: fileKeys.keys.join(' '),
      _countersKey: jsonEncode(counters),
      _settingsKey: jsonEncode(awake),
    };
  }

  /// Brings a backup onto this phone, for example after signing in again.
  /// Only fills in what's missing: anything already on the phone is kept.
  /// Returns how many marks were restored.
  Future<int> restore() async {
    if (!await isEnabled()) return 0;
    final index = await _read([_indexKey, _countersKey, _settingsKey]);
    final fileKeys = (index[_indexKey] ?? '').split(' ').where((key) => key.isNotEmpty).toList();
    final files = fileKeys.isEmpty ? const <String, String>{} : await _read(fileKeys);

    var restored = 0;
    for (final value in files.values) {
      restored += await _restoreFile(jsonDecode(value) as Map<String, dynamic>);
    }
    await _restoreCounters(index[_countersKey]);
    await _restoreSettings(index[_settingsKey]);
    return restored;
  }

  Future<int> _restoreFile(Map<String, dynamic> file) async {
    final sha = file['sha256'] as String;
    final hasMarks = Sqflite.firstIntValue(
          await _db.rawQuery('SELECT COUNT(*) FROM annotation WHERE file_sha256 = ?', [sha]),
        ) !=
        0;
    var restored = 0;
    if (!hasMarks) {
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final mark in (file['marks'] as List).cast<Map<String, dynamic>>()) {
        await _db.insert('annotation', {
          'file_sha256': sha,
          'page': mark['page'],
          'kind': mark['kind'],
          'geometry': jsonEncode(mark['geometry']),
          'note_text': mark['text'],
          'created_at': now,
          'updated_at': now,
        });
        restored++;
      }
    }

    // Reading spots need the file to be on the phone already.
    final localFiles = await _db.query('pattern_file', columns: ['id'], where: 'sha256 = ?', whereArgs: [sha]);
    for (final localFile in localFiles) {
      for (final spot in (file['spots'] as Map<String, dynamic>).entries) {
        await _db.insert(
          'reading_position',
          {
            'file_id': localFile['id'],
            'project_id': int.parse(spot.key),
            'page': spot.value,
            'saved_at': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }
    final steps = file['steps'] as Map<String, dynamic>? ?? const {};
    for (final entry in steps.entries) {
      final progress = entry.value as Map<String, dynamic>;
      await _db.insert(
        'step_progress',
        {
          'project_id': int.parse(entry.key),
          'file_sha256': sha,
          'current_step': progress['step'],
          'size_index': progress['size'],
          'next_moves_counter': progress['counter'],
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    return restored;
  }

  Future<void> _restoreCounters(String? value) async {
    if (value == null || value.isEmpty) return;
    final byProject = jsonDecode(value) as Map<String, dynamic>;
    for (final entry in byProject.entries) {
      final projectId = int.parse(entry.key);
      final existing = Sqflite.firstIntValue(
        await _db.rawQuery('SELECT COUNT(*) FROM counter WHERE project_id = ?', [projectId]),
      );
      if (existing != 0) continue;
      final counters = (entry.value as List).cast<Map<String, dynamic>>();
      for (var order = 0; order < counters.length; order++) {
        await _db.insert('counter', {
          'project_id': projectId,
          'label': counters[order]['label'],
          'value': counters[order]['value'],
          'every_n_rows': counters[order]['every'],
          'total_repeats': counters[order]['times'],
          'sort_order': order,
        });
      }
    }
  }

  Future<void> _restoreSettings(String? value) async {
    if (value == null || value.isEmpty) return;
    for (final entry in (jsonDecode(value) as Map<String, dynamic>).entries) {
      await _db.insert(
        'pattern_setting',
        {'pattern_key': entry.key, 'awake_minutes': entry.value},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  /// Removes the whole backup from Ravelry.
  Future<void> deleteBackup() async {
    final index = await _read([_indexKey]);
    final keys = [
      ...(index[_indexKey] ?? '').split(' ').where((key) => key.isNotEmpty),
      _indexKey,
      _countersKey,
      _settingsKey,
    ];
    await ravelry.postForm('/app/data/delete.json', {'keys': keys.join(' ')});
    await _db.delete('app_setting', where: "name LIKE 'backup_hash:%'");
  }

  Future<Map<String, String>> _read(List<String> keys) async {
    final reply = await ravelry.get('/app/data/get.json', query: {'keys': keys.join(' ')});
    final data = reply.body?['data'] as Map<String, dynamic>? ?? const {};
    return {
      for (final entry in data.entries)
        if (entry.value is String) entry.key: entry.value as String,
    };
  }

  /// The backup key for one PDF.
  static String fileKey(String sha256) => 'pn_f_${sha256.substring(0, 16)}';
}
