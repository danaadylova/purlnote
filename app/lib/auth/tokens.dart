import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The access and refresh tokens Ravelry gave us for one knitter.
class Tokens {
  const Tokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  /// Builds tokens from the sign-in function's JSON reply.
  ///
  /// [now] is passed in so tests can control the clock.
  factory Tokens.fromTokenResponse(Map<String, dynamic> json, DateTime now) {
    final accessToken = json['access_token'];
    if (accessToken is! String || accessToken.isEmpty) {
      throw const FormatException('The reply had no access token.');
    }
    // Ravelry's docs say tokens last 24 hours, but in practice they last one
    // hour. Trust the reply, and assume one hour if it doesn't say.
    final lifetimeSeconds = (json['expires_in'] as num?)?.toInt() ?? 3600;
    return Tokens(
      accessToken: accessToken,
      refreshToken: json['refresh_token'] as String?,
      expiresAt: now.add(Duration(seconds: lifetimeSeconds)),
    );
  }

  final String accessToken;

  /// Missing only if Ravelry didn't grant the `offline` scope.
  final String? refreshToken;

  final DateTime expiresAt;

  /// True when the access token has expired or will within [margin].
  bool expiresSoon(DateTime now, {Duration margin = const Duration(minutes: 2)}) {
    return !now.isBefore(expiresAt.subtract(margin));
  }

  /// Keeps the old refresh token if Ravelry didn't send a new one.
  Tokens replacedBy(Tokens newer) {
    return Tokens(
      accessToken: newer.accessToken,
      refreshToken: newer.refreshToken ?? refreshToken,
      expiresAt: newer.expiresAt,
    );
  }
}

/// Where tokens are kept between app launches.
abstract class TokenStore {
  Future<Tokens?> read();
  Future<void> write(Tokens tokens);
  Future<void> clear();
}

/// Keeps tokens in the iOS Keychain (or Android Keystore), never in the
/// database or in logs.
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _accessKey = 'ravelry_access_token';
  static const _refreshKey = 'ravelry_refresh_token';
  static const _expiresKey = 'ravelry_expires_at';

  @override
  Future<Tokens?> read() async {
    final access = await _storage.read(key: _accessKey);
    final expires = await _storage.read(key: _expiresKey);
    if (access == null || expires == null) return null;
    return Tokens(
      accessToken: access,
      refreshToken: await _storage.read(key: _refreshKey),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(int.parse(expires)),
    );
  }

  @override
  Future<void> write(Tokens tokens) async {
    await _storage.write(key: _accessKey, value: tokens.accessToken);
    await _storage.write(
      key: _expiresKey,
      value: tokens.expiresAt.millisecondsSinceEpoch.toString(),
    );
    final refresh = tokens.refreshToken;
    if (refresh == null) {
      await _storage.delete(key: _refreshKey);
    } else {
      await _storage.write(key: _refreshKey, value: refresh);
    }
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
    await _storage.delete(key: _expiresKey);
  }
}

/// Keeps tokens in memory only. Used by tests.
class MemoryTokenStore implements TokenStore {
  Tokens? _tokens;

  @override
  Future<Tokens?> read() async => _tokens;

  @override
  Future<void> write(Tokens tokens) async => _tokens = tokens;

  @override
  Future<void> clear() async => _tokens = null;
}
