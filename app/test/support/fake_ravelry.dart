import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fakes.dart';

/// A small stand-in for Ravelry's API that supports version tags (ETags).
class FakeRavelry {
  final requests = <http.Request>[];

  Map<String, dynamic> user = {'id': 1, 'username': 'unraveled-makes', 'first_name': 'Dana'};
  List<Map<String, dynamic>> projects = [
    {'id': 10, 'name': 'Harbour Raglan', 'status_name': 'In progress', 'progress': 40},
    {'id': 11, 'name': 'Petal Drop Socks', 'status_name': 'Finished', 'progress': 100},
  ];
  List<Map<String, dynamic>> queue = [
    {'id': 20, 'short_pattern_name': 'Fennel Socks', 'position_in_queue': 1},
  ];
  List<Map<String, dynamic>> stash = [
    {'id': 30, 'colorway_name': 'Rios', 'yarn': {'name': 'Rios', 'yarn_company_name': 'Malabrigo'}},
  ];

  /// Stash pages of this size; null means everything on one page.
  int? stashPageSize;

  /// Answers 401 to the next request, as if the token had just expired.
  bool rejectNextToken = false;

  http.Client get client => MockClient((request) async {
        requests.add(request);
        if (rejectNextToken) {
          rejectNextToken = false;
          return http.Response('expired', 401);
        }
        return _answer(request);
      });

  http.Response _answer(http.Request request) {
    final path = request.url.path;
    if (path == '/current_user.json') return _withTag(request, {'user': user});
    if (path == '/projects/unraveled-makes/list.json') return _withTag(request, {'projects': projects});
    if (path == '/people/unraveled-makes/queue/list.json') return _withTag(request, {'queued_projects': queue});
    if (path == '/people/unraveled-makes/stash/list.json') return _stashPage(request);
    return http.Response('not found', 404);
  }

  /// Replies 304 when the request's tag matches the current content.
  http.Response _withTag(http.Request request, Map<String, dynamic> body) {
    final tag = '"${body.toString().hashCode}"';
    if (request.headers['If-None-Match'] == tag) return http.Response('', 304, headers: {'etag': tag});
    return jsonReply(body, headers: {'etag': tag});
  }

  http.Response _stashPage(http.Request request) {
    final size = stashPageSize;
    if (size == null) return _withTag(request, {'stash': stash});
    final page = int.parse(request.url.queryParameters['page']!);
    final pageCount = (stash.length / size).ceil();
    final items = stash.skip((page - 1) * size).take(size).toList();
    return jsonReply({
      'stash': items,
      'paginator': {'page': page, 'page_count': pageCount, 'results': stash.length},
    }, headers: {'etag': '"stash-page-$page"'});
  }

  int countRequestsTo(String path) => requests.where((r) => r.url.path == path).length;
}
