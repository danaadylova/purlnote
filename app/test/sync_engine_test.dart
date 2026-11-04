import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:purlnote/data/local_database.dart';
import 'package:purlnote/data/sync_engine.dart';
import 'package:purlnote/ravelry/ravelry_client.dart';

import 'support/fake_ravelry.dart';
import 'support/fakes.dart';

void main() {
  late FakeRavelry ravelry;
  late LocalDatabase database;
  late SyncEngine engine;

  setUp(() async {
    ravelry = FakeRavelry();
    database = await emptyDatabase();
    final auth = await signedInAuth(
      signInFunction: MockClient((_) async => jsonReply({'access_token': 'access-2', 'expires_in': 3600})),
    );
    engine = syncEngineFor(ravelryHttp: ravelry.client, database: database, auth: auth);
  });

  tearDown(() => database.close());

  test('the first sync stores profile, projects, queue, stash and library in order', () async {
    final progress = <SyncStep, int>{};
    await engine.syncEverything(onProgress: (step, count) => progress[step] = count);

    expect(progress, {
      SyncStep.profile: 1,
      SyncStep.projects: 2,
      SyncStep.queue: 1,
      SyncStep.stash: 1,
      SyncStep.library: 1,
    });
    expect((await database.records(RecordType.user)).single['username'], 'unraveled-makes');
    expect((await database.records(RecordType.project)).map((p) => p['name']), ['Harbour Raglan', 'Petal Drop Socks']);
    expect((await database.records(RecordType.stash)).single['id'], 30);
    expect(await database.lastSyncedAt(), testNow);
  });

  test('every request carries the access token', () async {
    await engine.syncEverything();
    for (final request in ravelry.requests) {
      expect(request.headers['Authorization'], 'Bearer access-1');
    }
  });

  test('a second sync with nothing changed keeps everything and sends version tags', () async {
    await engine.syncEverything();
    ravelry.requests.clear();

    await engine.syncEverything();

    expect(ravelry.requests.every((r) => r.headers['If-None-Match'] != null), isTrue);
    expect(await database.records(RecordType.project), hasLength(2));
  });

  test('changes on Ravelry replace what was stored', () async {
    await engine.syncEverything();
    ravelry.projects = [ravelry.projects.first];

    await engine.syncEverything();

    expect((await database.records(RecordType.project)).single['id'], 10);
  });

  test('long lists are fetched page by page', () async {
    ravelry.stash = [
      for (var id = 1; id <= 5; id++)
        {
          'id': id,
          'yarn': {'name': 'Yarn $id'}
        }
    ];
    ravelry.stashPageSize = 2;

    await engine.syncEverything();

    expect(ravelry.countRequestsTo('/people/unraveled-makes/stash/list.json'), 3);
    expect((await database.records(RecordType.stash)).map((y) => y['id']), [1, 2, 3, 4, 5]);
    // Version tags only cover one page, so long lists aren't tagged.
    expect(await database.etagFor('stash'), isNull);
  });

  test('a rejected token is refreshed once and the request retried', () async {
    ravelry.rejectNextToken = true;

    await engine.syncEverything();

    final profileRequests = ravelry.requests.where((r) => r.url.path == '/current_user.json').toList();
    expect(profileRequests, hasLength(2));
    expect(profileRequests.last.headers['Authorization'], 'Bearer access-2');
  });

  test('offline, the sync stops and stored records stay', () async {
    await engine.syncEverything();
    final offline = syncEngineFor(
      ravelryHttp: MockClient((_) async => throw http.ClientException('offline')),
      database: database,
      auth: await signedInAuth(),
    );

    await expectLater(offline.syncEverything(), throwsA(isA<RavelryUnreachable>()));
    expect(await database.records(RecordType.project), hasLength(2));
  });
}
