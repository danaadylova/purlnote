import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_service.dart';

/// One reply from Ravelry's API.
class RavelryReply {
  const RavelryReply({required this.body, required this.etag, required this.unchanged});

  /// The decoded JSON. Null when [unchanged] is true.
  final Map<String, dynamic>? body;

  /// Ravelry's version tag for this reply. Sending it back next time lets
  /// Ravelry answer "unchanged" (304) instead of sending everything again.
  final String? etag;

  /// True when Ravelry said nothing changed since [etag].
  final bool unchanged;
}

/// Ravelry could not be reached, for example because the phone is offline.
class RavelryUnreachable implements Exception {
  const RavelryUnreachable();
}

/// Ravelry answered with an error status.
class RavelryError implements Exception {
  const RavelryError(this.statusCode, this.path);
  final int statusCode;
  final String path;

  /// Ravelry is busy or having trouble; trying again later may work.
  bool get isTemporary => statusCode == 429 || statusCode >= 500;

  @override
  String toString() => 'Ravelry answered $statusCode for $path';
}

/// Reads from and writes to Ravelry's API with the knitter's access token.
///
/// Everything except sign-in goes straight from the phone to Ravelry; our
/// sign-in function never sees the knitter's data.
class RavelryClient {
  RavelryClient({
    required this.baseUrl,
    required this.auth,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String baseUrl;
  final AuthService auth;
  final http.Client _http;

  /// GETs [path] (such as "/current_user.json").
  ///
  /// Pass the [etag] from the last reply to get a cheap "unchanged" answer
  /// when nothing changed. If Ravelry rejects the token, it is refreshed once
  /// and the request is retried.
  Future<RavelryReply> get(
    String path, {
    Map<String, String>? query,
    String? etag,
  }) async {
    final url = Uri.parse('$baseUrl$path').replace(queryParameters: query);

    var response = await _send(url, await auth.accessToken(), etag);
    if (response.statusCode == 401) {
      final fresh = await auth.refresh();
      response = await _send(url, fresh.accessToken, etag);
    }

    final newEtag = response.headers['etag'];
    if (response.statusCode == 304) {
      return RavelryReply(body: null, etag: newEtag ?? etag, unchanged: true);
    }
    if (response.statusCode != 200) {
      throw RavelryError(response.statusCode, path);
    }
    return RavelryReply(
      body: jsonDecode(response.body) as Map<String, dynamic>,
      etag: newEtag,
      unchanged: false,
    );
  }

  /// POSTs [body] as JSON to [path] (such as an update to a project) and
  /// returns Ravelry's reply. Like [get], refreshes the token once on 401.
  Future<Map<String, dynamic>> post(String path, Map<String, Object?> body) async {
    final url = Uri.parse('$baseUrl$path');
    final json = jsonEncode(body);

    var response = await _sendPost(url, await auth.accessToken(), json);
    if (response.statusCode == 401) {
      final fresh = await auth.refresh();
      response = await _sendPost(url, fresh.accessToken, json);
    }
    if (response.statusCode != 200) {
      throw RavelryError(response.statusCode, path);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<http.Response> _sendPost(Uri url, String accessToken, String json) async {
    try {
      return await _http.post(
        url,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: json,
      );
    } on Exception {
      throw const RavelryUnreachable();
    }
  }

  Future<http.Response> _send(Uri url, String accessToken, String? etag) async {
    try {
      return await _http.get(url, headers: {
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
        if (etag != null) 'If-None-Match': etag,
      });
    } on Exception {
      throw const RavelryUnreachable();
    }
  }
}
