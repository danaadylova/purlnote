import 'dart:convert';
import 'dart:ui';

import 'package:sqflite/sqflite.dart';

import '../data/local_database.dart';
import '../library/library_models.dart';

/// What kind of mark an annotation is.
enum AnnotationKind { highlight, ink, note }

/// A mark on a PDF page: a highlight, a pen stroke or a pinned note.
///
/// Positions are stored as fractions of the page (0 to 1 on each axis), so
/// marks stay in place at any zoom and on any screen size. Annotations belong
/// to the file's SHA-256, so they come back if the same PDF is downloaded or
/// imported again.
class Annotation {
  const Annotation({
    required this.id,
    required this.fileSha256,
    required this.page,
    required this.kind,
    required this.points,
    this.text,
  });

  factory Annotation.fromRow(Map<String, Object?> row) {
    final coordinates = (jsonDecode(row['geometry'] as String) as List).cast<num>();
    return Annotation(
      id: row['id'] as int,
      fileSha256: row['file_sha256'] as String,
      page: row['page'] as int,
      kind: AnnotationKind.values.byName(row['kind'] as String),
      points: [
        for (var i = 0; i + 1 < coordinates.length; i += 2)
          Offset(coordinates[i].toDouble(), coordinates[i + 1].toDouble()),
      ],
      text: row['note_text'] as String?,
    );
  }

  final int id;
  final String fileSha256;
  final int page;
  final AnnotationKind kind;

  /// Highlight: two corners. Pen: the stroke's points. Note: where the pin is.
  final List<Offset> points;

  /// The note's text (notes only).
  final String? text;
}

/// Keeps what the reader saves: where the knitter stopped, their marks on the
/// page, and project counters. All of it stays on the phone.
class ReaderStore {
  ReaderStore(this.database, {DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  final LocalDatabase database;
  final DateTime Function() _now;

  Database get _db => database.sqlite;

  /// Project ID used for reading outside any project.
  static const noProject = 0;

  // Reading spots ----------------------------------------------------------

  /// The page to reopen [fileId] at, for [projectId] (or outside a project).
  Future<int?> savedPage(int fileId, {int projectId = noProject}) async {
    final rows = await _db.query(
      'reading_position',
      where: 'file_id = ? AND project_id = ?',
      whereArgs: [fileId, projectId],
    );
    return rows.isEmpty ? null : rows.first['page'] as int;
  }

  Future<void> savePage(int fileId, int page, {int projectId = noProject}) async {
    await _db.insert(
      'reading_position',
      {'file_id': fileId, 'project_id': projectId, 'page': page, 'saved_at': _now().millisecondsSinceEpoch},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// The file a project last had open in [files], if any.
  Future<int?> lastFileFor(int projectId, List<PatternFile> files) async {
    if (files.isEmpty) return null;
    final ids = files.map((file) => file.id).join(',');
    final rows = await _db.rawQuery(
      'SELECT file_id FROM reading_position WHERE project_id = ? AND file_id IN ($ids) ORDER BY saved_at DESC LIMIT 1',
      [projectId],
    );
    return rows.isEmpty ? null : rows.first['file_id'] as int;
  }

  // Annotations ------------------------------------------------------------

  Future<List<Annotation>> annotationsFor(String fileSha256) async {
    final rows = await _db.query('annotation', where: 'file_sha256 = ?', whereArgs: [fileSha256], orderBy: 'id');
    return rows.map(Annotation.fromRow).toList();
  }

  Future<int> addAnnotation({
    required String fileSha256,
    required int page,
    required AnnotationKind kind,
    required List<Offset> points,
    String? text,
  }) {
    final now = _now().millisecondsSinceEpoch;
    return _db.insert('annotation', {
      'file_sha256': fileSha256,
      'page': page,
      'kind': kind.name,
      'geometry': jsonEncode([for (final point in points) ...[_round(point.dx), _round(point.dy)]]),
      'note_text': text,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> updateNoteText(int annotationId, String text) async {
    await _db.update(
      'annotation',
      {'note_text': text, 'updated_at': _now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [annotationId],
    );
  }

  Future<void> deleteAnnotation(int annotationId) async {
    await _db.delete('annotation', where: 'id = ?', whereArgs: [annotationId]);
  }

  /// Four decimal places is under a tenth of a millimeter on a page.
  static double _round(double value) => (value * 10000).roundToDouble() / 10000;

  // Counters ---------------------------------------------------------------

  /// A project's counters, the row counter first. Creates the row counter the
  /// first time a project is opened in the reader.
  Future<List<ProjectCounter>> countersFor(int projectId) async {
    var rows = await _db.query('counter', where: 'project_id = ?', whereArgs: [projectId], orderBy: 'sort_order');
    if (rows.isEmpty) {
      await _db.insert('counter', {'project_id': projectId, 'label': 'Rows', 'value': 0, 'sort_order': 0});
      rows = await _db.query('counter', where: 'project_id = ?', whereArgs: [projectId], orderBy: 'sort_order');
    }
    return rows.map(ProjectCounter.fromRow).toList();
  }

  Future<void> setCounterValue(int counterId, int value) async {
    await _db.update('counter', {'value': value < 0 ? 0 : value}, where: 'id = ?', whereArgs: [counterId]);
  }

  /// Adds a repeat counter that follows the row counter from [startRow].
  Future<void> addRepeatCounter({
    required int projectId,
    required String label,
    required int everyNRows,
    required int startRow,
    int? totalRepeats,
  }) async {
    final count = Sqflite.firstIntValue(
          await _db.rawQuery('SELECT COUNT(*) FROM counter WHERE project_id = ?', [projectId]),
        ) ??
        0;
    await _db.insert('counter', {
      'project_id': projectId,
      'label': label,
      'value': startRow,
      'every_n_rows': everyNRows,
      'total_repeats': totalRepeats,
      'sort_order': count,
    });
  }

  Future<void> deleteCounter(int counterId) async {
    await _db.delete('counter', where: 'id = ?', whereArgs: [counterId]);
  }
}
