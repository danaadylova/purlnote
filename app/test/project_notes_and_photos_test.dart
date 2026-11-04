import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:purlnote/app_session.dart';
import 'package:purlnote/auth/auth_service.dart';
import 'package:purlnote/auth/tokens.dart';
import 'package:purlnote/data/local_database.dart';
import 'package:purlnote/data/local_projects.dart';
import 'package:purlnote/projects/project_notes.dart';
import 'package:purlnote/projects/project_photos.dart';
import 'package:purlnote/ravelry/models.dart';
import 'package:purlnote/ravelry/ravelry_client.dart';

import 'support/fakes.dart';

void main() {
  group('notes as entries', () {
    test('split on blank lines and join back the same way', () {
      const notes = '2026-11-01: Cast on.\n\n2026-11-03: Switched to 4 mm.\nStill on the yoke.';
      final entries = noteEntries(notes);
      expect(entries, ['2026-11-01: Cast on.', '2026-11-03: Switched to 4 mm.\nStill on the yoke.']);
      expect(joinNoteEntries(entries), notes);
      expect(noteEntries(null), isEmpty);
      expect(noteEntries('  \n\n  '), isEmpty);
    });

    test('a new note starts with its date', () {
      expect(datedNote(' Blocked it. ', DateTime(2026, 11, 4)), '2026-11-04: Blocked it.');
    });
  });

  group('on a project kept on the phone', () {
    late LocalDatabase database;
    late AppSession session;

    setUp(() async {
      database = await emptyDatabase();
      final offline = MockClient((_) async => http.Response('offline', 500));
      final auth = AuthService(config: testConfig, tokenStore: MemoryTokenStore(), httpClient: offline);
      session = AppSession(
        auth: auth,
        database: database,
        sync: syncEngineFor(ravelryHttp: offline, database: database, auth: auth),
      );
      await session.startWithoutRavelry();
    });

    tearDown(() => database.close());

    test('notes can be added one after another, edited and deleted', () async {
      final id = await session.createProject(name: 'Socks');

      expect(await session.addProjectNote(id, 'Cast on 64.'), isNull);
      expect(await session.addProjectNote(id, 'Heel flap done.'), isNull);
      var entries = noteEntries(session.projectById(id)!.notes);
      expect(entries, hasLength(2));
      expect(entries.last, endsWith(': Heel flap done.'));

      await session.editProjectNote(id, 0, 'Cast on 60 instead.');
      await session.editProjectNote(id, 1, null);
      entries = noteEntries(session.projectById(id)!.notes);
      expect(entries, ['Cast on 60 instead.']);
    });

    test('photos are kept on the phone and can be deleted', () async {
      final folder = Directory.systemTemp.createTempSync('purlnote_photos_');
      final photos = ProjectPhotos(
        ravelry: RavelryClient(baseUrl: testConfig.ravelryApiUrl, auth: session.auth),
        database: database,
        localProjects: LocalProjects(database),
        folder: () async => folder,
      );
      final id = await session.createProject(name: 'Socks');

      await photos.add(projectId: id, username: null, bytes: Uint8List.fromList([1, 2, 3]), fileName: 'a.jpg');
      await photos.add(projectId: id, username: null, bytes: Uint8List.fromList([4, 5, 6]), fileName: 'b.jpg');
      var pictures = Project.fromJson((await LocalProjects(database).byId(id))!).pictures;
      expect(pictures, hasLength(2));
      expect(File(pictures.first.localPath!).existsSync(), isTrue);

      await photos.deleteFromPhone(projectId: id, path: pictures.first.localPath!);
      pictures = Project.fromJson((await LocalProjects(database).byId(id))!).pictures;
      expect(pictures, hasLength(1));
      expect(folder.listSync(), hasLength(1));
    });
  });

  test('a Ravelry photo is uploaded, attached to the project, and deletable', () async {
    final requests = <http.BaseRequest>[];
    final fake = MockClient.streaming((request, body) async {
      requests.add(request);
      final path = request.url.path;
      String reply = '{}';
      if (path == '/upload/request_token.json') reply = '{"upload_token": "tok"}';
      if (path == '/upload/image.json') reply = '{"uploads": {"file0": {"image_id": 16}}}';
      if (path.endsWith('/create_photo.json')) reply = '{"status_token": "s"}';
      if (path == '/photos/99.json') reply = '{"photo": {"id": 99}}';
      return http.StreamedResponse(Stream.value(reply.codeUnits), 200);
    });
    final database = await emptyDatabase();
    await database.replaceRecords(RecordType.project, [
      {
        'id': 10,
        'name': 'Raglan',
        'photos': [
          {'id': 99, 'square_url': 'a'},
          {'id': 100, 'square_url': 'b'},
        ],
      },
    ], testNow);
    final photos = ProjectPhotos(
      ravelry: RavelryClient(baseUrl: testConfig.ravelryApiUrl, auth: await signedInAuth(), httpClient: fake),
      database: database,
      localProjects: LocalProjects(database),
    );

    await photos.add(projectId: 10, username: 'dana', bytes: Uint8List.fromList([1]), fileName: 'p.jpg');
    expect(requests.map((r) => r.url.path), [
      '/upload/request_token.json',
      '/upload/image.json',
      '/projects/dana/10/create_photo.json',
    ]);
    expect(requests[1].headers['Authorization'], isNull, reason: 'the upload uses its one-time token');

    await photos.deleteFromRavelry(projectId: 10, photoId: 99);
    final stored = Project.fromJson((await database.record(RecordType.project, 10))!);
    expect(stored.pictures.map((p) => p.ravelryId), [100]);
    await database.close();
  });
}
