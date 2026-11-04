import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'local_database.dart';

/// Projects kept on this phone only.
///
/// They use negative IDs (-1, -2, …) so they can sit next to Ravelry
/// projects, and so counters, reading spots and steps (all keyed by project
/// ID) work the same for both. Each project is stored with Ravelry's field
/// names, so screens and edits treat both kinds alike.
class LocalProjects {
  LocalProjects(this.database, {DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  final LocalDatabase database;
  final DateTime Function() _now;

  Database get _db => database.sqlite;

  /// Statuses offered for phone-only projects, until Ravelry's own list has
  /// been synced.
  static const statusNames = ['In progress', 'Finished', 'Hibernating', 'Frogged'];

  static bool isLocal(int projectId) => projectId < 0;

  /// Every phone-only project, newest first, as Ravelry-style records.
  Future<List<Map<String, dynamic>>> all() async {
    final rows = await _db.query('local_project', orderBy: 'id DESC');
    return [for (final row in rows) _record(row)];
  }

  Future<Map<String, dynamic>?> byId(int projectId) async {
    final rows = await _db.query('local_project', where: 'id = ?', whereArgs: [-projectId]);
    return rows.isEmpty ? null : _record(rows.first);
  }

  /// Starts a project. Returns its (negative) ID.
  Future<int> create({required String name, String? patternName, String statusName = 'In progress'}) async {
    final now = _now();
    final started = '${now.year}/${_two(now.month)}/${_two(now.day)}';
    final id = await _db.insert('local_project', {
      'body': jsonEncode({
        'name': name,
        'pattern_name': patternName,
        'status_name': statusName,
        'progress': 0,
        'started': started,
      }),
      'created_at': now.millisecondsSinceEpoch,
    });
    return -id;
  }

  /// Merges [fields] (Ravelry field names) into a project.
  Future<void> update(int projectId, Map<String, Object?> fields) async {
    final current = await byId(projectId);
    if (current == null) return;
    final body = {...current, ...fields}..remove('id');
    await _db.update('local_project', {'body': jsonEncode(body)}, where: 'id = ?', whereArgs: [-projectId]);
  }

  Future<void> delete(int projectId) => _db.delete('local_project', where: 'id = ?', whereArgs: [-projectId]);

  /// After a project is added to Ravelry, moves everything the phone kept
  /// for it (counters, reading spots, steps, its pattern) to the new
  /// Ravelry ID, and removes the phone-only copy.
  Future<void> moveTo(int projectId, int ravelryId) async {
    await _db.transaction((txn) async {
      for (final table in ['counter', 'reading_position', 'step_progress', 'project_pattern']) {
        await txn.update(table, {'project_id': ravelryId}, where: 'project_id = ?', whereArgs: [projectId]);
      }
      await txn.delete('local_project', where: 'id = ?', whereArgs: [-projectId]);
    });
  }

  Map<String, dynamic> _record(Map<String, Object?> row) {
    return {...jsonDecode(row['body'] as String) as Map<String, dynamic>, 'id': -(row['id'] as int)};
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}
