import '../../../core/api/api_client.dart';
import 'moderation_models.dart';

/// The admin moderation queues: flagged verdicts and user reports, plus the two
/// calls that take a row out of them.
///
/// Constructed from the ambient [ApiClient] by the section itself rather than
/// registered app-wide like the domain repositories: only the moderation panel
/// speaks to these endpoints, and a repository injected into every screen that
/// exactly one screen uses is a dependency nobody can trace back.
class AdminModerationRepository {
  AdminModerationRepository(this._api);

  final ApiClient _api;

  static const String _base = '/api/v1/admin/moderation';

  /// One page of recorded verdicts, newest first. A null filter widens the
  /// query — including [state], so a moderator can look back at what was
  /// already decided rather than only at the open backlog.
  Future<({List<ModerationRecord> items, int total})> records({
    ModerationReviewState? state,
    ModerationSurfaceKind? surface,
    ModerationCategoryKind? category,
    String? projectId,
    int page = 0,
    int size = 25,
  }) async => _page(
    await _api.get(
          '$_base/records',
          query: {
            'state': ?state?.wire,
            'surface': ?surface?.filterValue,
            'category': ?category?.filterValue,
            'projectId': ?projectId,
            'page': '$page',
            'size': '$size',
          },
        )
        as Map<String, dynamic>,
    ModerationRecord.fromJson,
  );

  /// Records a human decision on one verdict. [note] is the moderator's own
  /// reasoning and may be empty — it is stored, not shown to the author.
  Future<void> reviewRecord(
    String id, {
    required ModerationReviewState state,
    String? note,
  }) => _api.post(
    '$_base/records/$id/review',
    body: {'state': state.wire, 'note': ?note},
  );

  /// One page of user reports, newest first.
  Future<({List<ContentReport> items, int total})> reports({
    ContentReportState? state,
    int page = 0,
    int size = 25,
  }) async => _page(
    await _api.get(
          '$_base/reports',
          query: {'state': ?state?.wire, 'page': '$page', 'size': '$size'},
        )
        as Map<String, dynamic>,
    ContentReport.fromJson,
  );

  /// The open backlog and what the image tier is actually doing.
  ///
  /// Deliberately not merged into the two page calls: those are paged and
  /// filtered by whatever the moderator is looking at, while this answers a
  /// question about the instance that does not change when they switch tabs.
  Future<ModerationSummary> summary() async => ModerationSummary.fromJson(
    await _api.get('$_base/summary') as Map<String, dynamic>,
  );

  /// Closes a report, either upholding it ([ContentReportState.actioned]) or
  /// rejecting it ([ContentReportState.dismissed]).
  Future<void> handleReport(
    String id, {
    required ContentReportState state,
    String? note,
  }) => _api.post(
    '$_base/reports/$id/handle',
    body: {'state': state.wire, 'note': ?note},
  );
}

/// Reads the `{items, total, page, size}` envelope the admin controllers emit —
/// the same hand-rolled shape as the audit and user boards, not Spring's `Page`
/// serialisation. Only `total` is read beyond the rows: it is what tells the
/// pager whether another page exists, and the page number it would ask for is
/// the one it already knows it sent.
({List<T> items, int total}) _page<T>(
  Map<String, dynamic> json,
  T Function(Map<String, dynamic>) parse,
) {
  final raw = json['items'] as List<dynamic>? ?? const [];
  final items = raw.map((e) => parse(e as Map<String, dynamic>)).toList();
  // Falls back to the row count rather than zero: a missing total would
  // otherwise read as "no more pages" *and* as an empty list to anything that
  // renders a count.
  final total = (json['total'] as num?)?.toInt() ?? items.length;
  return (items: items, total: total);
}
