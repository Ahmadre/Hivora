import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/features/admin/moderation/moderation_models.dart';
import 'package:hinata/features/admin/moderation/moderation_repository.dart';

/// Pins the admin queue to `AdminModerationController`: its paths, its filter
/// names, and the `{items, total, page, size}` envelope it answers with — the
/// hand-rolled one the audit and user boards use, not Spring's `Page`.
///
/// The row fields are checked through the enums, because those are where the two
/// sides can drift silently: the server serialises a Java constant, the app
/// derives the same constant from a Dart name, and a mismatch shows up as a row
/// that renders "unknown" rather than as an error anybody notices.
void main() {
  late _RecordingApi api;
  late AdminModerationRepository repository;

  setUp(() {
    api = _RecordingApi();
    repository = AdminModerationRepository(api);
  });

  Map<String, dynamic> recordRow() => {
    'id': 'r1',
    'createdAt': '2026-08-05T09:00:00Z',
    'surface': 'ORGANISATION_LOGO',
    'category': 'SELF_HARM',
    'decision': 'FLAG',
    'tier': 'LOCAL_MODEL',
    'score': 72,
    'degraded': true,
    'reviewState': 'OPEN',
    'targetType': 'issue',
    'targetId': 'i1',
    'label': 'HIN-12',
    'link': '/issues/HIN-12',
  };

  group('records', () {
    test('asks the admin queue with the filters it was given', () async {
      api.response = {'items': [recordRow()], 'total': 41, 'page': 2, 'size': 25};

      final page = await repository.records(
        state: ModerationReviewState.open,
        surface: ModerationSurfaceKind.comment,
        category: ModerationCategoryKind.hate,
        projectId: 'p1',
        page: 2,
      );

      final call = api.calls.single;
      expect(call.path, '/api/v1/admin/moderation/records');
      expect(call.query, {
        'state': 'OPEN',
        'surface': 'COMMENT',
        'category': 'HATE',
        'projectId': 'p1',
        'page': '2',
        'size': '25',
      });
      expect(page.total, 41);
      expect(page.items.single.id, 'r1');
    });

    test('omits a filter that was not set instead of widening it to a word', () async {
      api.response = {'items': const [], 'total': 0};

      await repository.records();

      // A `state=null` or `state=` would be a filter value the server has to
      // interpret; leaving the key out is what actually means "any".
      expect(api.calls.single.query, {'page': '0', 'size': '25'});
    });

    test('reads every enum the queue row is described with', () async {
      api.response = {'items': [recordRow()], 'total': 1};

      final row = (await repository.records()).items.single;

      expect(row.surface, ModerationSurfaceKind.organisationLogo);
      expect(row.category, ModerationCategoryKind.selfHarm);
      expect(row.decision, ModerationDecisionKind.flag);
      expect(row.tier, ModerationTier.localModel);
      expect(row.reviewState, ModerationReviewState.open);
      expect(row.degraded, isTrue);
      expect(row.route, '/issues/HIN-12');
    });

    test('falls back to the row count when the envelope carries no total', () async {
      api.response = {
        'items': [recordRow(), recordRow()],
      };

      // Zero would read as "no more pages" and as an empty queue to anything
      // rendering a count, for rows that are demonstrably there.
      expect((await repository.records()).total, 2);
    });
  });

  group('decisions', () {
    test('reviews a verdict on the record it names', () async {
      await repository.reviewRecord(
        'r1',
        state: ModerationReviewState.confirmed,
        note: 'agreed',
      );

      final call = api.calls.single;
      expect(call.path, '/api/v1/admin/moderation/records/r1/review');
      expect(call.body, {'state': 'CONFIRMED', 'note': 'agreed'});
    });

    test('handles a report, and drops an absent note rather than sending null',
        () async {
      await repository.handleReport('c1', state: ContentReportState.actioned);

      final call = api.calls.single;
      expect(call.path, '/api/v1/admin/moderation/reports/c1/handle');
      expect(call.body, {'state': 'ACTIONED'});
    });
  });

  group('reports', () {
    test('reads the report queue in the same envelope', () async {
      api.response = {
        'items': [
          {
            'id': 'c1',
            'createdAt': '2026-08-05T09:00:00Z',
            'state': 'OPEN',
            'category': 'HARASSMENT',
            'surface': 'COMMENT',
            'reporterName': 'Ada',
            'targetType': 'comment',
            'targetId': 'x1',
            'link': '/issues/HIN-3?comment=x1',
          },
        ],
        'total': 1,
      };

      final page = await repository.reports(state: ContentReportState.open);

      expect(api.calls.single.path, '/api/v1/admin/moderation/reports');
      expect(api.calls.single.query, {
        'state': 'OPEN',
        'page': '0',
        'size': '25',
      });
      final row = page.items.single;
      expect(row.state, ContentReportState.open);
      expect(row.category, ModerationCategoryKind.harassment);
      // A comment is only reachable through the issue that owns it, so the
      // server's own link is the route — never one derived from the id.
      expect(row.route, '/issues/HIN-3?comment=x1');
    });
  });
}

typedef _Call = ({
  String path,
  Object? body,
  Map<String, dynamic>? query,
});

/// An [ApiClient] that records instead of sending; `noSuchMethod` covers the
/// rest of a client this repository never touches.
class _RecordingApi implements ApiClient {
  final List<_Call> calls = [];

  Object? response;

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    calls.add((path: path, body: null, query: query));
    return response;
  }

  @override
  Future<dynamic> post(String path, {Object? body}) async {
    calls.add((path: path, body: body, query: null));
    return response;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
