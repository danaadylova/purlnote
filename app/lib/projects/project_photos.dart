import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/local_database.dart';
import '../data/local_projects.dart';
import '../ravelry/ravelry_client.dart';

/// Adds and removes project photos.
///
/// Photos of Ravelry projects go to Ravelry (that's where they're kept and
/// shown); photos of projects kept on the phone stay in the app's own folder.
/// Adding to Ravelry needs a connection, since Ravelry processes each photo.
class ProjectPhotos {
  ProjectPhotos({
    required this.ravelry,
    required this.database,
    required this.localProjects,
    Future<Directory> Function()? folder,
  }) : _folder = folder ?? _defaultFolder;

  final RavelryClient ravelry;
  final LocalDatabase database;
  final LocalProjects localProjects;
  final Future<Directory> Function() _folder;

  /// Adds a photo to a project. Throws [RavelryUnreachable] offline for
  /// Ravelry projects.
  Future<void> add({required int projectId, required String? username, required Uint8List bytes, required String fileName}) async {
    if (LocalProjects.isLocal(projectId)) {
      final path = await _keepOnPhone(bytes, fileName);
      final project = await localProjects.byId(projectId);
      final photos = [...(project?['local_photos'] as List<dynamic>? ?? const []).cast<String>(), path];
      await localProjects.update(projectId, {'local_photos': photos});
      return;
    }
    final imageId = await ravelry.uploadImage(bytes, fileName);
    await ravelry.postForm(
      '/projects/${Uri.encodeComponent(username!)}/$projectId/create_photo.json',
      {'image_id': '$imageId'},
    );
  }

  /// Removes a Ravelry photo, and takes it off the stored project at once.
  Future<void> deleteFromRavelry({required int projectId, required int photoId}) async {
    await ravelry.delete('/photos/$photoId.json');
    final project = await database.record(RecordType.project, projectId);
    if (project == null) return;
    final photos = (project['photos'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .where((photo) => photo['id'] != photoId)
        .toList();
    await database.updateRecord(RecordType.project, projectId, {
      'photos': photos,
      'first_photo': photos.isEmpty ? null : photos.first,
    }, DateTime.now());
  }

  /// Removes a photo kept on the phone.
  Future<void> deleteFromPhone({required int projectId, required String path}) async {
    final project = await localProjects.byId(projectId);
    // Saved paths may predate a move of the app's folder, so match by name.
    final photos = (project?['local_photos'] as List<dynamic>? ?? const [])
        .cast<String>()
        .where((saved) => p.basename(saved) != p.basename(path));
    await localProjects.update(projectId, {'local_photos': photos.toList()});
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  Future<String> _keepOnPhone(Uint8List bytes, String fileName) async {
    final folder = await _folder();
    await folder.create(recursive: true);
    final extension = p.extension(fileName).isEmpty ? '.jpg' : p.extension(fileName);
    final file = File(p.join(folder.path, '${sha256.convert(bytes)}$extension'));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static Future<Directory> _defaultFolder() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'project_photos'));
  }
}
