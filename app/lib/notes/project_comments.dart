import 'package:sqflite/sqflite.dart';

import '../data/local_database.dart';
import '../ravelry/ravelry_client.dart';

/// Where a note sent to a project's comments stands.
enum CommentState {
  /// Saved on the phone; posted at the next sync.
  waiting,

  /// On Ravelry. [ProjectCommentRecord.postedCommentId] is its ID there.
  posted,

  /// Ravelry refused it.
  failed,
}

/// A note that was sent (or is waiting to be sent) to a project's comments.
class ProjectCommentRecord {
  const ProjectCommentRecord({
    required this.id,
    required this.projectId,
    required this.body,
    required this.state,
    required this.attempts,
    this.annotationId,
    this.postedCommentId,
    this.problem,
    this.nextAttemptAt,
  });

  factory ProjectCommentRecord.fromRow(Map<String, Object?> row) {
    final next = row['next_attempt_at'] as int?;
    return ProjectCommentRecord(
      id: row['id'] as int,
      projectId: row['project_id'] as int,
      body: row['body'] as String,
      state: CommentState.values.byName(row['state'] as String),
      attempts: row['attempts'] as int,
      annotationId: row['annotation_id'] as int?,
      postedCommentId: row['posted_comment_id'] as int?,
      problem: row['problem'] as String?,
      nextAttemptAt: next == null ? null : DateTime.fromMillisecondsSinceEpoch(next),
    );
  }

  final int id;
  final int projectId;
  final String body;
  final CommentState state;
  final int attempts;

  /// The note on the page this came from, if any.
  final int? annotationId;
  final int? postedCommentId;
  final String? problem;
  final DateTime? nextAttemptAt;
}

/// A comment on a project, as Ravelry shows it.
class RavelryComment {
  const RavelryComment({required this.id, required this.body, this.author, this.createdAt});

  factory RavelryComment.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>?;
    return RavelryComment(
      id: json['id'] as int,
      body: plainText((json['body'] as String?) ?? ''),
      author: user?['username'] as String?,
      createdAt: json['created_at'] as String?,
    );
  }

  final int id;
  final String body;
  final String? author;
  final String? createdAt;
}

/// Ravelry returns comments as HTML (it turns Markdown into HTML). This
/// gives back the text, for showing and for matching against what was sent.
String plainText(String html) {
  final withBreaks = html.replaceAll(RegExp(r'<br\s*/?>|</p>\s*<p>', caseSensitive: false), '\n');
  final text = withBreaks.replaceAll(RegExp(r'<[^>]+>'), '');
  return text
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .trim();
}

/// Turns notes into comments on a project, and keeps them until Ravelry has
/// them. Comments are public, can't be edited on Ravelry, and must never be
/// posted twice, so before trying again after a failed send this checks
/// whether the first try got through after all.
class ProjectComments {
  ProjectComments({required this.ravelry, required this.database, DateTime Function()? clock})
      : _now = clock ?? DateTime.now;

  final RavelryClient ravelry;
  final LocalDatabase database;
  final DateTime Function() _now;

  Database get _db => database.sqlite;

  /// Saves a comment to post at the next sync.
  Future<int> queue({required int projectId, required String body, int? annotationId}) {
    return _db.insert('project_comment', {
      'project_id': projectId,
      'body': body,
      'annotation_id': annotationId,
      'state': CommentState.waiting.name,
      'created_at': _now().millisecondsSinceEpoch,
    });
  }

  /// Comments for one project that haven't been posted yet.
  Future<List<ProjectCommentRecord>> unsent(int projectId) async {
    final rows = await _db.query(
      'project_comment',
      where: 'project_id = ? AND state != ?',
      whereArgs: [projectId, CommentState.posted.name],
      orderBy: 'id',
    );
    return rows.map(ProjectCommentRecord.fromRow).toList();
  }

  /// The latest comment a note on the page was posted as, if any.
  Future<ProjectCommentRecord?> forAnnotation(int annotationId) async {
    final rows = await _db.query(
      'project_comment',
      where: 'annotation_id = ?',
      whereArgs: [annotationId],
      orderBy: 'id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : ProjectCommentRecord.fromRow(rows.first);
  }

  /// Stops a waiting comment from being posted.
  Future<void> cancel(int id) => _db.delete('project_comment', where: 'id = ? AND state != ?', whereArgs: [id, 'posted']);

  /// Posts every waiting comment. Returns how many were posted. Stops when
  /// Ravelry can't be reached; the rest wait for next time.
  Future<int> sendAll({required String username}) async {
    final rows = await _db.query('project_comment', where: 'state = ?', whereArgs: [CommentState.waiting.name], orderBy: 'id');
    var posted = 0;
    for (final comment in rows.map(ProjectCommentRecord.fromRow)) {
      final notBefore = comment.nextAttemptAt;
      if (notBefore != null && _now().isBefore(notBefore)) continue;
      try {
        await _send(comment, username);
        posted++;
      } on RavelryUnreachable {
        // A send may have reached Ravelry before the connection dropped;
        // the next try checks first.
        await _db.update('project_comment', {'attempts': comment.attempts + 1}, where: 'id = ?', whereArgs: [comment.id]);
        break;
      } on RavelryError catch (error) {
        await _recordFailure(comment, error);
      }
    }
    return posted;
  }

  Future<void> _send(ProjectCommentRecord comment, String username) async {
    if (comment.attempts > 0) {
      final alreadyPosted = await _findPosted(comment, username);
      if (alreadyPosted != null) {
        await _markPosted(comment.id, alreadyPosted);
        return;
      }
    }
    final reply = await ravelry.postForm('/comments/create.json', {
      'type': 'project',
      'commented_id': '${comment.projectId}',
      'body': comment.body,
    });
    final id = (reply['comment'] as Map<String, dynamic>?)?['id'] as int?;
    await _markPosted(comment.id, id);
  }

  /// Looks for an earlier try of [comment] among the project's comments.
  Future<int?> _findPosted(ProjectCommentRecord comment, String username) async {
    final comments = await load(username: username, projectId: comment.projectId);
    final mine = comments.where((c) => c.author == username && c.body.trim() == comment.body.trim());
    return mine.isEmpty ? null : mine.last.id;
  }

  Future<void> _markPosted(int id, int? ravelryCommentId) async {
    await _db.update(
      'project_comment',
      {'state': CommentState.posted.name, 'posted_comment_id': ravelryCommentId, 'problem': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> _recordFailure(ProjectCommentRecord comment, RavelryError error) async {
    if (error.isTemporary) {
      final attempts = comment.attempts + 1;
      final minutes = attempts >= 7 ? 60 : 1 << (attempts - 1);
      await _db.update(
        'project_comment',
        {'attempts': attempts, 'next_attempt_at': _now().add(Duration(minutes: minutes)).millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [comment.id],
      );
      return;
    }
    final problem = error.statusCode == 403
        ? 'Ravelry didn\'t allow this comment. Check that Purlnote may post comments.'
        : 'Ravelry refused this comment (error ${error.statusCode}).';
    await _db.update(
      'project_comment',
      {'state': CommentState.failed.name, 'problem': problem},
      where: 'id = ?',
      whereArgs: [comment.id],
    );
  }

  /// The comments on a project, oldest first. Throws [RavelryUnreachable]
  /// offline.
  Future<List<RavelryComment>> load({required String username, required int projectId}) async {
    final reply = await ravelry.get(
      '/projects/${Uri.encodeComponent(username)}/$projectId.json',
      query: const {'include': 'comments'},
    );
    final comments = reply.body!['comments'] as List<dynamic>? ?? const [];
    return [for (final comment in comments) RavelryComment.fromJson(comment as Map<String, dynamic>)];
  }

  /// Deletes one of the knitter's comments on Ravelry.
  Future<void> deletePosted(int ravelryCommentId) async {
    await ravelry.delete('/comments/$ravelryCommentId.json');
    await _db.delete('project_comment', where: 'posted_comment_id = ?', whereArgs: [ravelryCommentId]);
  }
}

/// Where in the pattern a note was made, written at the start of a comment so
/// it reads sensibly on the Ravelry website: "[Charts p.2 · row 31] ...".
class NoteTag {
  const NoteTag({required this.page, this.fileLabel, this.row});

  /// The file's name, given only when a pattern has more than one file.
  final String? fileLabel;
  final int page;

  /// The row counter when the note was made, if the project has one going.
  final int? row;

  String get text {
    final where = [if (fileLabel != null) fileLabel, 'p.$page'].join(' ');
    return row == null || row == 0 ? '[$where]' : '[$where · row $row]';
  }

  /// "[tag] note text".
  String commentBody(String note) => '$text ${note.trim()}';

  static final _pattern = RegExp(r'^\[(?:(.+?) )?p\.(\d+)(?: · row (\d+))?\]');

  /// Reads the tag at the start of a comment, or null if there is none.
  static NoteTag? parse(String comment) {
    final match = _pattern.firstMatch(comment.trim());
    if (match == null) return null;
    return NoteTag(
      fileLabel: match.group(1),
      page: int.parse(match.group(2)!),
      row: match.group(3) == null ? null : int.parse(match.group(3)!),
    );
  }
}
