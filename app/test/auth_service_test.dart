import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:purlnote/auth/auth_service.dart';
import 'package:purlnote/auth/tokens.dart';

import 'support/fakes.dart';

void main() {
  late MemoryTokenStore store;
  late List<http.Request> sentToFunction;

  setUp(() {
    store = MemoryTokenStore();
    sentToFunction = [];
  });

  /// An AuthService whose sign-in function answers with [reply], and whose
  /// sign-in page answers with whatever [approve] returns.
  AuthService makeAuth({
    required http.Response Function(http.Request request) reply,
    String Function(Uri page)? approve,
    DateTime Function()? clock,
  }) {
    return AuthService(
      config: testConfig,
      tokenStore: store,
      clock: clock ?? () => testNow,
      httpClient: MockClient((request) async {
        sentToFunction.add(request);
        return reply(request);
      }),
      openSignInPage: (page, scheme) async {
        expect(scheme, 'purlnote');
        return (approve ?? _approveWithCode)(page);
      },
    );
  }

  group('sign-in', () {
    test('opens Ravelry with the right request and stores the tokens', () async {
      Uri? openedPage;
      final auth = makeAuth(
        reply: (_) => jsonReply({'access_token': 'a1', 'refresh_token': 'r1', 'expires_in': 3600}),
        approve: (page) {
          openedPage = page;
          return _approveWithCode(page);
        },
      );

      await auth.signIn();

      expect(openedPage!.host, 'www.ravelry.com');
      expect(openedPage!.queryParameters['client_id'], 'test-client-id');
      expect(openedPage!.queryParameters['redirect_uri'], 'purlnote://oauth-callback');
      expect(openedPage!.queryParameters['scope'], 'offline');

      final exchange = sentToFunction.single;
      expect(exchange.url.toString(), 'https://signin.test/token');
      expect(exchange.bodyFields, {
        'grant_type': 'authorization_code',
        'code': 'code-123',
        'redirect_uri': 'purlnote://oauth-callback',
      });

      final saved = await store.read();
      expect(saved!.accessToken, 'a1');
      expect(saved.refreshToken, 'r1');
      expect(saved.expiresAt, testNow.add(const Duration(hours: 1)));
    });

    test('refuses a reply whose state does not match', () async {
      final auth = makeAuth(
        reply: (_) => jsonReply({'access_token': 'a1'}),
        approve: (_) => 'purlnote://oauth-callback?code=code-123&state=someone-else',
      );

      await expectLater(auth.signIn(), throwsA(isA<SignInFailed>()));
      expect(sentToFunction, isEmpty);
      expect(await store.read(), isNull);
    });

    test('treats "Deny" on Ravelry as cancelled', () async {
      final auth = makeAuth(
        reply: (_) => jsonReply({}),
        approve: (_) => 'purlnote://oauth-callback?error=access_denied',
      );
      await expectLater(auth.signIn(), throwsA(isA<SignInCancelled>()));
    });

    test('explains when the sign-in function says no', () async {
      final auth = makeAuth(
        reply: (_) => jsonReply({'error': 'server_error', 'error_description': 'Sign-in is not set up yet.'}, status: 500),
      );
      await expectLater(
        auth.signIn(),
        throwsA(isA<SignInFailed>().having((e) => e.message, 'message', contains('not set up'))),
      );
    });

    test('explains when the network is down', () async {
      final auth = AuthService(
        config: testConfig,
        tokenStore: store,
        httpClient: MockClient((_) async => throw const SocketLikeException()),
        openSignInPage: (page, _) async => _approveWithCode(page),
      );
      await expectLater(
        auth.signIn(),
        throwsA(isA<SignInFailed>().having((e) => e.message, 'message', contains('Could not reach'))),
      );
    });
  });

  group('access tokens', () {
    test('returns the stored token while it is still good', () async {
      await store.write(freshTokens());
      final auth = makeAuth(reply: (_) => fail('should not refresh'));
      expect(await auth.accessToken(), 'access-1');
    });

    test('refreshes a token that expires within two minutes', () async {
      await store.write(Tokens(
        accessToken: 'old',
        refreshToken: 'refresh-1',
        expiresAt: testNow.add(const Duration(minutes: 1)),
      ));
      final auth = makeAuth(reply: (_) => jsonReply({'access_token': 'new', 'expires_in': 3600}));

      expect(await auth.accessToken(), 'new');
      expect(sentToFunction.single.bodyFields, {'grant_type': 'refresh_token', 'refresh_token': 'refresh-1'});
      // Ravelry sent no new refresh token, so the old one is kept.
      expect((await store.read())!.refreshToken, 'refresh-1');
    });

    test('several callers share one refresh', () async {
      await store.write(freshTokens());
      final release = Completer<void>();
      final auth = AuthService(
        config: testConfig,
        tokenStore: store,
        clock: () => testNow,
        httpClient: MockClient((request) async {
          sentToFunction.add(request);
          await release.future;
          return jsonReply({'access_token': 'new', 'refresh_token': 'r2', 'expires_in': 3600});
        }),
      );

      final first = auth.refresh();
      final second = auth.refresh();
      release.complete();
      expect((await first).accessToken, 'new');
      expect((await second).accessToken, 'new');
      expect(sentToFunction, hasLength(1));
    });

    test('a refused refresh token signs the knitter out', () async {
      await store.write(freshTokens());
      final auth = makeAuth(reply: (_) => jsonReply({'error': 'invalid_grant'}, status: 400));

      await expectLater(auth.refresh(), throwsA(isA<SignInExpired>()));
      expect(await store.read(), isNull);
    });

    test('with no tokens at all, asks for sign-in', () async {
      final auth = makeAuth(reply: (_) => fail('nothing to refresh'));
      await expectLater(auth.accessToken(), throwsA(isA<SignInExpired>()));
    });
  });
}

/// Approves on "Ravelry": redirects back with a code and the same state.
String _approveWithCode(Uri page) {
  final state = page.queryParameters['state'];
  return 'purlnote://oauth-callback?code=code-123&state=$state';
}

/// Stands in for a dropped connection.
class SocketLikeException implements Exception {
  const SocketLikeException();
}
