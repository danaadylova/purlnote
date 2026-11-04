import 'dart:convert';
import 'dart:typed_data';

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
  Future<Map<String, dynamic>> post(String path, Map<String, Object?> body) {
    return _write('POST', path, body: jsonEncode(body), contentType: 'application/json');
  }

  /// POSTs [fields] as a form, which some calls (such as creating a comment)
  /// expect instead of JSON.
  Future<Map<String, dynamic>> postForm(String path, Map<String, String> fields) {
    return _write(
      'POST',
      path,
      body: Uri(queryParameters: fields).query,
      contentType: 'application/x-www-form-urlencoded',
    );
  }

  /// Uploads an image and returns Ravelry's image ID, for attaching it to a
  /// project. Ravelry's upload takes a one-time upload token instead of the
  /// knitter's access token.
  Future<int> uploadImage(Uint8List bytes, String fileName) async {
    final token = (await post('/upload/request_token.json', const {}))['upload_token'] as String?;
    if (token == null) throw const RavelryError(500, '/upload/request_token.json');

    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/upload/image.json'))
      ..fields['upload_token'] = token
      ..files.add(http.MultipartFile.fromBytes('file0', bytes, filename: fileName));
    final http.Response response;
    try {
      response = await http.Response.fromStream(await _http.send(request));
    } on Exception {
      throw const RavelryUnreachable();
    }
    if (response.statusCode != 200) throw RavelryError(response.statusCode, '/upload/image.json');

    // The reply is {"uploads": {"file0": {"image_id": 16}}}, sometimes with
    // "uploads" as a list of such objects.
    final uploads = (jsonDecode(response.body) as Map<String, dynamic>)['uploads'];
    final entries = uploads is List ? uploads.cast<Map<String, dynamic>>() : [uploads as Map<String, dynamic>];
    for (final entry in entries) {
      final file = entry['file0'] as Map<String, dynamic>?;
      final id = (file?['image_id'] as num?)?.toInt();
      if (id != null) return id;
    }
    throw const RavelryError(500, '/upload/image.json');
  }

  /// DELETEs [path], such as one of the knitter's comments.
  Future<Map<String, dynamic>> delete(String path) => _write('DELETE', path);

  Future<Map<String, dynamic>> _write(String method, String path, {String? body, String? contentType}) async {
    final url = Uri.parse('$baseUrl$path');

    Future<http.Response> send(String accessToken) async {
      final request = http.Request(method, url)
        ..headers['Authorization'] = 'Bearer $accessToken'
        ..headers['Accept'] = 'application/json';
      if (contentType != null) request.headers['Content-Type'] = contentType;
      if (body != null) request.body = body;
      try {
        return await http.Response.fromStream(await _http.send(request));
      } on Exception {
        throw const RavelryUnreachable();
      }
    }

    var response = await send(await auth.accessToken());
    if (response.statusCode == 401) {
      response = await send((await auth.refresh()).accessToken);
    }
    if (response.statusCode != 200) {
      throw RavelryError(response.statusCode, path);
    }
    return response.body.isEmpty ? const {} : jsonDecode(response.body) as Map<String, dynamic>;
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
