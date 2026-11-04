/// The pattern library: Ravelry purchases and imported PDFs, side by side.
library;

import '../app_paths.dart';

/// Where a pattern came from.
enum PatternSource { ravelry, imported }

/// One pattern in the library. A pattern is a set of files, not one file:
/// Ravelry purchases often hold a main PDF, charts, size ranges and so on.
class LibraryPattern {
  const LibraryPattern({
    required this.key,
    required this.title,
    required this.source,
    required this.files,
    this.author,
    this.coverUrl,
    this.ravelryPatternId,
    this.hasDownloads = false,
    this.addedAt,
    this.lastOpenedAt,
  });

  /// `volume:<Ravelry volume id>` or `import:<local id>`.
  final String key;
  final String title;
  final PatternSource source;
  final String? author;
  final String? coverUrl;

  /// The Ravelry pattern this is, if known. Projects knitting that pattern
  /// open it straight from the project.
  final int? ravelryPatternId;

  /// For Ravelry purchases: whether Ravelry has PDFs to download.
  final bool hasDownloads;

  /// The files known so far. For a purchase that hasn't been opened yet, this
  /// can be empty until Ravelry's file list is fetched.
  final List<PatternFile> files;
  final DateTime? addedAt;
  final DateTime? lastOpenedAt;

  bool get isOnPhone => files.any((file) => file.isDownloaded);

  static String volumeKey(int volumeId) => 'volume:$volumeId';
  static String importKey(int importId) => 'import:$importId';

  /// The Ravelry volume ID in a "volume:" key, or null.
  static int? volumeIdOf(String key) => key.startsWith('volume:') ? int.tryParse(key.substring(7)) : null;
}

/// One PDF in a pattern.
class PatternFile {
  const PatternFile({
    required this.id,
    required this.patternKey,
    required this.label,
    required this.sortOrder,
    this.attachmentId,
    this.localPath,
    this.sha256,
    this.bytes,
  });

  factory PatternFile.fromRow(Map<String, Object?> row) {
    return PatternFile(
      id: row['id'] as int,
      patternKey: row['pattern_key'] as String,
      label: row['label'] as String,
      sortOrder: row['sort_order'] as int,
      attachmentId: row['attachment_id'] as int?,
      localPath: row['local_path'] == null ? null : AppPaths.resolve(row['local_path'] as String),
      sha256: row['sha256'] as String?,
      bytes: row['bytes'] as int?,
    );
  }

  final int id;
  final String patternKey;

  /// What the reader's file tab says, such as "Charts".
  final String label;
  final int sortOrder;

  /// Ravelry's product attachment, for purchases.
  final int? attachmentId;

  /// Where the PDF is on the phone, once downloaded or imported.
  final String? localPath;
  final String? sha256;
  final int? bytes;

  bool get isDownloaded => localPath != null && sha256 != null;
}

/// What a counter counts.
class ProjectCounter {
  const ProjectCounter({
    required this.id,
    required this.projectId,
    required this.label,
    required this.value,
    required this.sortOrder,
    this.everyNRows,
    this.totalRepeats,
  });

  factory ProjectCounter.fromRow(Map<String, Object?> row) {
    return ProjectCounter(
      id: row['id'] as int,
      projectId: row['project_id'] as int,
      label: row['label'] as String,
      value: row['value'] as int,
      sortOrder: row['sort_order'] as int,
      everyNRows: row['every_n_rows'] as int?,
      totalRepeats: row['total_repeats'] as int?,
    );
  }

  final int id;
  final int projectId;
  final String label;

  /// For the row counter, the current row. For a repeat counter, the row
  /// it started on: it follows the row counter from there.
  final int value;
  final int sortOrder;

  /// Set for repeat counters, such as "decrease every 6 rows".
  final int? everyNRows;
  final int? totalRepeats;

  bool get isRepeat => everyNRows != null;

  /// For a repeat counter: how many repeats are done at [rows].
  int repeatsDone(int rows) {
    final every = everyNRows!;
    final done = rows <= value ? 0 : (rows - value) ~/ every;
    final total = totalRepeats;
    return total == null ? done : done.clamp(0, total);
  }

  /// For a repeat counter: rows until the next repeat at [rows].
  int rowsUntilNext(int rows) {
    final every = everyNRows!;
    if (rows < value) return value - rows + every;
    return every - (rows - value) % every;
  }
}
