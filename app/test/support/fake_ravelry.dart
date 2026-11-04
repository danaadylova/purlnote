import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fakes.dart';

/// A small stand-in for Ravelry's API: lists with version tags (ETags),
/// project and stash pages, and updates to them.
class FakeRavelry {
  final requests = <http.Request>[];

  Map<String, dynamic> user = {'id': 1, 'username': 'unraveled-makes', 'first_name': 'Dana'};

  /// Full project records. The project list leaves out notes and size, like
  /// the real one.
  List<Map<String, dynamic>> projects = [
    {
      'id': 10,
      'name': 'Harbour Raglan',
      'project_status_id': 1,
      'status_name': 'In progress',
      'progress': 40,
      'size': 'M',
      'notes': 'Cast on with 4mm.',
    },
    {'id': 11, 'name': 'Petal Drop Socks', 'project_status_id': 2, 'status_name': 'Finished', 'progress': 100},
  ];
  List<Map<String, dynamic>> queue = [
    {'id': 20, 'short_pattern_name': 'Fennel Socks', 'position_in_queue': 1},
  ];
  List<Map<String, dynamic>> stash = [
    {
      'id': 30,
      'colorway_name': 'Rios',
      'location': 'Blue bin',
      'stash_status': {'id': 1, 'name': 'In stash'},
      'yarn': {'name': 'Rios', 'yarn_company_name': 'Malabrigo'},
    },
  ];
  List<Map<String, dynamic>> library = [
    {'id': 70, 'title': 'Harbour Raglan', 'author_name': 'A. Designer', 'pattern_id': 500, 'has_downloads': true},
  ];
  List<Map<String, dynamic>> projectStatuses = [
    {'id': 1, 'name': 'In progress'},
    {'id': 2, 'name': 'Finished'},
    {'id': 3, 'name': 'Hibernating'},
  ];

  /// Stash pages of this size; null means everything on one page.
  int? stashPageSize;

  /// Answers 401 to the next request, as if the token had just expired.
  bool rejectNextToken = false;

  /// Answers every update with this status instead of saving it.
  int? updateStatus;

  /// Comments on projects, by project ID. Ravelry returns bodies as HTML.
  final Map<int, List<Map<String, dynamic>>> comments = {};
  int _nextCommentId = 5000;

  /// Answers comment posts with this status instead of posting.
  int? commentStatus;

  /// Posts the comment but drops the connection before replying, as if the
  /// phone went offline mid-send.
  bool dropConnectionAfterNextComment = false;

  /// The knitter's app data store.
  final Map<String, String> appData = {};

  http.Client get client => MockClient((request) async {
        requests.add(request);
        if (rejectNextToken) {
          rejectNextToken = false;
          return http.Response('expired', 401);
        }
        return _answer(request);
      });

  /// The JSON bodies of every project or stash update sent, in order.
  List<Map<String, dynamic>> get updatesSent => [
        for (final request in requests)
          if (request.method == 'POST' && request.headers['Content-Type'] == 'application/json')
            jsonDecode(request.body) as Map<String, dynamic>,
      ];

  /// How many comments were posted (not counting refused ones).
  int get commentsPosted => comments.values.fold(0, (sum, list) => sum + list.length);

  http.Response _answer(http.Request request) {
    final path = request.url.path;
    if (path == '/current_user.json') return _withTag(request, {'user': user});
    if (path == '/projects/unraveled-makes/list.json') {
      return _withTag(request, {'projects': projects.map(_asListItem).toList()});
    }
    if (path == '/people/unraveled-makes/queue/list.json') return _withTag(request, {'queued_projects': queue});
    if (path == '/people/unraveled-makes/stash/list.json') return _stashPage(request);
    if (path == '/projects/project_statuses.json') return _withTag(request, {'project_statuses': projectStatuses});
    if (path == '/people/unraveled-makes/library/search.json') return _withTag(request, {'volumes': library});

    if (path == '/comments/create.json') return _createComment(request);
    final deleteComment = RegExp(r'^/comments/(\d+)\.json$').firstMatch(path);
    if (deleteComment != null && request.method == 'DELETE') {
      final id = int.parse(deleteComment.group(1)!);
      for (final list in comments.values) {
        list.removeWhere((c) => c['id'] == id);
      }
      return jsonReply({'comment': {'id': id}});
    }
    if (path == '/app/data/set.json') {
      appData.addAll(Uri.splitQueryString(request.body));
      return jsonReply({'data': Uri.splitQueryString(request.body)});
    }
    if (path == '/app/data/get.json') {
      final keys = request.url.queryParameters['keys']!.split(' ');
      return jsonReply({
        'data': {for (final key in keys) if (appData.containsKey(key)) key: appData[key]},
      });
    }
    if (path == '/app/data/delete.json') {
      final keys = Uri.splitQueryString(request.body)['keys']!.split(' ');
      keys.forEach(appData.remove);
      return jsonReply({'data': {}});
    }

    final project = RegExp(r'^/projects/unraveled-makes/(\d+)\.json$').firstMatch(path);
    if (project != null) return _recordPage(request, projects, int.parse(project.group(1)!), 'project');
    final yarn = RegExp(r'^/people/unraveled-makes/stash/(\d+)\.json$').firstMatch(path);
    if (yarn != null) return _recordPage(request, stash, int.parse(yarn.group(1)!), 'stash');

    return http.Response('not found', 404);
  }

  /// GET shows the record; POST updates it with the JSON body.
  http.Response _recordPage(http.Request request, List<Map<String, dynamic>> records, int id, String key) {
    final record = records.where((r) => r['id'] == id).firstOrNull;
    if (record == null) return http.Response('not found', 404);
    if (request.method == 'POST') {
      final status = updateStatus;
      if (status != null) return http.Response('refused', status);
      record.addAll(jsonDecode(request.body) as Map<String, dynamic>);
      final statusId = record['project_status_id'];
      final statusName = projectStatuses.where((s) => s['id'] == statusId).firstOrNull?['name'];
      if (key == 'project' && statusName != null) record['status_name'] = statusName;
    }
    if (request.url.queryParameters['include'] == 'comments') {
      return jsonReply({key: record, 'comments': comments[id] ?? []});
    }
    return jsonReply({key: record});
  }

  http.Response _createComment(http.Request request) {
    final status = commentStatus;
    if (status != null) return http.Response('refused', status);
    final fields = Uri.splitQueryString(request.body);
    final comment = {
      'id': _nextCommentId++,
      'body': '<p>${fields['body']}</p>',
      'user': {'username': 'unraveled-makes'},
    };
    comments.putIfAbsent(int.parse(fields['commented_id']!), () => []).add(comment);
    if (dropConnectionAfterNextComment) {
      dropConnectionAfterNextComment = false;
      throw http.ClientException('connection dropped');
    }
    return jsonReply({'comment': comment});
  }

  /// Change a project as if someone edited it on the Ravelry website.
  void editProjectOnWebsite(int id, Map<String, dynamic> fields) {
    projects.firstWhere((p) => p['id'] == id).addAll(fields);
  }

  Map<String, dynamic> _asListItem(Map<String, dynamic> project) {
    return {...project}
      ..remove('notes')
      ..remove('size');
  }

  /// Replies 304 when the request's tag matches the current content.
  http.Response _withTag(http.Request request, Map<String, dynamic> body) {
    final tag = '"${jsonEncode(body).hashCode}"';
    if (request.headers['If-None-Match'] == tag) return http.Response('', 304, headers: {'etag': tag});
    return jsonReply(body, headers: {'etag': tag});
  }

  http.Response _stashPage(http.Request request) {
    final size = stashPageSize;
    if (size == null) return _withTag(request, {'stash': stash});
    final page = int.parse(request.url.queryParameters['page']!);
    final pageCount = (stash.length / size).ceil();
    final items = stash.skip((page - 1) * size).take(size).toList();
    return jsonReply(
      {
        'stash': items,
        'paginator': {'page': page, 'page_count': pageCount, 'results': stash.length},
      },
      headers: {'etag': '"stash-page-$page"'},
    );
  }

  int countRequestsTo(String path) => requests.where((r) => r.url.path == path).length;
}
