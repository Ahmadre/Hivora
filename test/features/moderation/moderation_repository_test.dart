import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/moderation_models.dart';
import 'package:hinata/core/repositories/moderation_repository.dart';

/// Pins the four calls this repository makes to the paths and payloads the
/// server actually serves.
///
/// Nothing else can catch a mistake here: a wrong path is a 404 at runtime on a
/// screen most users only reach once, and a wrong field name is a 400 that the
/// report modal renders as a generic error. The endpoints are
/// `ContentReportController`'s — `/reports/content` (not `/reports`, which the
/// analytics controller owns) and `/me/blocks`, because a block is part of the
/// blocker's own account rather than a thing done to the blocked user.
void main() {
  late _RecordingApi api;
  late ModerationRepository repository;

  setUp(() {
    api = _RecordingApi();
    repository = ModerationRepository(api);
  });

  group('report', () {
    test('posts the content report in the server vocabulary', () async {
      await repository.report(
        ReportTarget.comment(commentId: 'c1', issueId: 'i1'),
        reason: ReportReason.harassment,
        note: '  he keeps doing this  ',
      );

      final call = api.calls.single;
      expect(call.method, 'POST');
      expect(call.path, '/api/v1/reports/content');
      expect(call.body, {
        'targetType': 'COMMENT',
        'targetId': 'c1',
        'contextId': 'i1',
        'reason': 'HARASSMENT',
        'note': 'he keeps doing this',
      });
    });

    test('omits an empty note rather than sending whitespace', () async {
      await repository.report(
        const ReportTarget(type: ReportTargetType.user, id: 'u1'),
        reason: ReportReason.other,
        note: '   ',
      );

      expect(api.calls.single.body, {
        'targetType': 'USER',
        'targetId': 'u1',
        'reason': 'OTHER',
      });
    });
  });

  group('blocks', () {
    test('blocks through the account path with the id in the URL', () async {
      await repository.blockUser('u7');

      final call = api.calls.single;
      expect(call.method, 'POST');
      expect(call.path, '/api/v1/me/blocks/u7');
      // No body: the path already names the account, and a second copy of the
      // id could only ever disagree with it.
      expect(call.body, isNull);
    });

    test('unblocks the same resource it blocked', () async {
      await repository.unblockUser('u7');

      expect(api.calls.single.method, 'DELETE');
      expect(api.calls.single.path, '/api/v1/me/blocks/u7');
    });

    test('reads the block list as the flat list the server returns', () async {
      api.response = [
        {
          'userId': 'u1',
          'displayName': 'Ada Lovelace',
          'username': 'ada',
          'blockedAt': '2026-08-05T10:00:00Z',
        },
        {'userId': 'u2', 'displayName': 'Bob Bauer', 'username': 'bob'},
      ];

      final blocked = await repository.blockedUsers();

      final call = api.calls.single;
      expect(call.method, 'GET');
      expect(call.path, '/api/v1/me/blocks');
      // No page/size: there is no paged endpoint behind this, and asking for one
      // would send query parameters the server silently ignores while the app
      // believed it was paging.
      expect(call.query, isNull);
      expect(blocked.map((u) => u.userId), ['u1', 'u2']);
      expect(blocked.first.blockedAt, isNotNull);
    });

    test('treats an empty list as an empty block list', () async {
      api.response = const <dynamic>[];

      expect(await repository.blockedUsers(), isEmpty);
    });
  });
}

/// One HTTP call the repository made.
typedef _Call = ({
  String method,
  String path,
  Object? body,
  Map<String, dynamic>? query,
});

/// An [ApiClient] that records instead of sending.
///
/// `noSuchMethod` covers everything the repository never touches, so this fake
/// does not have to be kept in step with a client that carries token refresh,
/// uploads and an SSE transport.
class _RecordingApi implements ApiClient {
  final List<_Call> calls = [];

  /// What the next `get` resolves with.
  Object? response;

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    calls.add((method: 'GET', path: path, body: null, query: query));
    return response;
  }

  @override
  Future<dynamic> post(String path, {Object? body}) async {
    calls.add((method: 'POST', path: path, body: body, query: null));
    return response;
  }

  @override
  Future<dynamic> delete(String path, {Object? body}) async {
    calls.add((method: 'DELETE', path: path, body: body, query: null));
    return response;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
