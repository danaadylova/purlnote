/// The parts of Ravelry's records that the Notebook shows.
///
/// Each model keeps only the fields the screens use. The full JSON is kept in
/// the local database, so adding a field later needs no new sync.
library;

/// The signed-in knitter.
class RavelryUser {
  const RavelryUser({required this.id, required this.username, this.firstName, this.photoUrl});

  factory RavelryUser.fromJson(Map<String, dynamic> json) {
    return RavelryUser(
      id: json['id'] as int,
      username: json['username'] as String,
      firstName: _text(json['first_name']),
      photoUrl: _text(json['small_photo_url']) ?? _text(json['photo_url']),
    );
  }

  final int id;
  final String username;
  final String? firstName;
  final String? photoUrl;

  /// What to call the knitter on screen.
  String get displayName => firstName ?? username;
}

/// One knitting or crochet project.
class Project {
  const Project({
    required this.id,
    required this.name,
    this.permalink,
    this.patternName,
    this.statusName,
    this.craftName,
    this.progressPercent,
    this.started,
    this.completed,
    this.photoUrl,
    this.updatedAt,
  });

  factory Project.fromJson(Map<String, dynamic> json) {
    final photo = json['first_photo'] as Map<String, dynamic>?;
    return Project(
      id: json['id'] as int,
      name: _text(json['name']) ?? 'Untitled project',
      permalink: _text(json['permalink']),
      patternName: _text(json['pattern_name']),
      statusName: _text(json['status_name']),
      craftName: _text(json['craft_name']),
      progressPercent: (json['progress'] as num?)?.toInt(),
      started: _date(json['started']),
      completed: _date(json['completed']),
      photoUrl: photo == null ? null : _text(photo['small_url']) ?? _text(photo['square_url']),
      updatedAt: _date(json['updated_at']),
    );
  }

  final int id;
  final String name;
  final String? permalink;
  final String? patternName;

  /// Ravelry's status, such as "In progress", "Finished" or "Hibernating".
  final String? statusName;
  final String? craftName;

  /// 0 to 100, or null if the knitter never set it.
  final int? progressPercent;
  final DateTime? started;
  final DateTime? completed;
  final String? photoUrl;
  final DateTime? updatedAt;

  bool get isOnTheNeedles => statusName == 'In progress';
}

/// A pattern the knitter has queued to make later.
class QueuedProject {
  const QueuedProject({required this.id, required this.patternName, this.position, this.patternId});

  factory QueuedProject.fromJson(Map<String, dynamic> json) {
    return QueuedProject(
      id: json['id'] as int,
      patternName:
          _text(json['short_pattern_name']) ?? _text(json['pattern_name']) ?? _text(json['name']) ?? 'Queued pattern',
      position: (json['position_in_queue'] as num?)?.toInt(),
      patternId: (json['pattern_id'] as num?)?.toInt(),
    );
  }

  final int id;
  final String patternName;

  /// 1 is the top of the queue.
  final int? position;
  final int? patternId;
}

/// One yarn in the knitter's stash.
class StashYarn {
  const StashYarn({
    required this.id,
    required this.name,
    this.colorway,
    this.weightName,
    this.companyName,
  });

  factory StashYarn.fromJson(Map<String, dynamic> json) {
    final yarn = json['yarn'] as Map<String, dynamic>?;
    return StashYarn(
      id: json['id'] as int,
      name: _text(yarn?['name']) ?? _text(json['name']) ?? 'Unnamed yarn',
      colorway: _text(json['colorway_name']),
      weightName: _text(json['yarn_weight_name']),
      companyName: _text(yarn?['yarn_company_name']),
    );
  }

  final int id;
  final String name;
  final String? colorway;
  final String? weightName;
  final String? companyName;
}

/// Ravelry sends empty strings for many unset fields; treat them as missing.
String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Ravelry dates look like "2026/11/04" or "2026/11/04 13:37:23 -0500".
DateTime? _date(Object? value) {
  final text = _text(value);
  if (text == null) return null;
  final match = RegExp(r'^(\d{4})[/-](\d{2})[/-](\d{2})').firstMatch(text);
  if (match == null) return null;
  return DateTime(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
}
