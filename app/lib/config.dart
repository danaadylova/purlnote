/// Addresses and identifiers the app needs to talk to Ravelry.
///
/// Nothing here is secret. Ravelry's client *secret* lives only in the
/// sign-in function on Cloudflare; the client *ID* is public by design and is
/// passed in at build time:
///
///     flutter run --dart-define=RAVELRY_CLIENT_ID=...
class AppConfig {
  const AppConfig({
    required this.ravelryClientId,
    this.signInFunctionUrl = 'https://purlnote-auth.danaadylova.workers.dev',
    this.ravelryAuthorizeUrl = 'https://www.ravelry.com/oauth2/auth',
    this.ravelryApiUrl = 'https://api.ravelry.com',
    this.redirectUri = 'purlnote://oauth-callback',
  });

  /// Reads the client ID given to `flutter build` with `--dart-define`.
  factory AppConfig.fromEnvironment() {
    return const AppConfig(
      ravelryClientId: String.fromEnvironment('RAVELRY_CLIENT_ID'),
    );
  }

  final String ravelryClientId;

  /// The Cloudflare function that swaps sign-in codes for tokens.
  final String signInFunctionUrl;

  /// Ravelry's own page where the knitter approves Purlnote.
  final String ravelryAuthorizeUrl;

  final String ravelryApiUrl;

  /// Where Ravelry sends the knitter back after approving. Must match the
  /// redirect registered on the Ravelry app exactly.
  final String redirectUri;

  /// The URL scheme part of [redirectUri], without "://".
  String get redirectScheme => Uri.parse(redirectUri).scheme;

  bool get isComplete => ravelryClientId.isNotEmpty;
}
