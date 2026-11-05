import 'package:flutter_test/flutter_test.dart';
import 'package:purlnote/app_session.dart';
import 'package:purlnote/data/local_database.dart';
import 'package:purlnote/notes/project_comments.dart';
import 'package:purlnote/ravelry/ravelry_client.dart';

import 'support/fake_ravelry.dart';
import 'support/fakes.dart';

void main() {
  late FakeRavelry ravelry;
  late LocalDatabase database;
  late AppSession session;

  setUp(() async {
    ravelry = FakeRavelry();
    database = await emptyDatabase();
    final auth = await signedInAuth();
    final client = RavelryClient(baseUrl: testConfig.ravelryApiUrl, auth: auth, httpClient: ravelry.client);
    session = AppSession(
      auth: auth,
      database: database,
      comments: ProjectComments(ravelry: client, database: database),
      sync: syncEngineFor(ravelryHttp: ravelry.client, database: database, auth: auth),
    );
    await session.start();
    session.finishFirstSync();
    final me = session.user!.username;
    ravelry.comments[10] = [
      {'id': 1, 'body': '<p>Lovely colour!</p>', 'user': {'username': 'friendly-knitter'}},
      {'id': 2, 'body': '<p>Buy my stuff</p>', 'user': {'username': 'spammer'}},
      {'id': 3, 'body': '<p>More spam</p>', 'user': {'username': 'spammer'}},
      {'id': 4, 'body': '<p>[p.2] Switched needles</p>', 'user': {'username': me}},
    ];
  });

  tearDown(() => database.close());

  Future<List<int>> shownIds() async => [for (final comment in (await session.loadComments(10))!) comment.id];

  test('a hidden comment, and everything from a hidden person, stop showing', () async {
    expect(await shownIds(), [1, 2, 3, 4]);

    await session.hideComment(1);
    expect(await shownIds(), [2, 3, 4]);

    await session.hideCommentsFrom('spammer');
    expect(await shownIds(), [4], reason: 'your own comments always show');
    expect(await session.hasHiddenComments(), isTrue);

    await session.showHiddenComments();
    expect(await shownIds(), [1, 2, 3, 4]);
    expect(await session.hasHiddenComments(), isFalse);
  });

  test('"delete or report" opens the project on Ravelry', () {
    final project = session.projectById(10)!;
    final page = session.ravelryPageFor(project).toString();
    expect(page, startsWith('https://www.ravelry.com/projects/${session.user!.username}'));
  });
}
