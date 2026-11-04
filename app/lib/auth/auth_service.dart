import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import 'tokens.dart';

/// Opens Ravelry's sign-in page and returns the URL Ravelry redirected back
/// to. Swapped out in tests.
typedef OpenSignInPage = Future<String> Function(Uri page, String callbackScheme);

/// The knitter closed the sign-in sheet without approving.
class SignInCancelled implements Exception {
  const SignInCancelled();
}

/// Sign-in or token refresh failed. [message] is safe to show on screen.
class SignInFailed implements Exception {
  const SignInFailed(this.message);
  final String message;

  @override
  String toString() => 'SignInFailed: $message';
}

/// Ravelry no longer accepts our refresh token (the knitter removed access,
/// or it expired). The only fix is to sign in again.
class SignInExpired implements Exception {
  const SignInExpired();
}

/// Signs the knitter in with Ravelry and keeps a valid access token on hand.
///
/// Sign-in steps:
/// 1. Open Ravelry's approval page in the system's secure browser sheet.
/// 2. Ravelry redirects to purlnote://oauth-callback with a one-time code.
/// 3. Send the code to our sign-in function, which adds the client secret and
///    gets the tokens from Ravelry.
/// 4. Store the tokens in the Keychain.
class AuthService {
  AuthService({
    required this.config,
    required this.tokenStore,
    http.Client? httpClient,
    OpenSignInPage? openSignInPage,
    DateTime Function()? clock,
    Random? random,
  })  : _http = httpClient ?? http.Client(),
        _openSignInPage = openSignInPage ?? _openWithSystemBrowser,
        _now = clock ?? DateTime.now,
        _random = random ?? Random.secure();

  final AppConfig config;
  final TokenStore tokenStore;
  final http.Client _http;
  final OpenSignInPage _openSignInPage;
  final DateTime Function() _now;
  final Random _random;

  /// While a refresh is running, everyone who needs a token waits for it
  /// instead of starting their own.
  Future<Tokens>? _refreshInProgress;

  /// Only `offline` at sign-in, so the knitter stays signed in. PDF downloads
  /// and posting comments ask for their own permission when first used.
  static const signInScopes = ['offline'];

  Future<bool> isSignedIn() async => await tokenStore.read() != null;

  /// Runs the whole sign-in. Throws [SignInCancelled] or [SignInFailed].
  Future<void> signIn() async {
    if (!config.isComplete) {
      throw const SignInFailed('This build is missing its Ravelry client ID.');
    }

    final state = _randomState();
    final approvalPage = Uri.parse(config.ravelryAuthorizeUrl).replace(
      queryParameters: {
        'response_type': 'code',
        'client_id': config.ravelryClientId,
        'redirect_uri': config.redirectUri,
        'scope': signInScopes.join(' '),
        'state': state,
      },
    );

    final callback = Uri.parse(
      await _openSignInPage(approvalPage, config.redirectScheme),
    );

    final error = callback.queryParameters['error'];
    if (error == 'access_denied') throw const SignInCancelled();
    if (error != null) throw SignInFailed('Ravelry said: $error');

    // The state must come back unchanged, or this redirect wasn't ours.
    if (callback.queryParameters['state'] != state) {
      throw const SignInFailed('The sign-in reply did not match. Please try again.');
    }
    final code = callback.queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw const SignInFailed('Ravelry did not send a sign-in code.');
    }

    final Tokens tokens;
    try {
      tokens = await _requestTokens({
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': config.redirectUri,
      });
    } on _RejectedByRavelry {
      throw const SignInFailed('The sign-in took too long. Please try again.');
    }
    await tokenStore.write(tokens);
  }

  /// Returns an access token that is good for at least two more minutes,
  /// refreshing it first if needed. Throws [SignInExpired] if the knitter
  /// must sign in again.
  Future<String> accessToken() async {
    final tokens = await tokenStore.read();
    if (tokens == null) throw const SignInExpired();
    if (!tokens.expiresSoon(_now())) return tokens.accessToken;
    return (await refresh()).accessToken;
  }

  /// Gets a fresh access token now, for example after Ravelry answered 401.
  Future<Tokens> refresh() {
    return _refreshInProgress ??= _refresh().whenComplete(() {
      _refreshInProgress = null;
    });
  }

  Future<Tokens> _refresh() async {
    final current = await tokenStore.read();
    final refreshToken = current?.refreshToken;
    if (current == null || refreshToken == null) throw const SignInExpired();

    final Tokens fresh;
    try {
      fresh = await _requestTokens({
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
      });
    } on _RejectedByRavelry {
      await tokenStore.clear();
      throw const SignInExpired();
    }
    final updated = current.replacedBy(fresh);
    await tokenStore.write(updated);
    return updated;
  }

  /// Forgets the tokens on this phone.
  Future<void> signOut() => tokenStore.clear();

  Future<Tokens> _requestTokens(Map<String, String> form) async {
    final http.Response response;
    try {
      response = await _http.post(
        Uri.parse('${config.signInFunctionUrl}/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: form,
      );
    } on Exception {
      throw const SignInFailed('Could not reach Ravelry. Check your connection and try again.');
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } on Object {
      throw SignInFailed('Unexpected reply from the sign-in service (${response.statusCode}).');
    }

    if (response.statusCode == 200) return Tokens.fromTokenResponse(body, _now());

    // invalid_grant means the code or refresh token is no longer accepted.
    if (body['error'] == 'invalid_grant') throw const _RejectedByRavelry();
    final description = body['error_description'] ?? body['error'] ?? 'unknown error';
    throw SignInFailed('Sign-in did not work: $description');
  }

  String _randomState() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static Future<String> _openWithSystemBrowser(Uri page, String scheme) async {
    try {
      return await FlutterWebAuth2.authenticate(
        url: page.toString(),
        callbackUrlScheme: scheme,
      );
    } on PlatformException catch (error) {
      if (error.code == 'CANCELED') throw const SignInCancelled();
      rethrow;
    }
  }
}

/// Ravelry refused a code or refresh token (`invalid_grant`).
class _RejectedByRavelry implements Exception {
  const _RejectedByRavelry();
}
