import 'package:sqflite/sqflite.dart';

import '../data/local_database.dart';
import 'step_models.dart';

/// Where one project is in a file's steps.
class StepProgress {
  const StepProgress({required this.currentStep, required this.sizeIndex, required this.nextMovesCounter});

  /// Index into the visible steps.
  final int currentStep;

  /// The size being made (0 is the first size), or null if not chosen yet.
  final int? sizeIndex;

  /// Whether Next also moves the project's row counter on row steps.
  final bool nextMovesCounter;
}

/// Keeps steps per PDF (by SHA-256) and each project's place in them.
class StepsStore {
  StepsStore(this.database);

  final LocalDatabase database;

  Database get _db => database.sqlite;

  /// Every step for a file, hidden ones included, in order.
  Future<List<PatternStep>> stepsFor(String fileSha256) async {
    final rows = await _db.query('pattern_step', where: 'file_sha256 = ?', whereArgs: [fileSha256], orderBy: 'step_order');
    return rows.map(PatternStep.fromRow).toList();
  }

  /// Replaces a file's steps (a first build or "Rebuild steps").
  Future<void> replaceSteps(String fileSha256, List<PatternStep> steps) async {
    await _db.transaction((txn) async {
      await txn.delete('pattern_step', where: 'file_sha256 = ?', whereArgs: [fileSha256]);
      final batch = txn.batch();
      for (var order = 0; order < steps.length; order++) {
        batch.insert('pattern_step', steps[order].toRow(fileSha256, order * 10));
      }
      await batch.commit(noResult: true);
    });
  }

  /// Adds steps after those already stored, for building page by page.
  Future<void> appendSteps(String fileSha256, List<PatternStep> steps) async {
    final last = Sqflite.firstIntValue(
          await _db.rawQuery('SELECT MAX(step_order) FROM pattern_step WHERE file_sha256 = ?', [fileSha256]),
        ) ??
        -10;
    final batch = _db.batch();
    for (var i = 0; i < steps.length; i++) {
      batch.insert('pattern_step', steps[i].toRow(fileSha256, last + (i + 1) * 10));
    }
    await batch.commit(noResult: true);
  }

  // The knitter's fixes ------------------------------------------------------

  Future<void> editText(PatternStep step, String text) async {
    await _db.update('pattern_step', {'text': text, 'made_by': StepMaker.edited.name}, where: 'id = ?', whereArgs: [step.id]);
  }

  Future<void> hide(PatternStep step) async {
    await _db.update('pattern_step', {'hidden': 1}, where: 'id = ?', whereArgs: [step.id]);
  }

  /// Joins [step] with [next]: one step with both texts.
  Future<void> join(PatternStep step, PatternStep next) async {
    await _db.update(
      'pattern_step',
      {'text': '${step.text} ${next.text}', 'made_by': StepMaker.edited.name},
      where: 'id = ?',
      whereArgs: [step.id],
    );
    await _db.delete('pattern_step', where: 'id = ?', whereArgs: [next.id]);
  }

  /// Splits [step] (of the file [fileSha256]) at [at], a position in its
  /// text, into two steps.
  Future<void> split(String fileSha256, PatternStep step, int at) async {
    final first = step.text.substring(0, at).trim();
    final second = step.text.substring(at).trim();
    if (first.isEmpty || second.isEmpty) return;
    await _db.update('pattern_step', {'text': first, 'made_by': StepMaker.edited.name}, where: 'id = ?', whereArgs: [step.id]);
    // Orders are spaced by 10, so there's room right after this step. The
    // second part isn't a row of its own, so it doesn't move the counter.
    await _db.insert('pattern_step', {
      ...step.copyWith(text: second, madeBy: StepMaker.edited).toRow(fileSha256, step.order + 1),
      'label': null,
      'side': null,
    });
  }

  // Progress -----------------------------------------------------------------

  Future<StepProgress> progress(int projectId, String fileSha256) async {
    final rows = await _db.query(
      'step_progress',
      where: 'project_id = ? AND file_sha256 = ?',
      whereArgs: [projectId, fileSha256],
    );
    if (rows.isEmpty) return const StepProgress(currentStep: 0, sizeIndex: null, nextMovesCounter: true);
    return StepProgress(
      currentStep: rows.first['current_step'] as int,
      sizeIndex: rows.first['size_index'] as int?,
      nextMovesCounter: rows.first['next_moves_counter'] == 1,
    );
  }

  Future<void> saveProgress(int projectId, String fileSha256, StepProgress progress) async {
    await _db.insert(
      'step_progress',
      {
        'project_id': projectId,
        'file_sha256': fileSha256,
        'current_step': progress.currentStep,
        'size_index': progress.sizeIndex,
        'next_moves_counter': progress.nextMovesCounter ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
