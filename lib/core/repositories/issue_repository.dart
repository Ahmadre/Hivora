import 'package:dio/dio.dart';

import '../api/api_client.dart';
import '../models/issue_detail.dart';
import '../models/issue_move.dart';
import '../models/work_models.dart';

/// Issues: search/CRUD, hierarchy, relationship links, change history,
/// attachments, and time-tracking work items.
class IssueRepository {
  IssueRepository(this._api);

  final ApiClient _api;

  /// The configured backend base URL — used to derive shareable web links to
  /// issues (copy-link, smart links).
  String get apiBaseUrl => _api.baseUrl;

  Future<({List<Issue> issues, int total})> issues({
    String? projectId,
    String? state,
    String? assigneeId,
    String? sprintId,
    String? type,
    String? query,
    bool noSprint = false,
    bool archived = false,
    String? sort,
    int page = 0,
    int size = 50,
    // Repeatable server-side facets: let the backend return an already
    // reduced page so the client no longer has to drain every page and filter in
    // memory. Empty/null means "no restriction" for that facet.
    List<String>? states,
    List<String>? assigneeIds,
    List<String>? types,
    List<String>? priorities,
    DateTime? createdFrom,
    DateTime? createdTo,
    DateTime? dueFrom,
    DateTime? dueTo,
  }) async {
    String? day(DateTime? d) => d?.toIso8601String().substring(0, 10);
    final data =
        await _api.get(
              '/api/v1/issues',
              query: {
                'projectId': ?projectId,
                'state': ?state,
                if (states != null && states.isNotEmpty) 'states': states,
                'assigneeId': ?assigneeId,
                if (assigneeIds != null && assigneeIds.isNotEmpty)
                  'assigneeIds': assigneeIds,
                'sprintId': ?sprintId,
                'type': ?type,
                if (types != null && types.isNotEmpty) 'types': types,
                if (priorities != null && priorities.isNotEmpty)
                  'priorities': priorities,
                'createdFrom': ?day(createdFrom),
                'createdTo': ?day(createdTo),
                'dueFrom': ?day(dueFrom),
                'dueTo': ?day(dueTo),
                if (noSprint) 'noSprint': true,
                if (archived) 'archived': true,
                'sort': ?sort,
                if (query != null && query.isNotEmpty) 'query': query,
                'page': page,
                'size': size,
              },
            )
            as Map<String, dynamic>;
    return (
      issues: ((data['content'] as List<dynamic>?) ?? [])
          .map((i) => Issue.fromJson(i as Map<String, dynamic>))
          .toList(),
      total: data['totalElements'] as int? ?? 0,
    );
  }

  /// Fetches **every** matching issue by paging through the server-clamped
  /// result set (the search endpoint caps `size` at 100), so callers that need
  /// the complete collection — exports, board swimlane indexes, smart-link
  /// `@`-menus — never silently miss issues beyond the first page.
  ///
  /// Pages are de-duplicated by id: a row can shift across a page boundary
  /// while we page (the backend sort is time-based), so dedup keeps the result
  /// clean regardless of [sort]. Stops at the last partial page or once the
  /// accumulated count reaches the backend total.
  Future<List<Issue>> allIssues({
    String? projectId,
    String? state,
    String? assigneeId,
    String? sprintId,
    String? query,
    bool noSprint = false,
    bool archived = false,
    String? sort,
    List<String>? states,
    List<String>? assigneeIds,
    List<String>? types,
    List<String>? priorities,
    DateTime? createdFrom,
    DateTime? createdTo,
    DateTime? dueFrom,
    DateTime? dueTo,
  }) async {
    const size = 100;
    final out = <Issue>[];
    final seen = <String>{};
    var page = 0;
    while (true) {
      final result = await issues(
        projectId: projectId,
        state: state,
        assigneeId: assigneeId,
        sprintId: sprintId,
        query: query,
        noSprint: noSprint,
        archived: archived,
        sort: sort,
        states: states,
        assigneeIds: assigneeIds,
        types: types,
        priorities: priorities,
        createdFrom: createdFrom,
        createdTo: createdTo,
        dueFrom: dueFrom,
        dueTo: dueTo,
        page: page,
        size: size,
      );
      for (final issue in result.issues) {
        if (seen.add(issue.id)) out.add(issue);
      }
      if (result.issues.length < size || out.length >= result.total) break;
      page++;
    }
    return out;
  }

  /// Lightweight type-ahead for the comment @-mention menu: a small,
  /// server-capped list of `{id, readableId, title}` for [query] within
  /// [projectId], instead of draining the whole project issue set client-side.
  Future<List<IssueRef>> mentionSearch({
    String? projectId,
    required String query,
  }) async =>
      ((await _api.get(
                '/api/v1/issues/mention-search',
                query: {
                  'projectId': ?projectId,
                  if (query.isNotEmpty) 'q': query,
                },
              ))
              as List<dynamic>)
          .map((r) => IssueRef.fromJson(r as Map<String, dynamic>))
          .toList();

  /// Batch-resolves readable ids (e.g. `HIN-1,HIN-2`) to the full issues needed
  /// to render `{{issue:KEY}}` chips + hover cards (state, assignee, priority,
  /// labels) — ACL-scoped and capped server-side, so only the keys actually
  /// referenced are fetched instead of draining the whole project.
  Future<List<Issue>> resolveIssues(List<String> keys) async {
    if (keys.isEmpty) return const [];
    return ((await _api.get('/api/v1/issues/resolve', query: {'keys': keys}))
            as List<dynamic>)
        .map((i) => Issue.fromJson(i as Map<String, dynamic>))
        .toList();
  }

  Future<Issue> issue(String id) async => Issue.fromJson(
    await _api.get('/api/v1/issues/$id') as Map<String, dynamic>,
  );

  /// First-paint bootstrap for the issue-detail view: the issue plus page 0 of
  /// comments/activity, pinned comments, work items, project, hierarchy,
  /// sprints, referenced users and the delete capability — in ONE request
  /// instead of ~13. See [IssueDetail]. Load-more still uses the paged calls.
  Future<IssueDetail> issueDetail(
    String id, {
    int commentSize = 30,
    String commentSort = 'newest',
    int activitySize = 30,
  }) async => IssueDetail.fromJson(
    await _api.get(
          '/api/v1/issues/$id/detail',
          query: {
            'commentSize': commentSize,
            'commentSort': commentSort,
            'activitySize': activitySize,
          },
        )
        as Map<String, dynamic>,
  );

  /// Breadcrumb ancestors + direct children for the issue hierarchy view.
  Future<IssueHierarchy> issueHierarchy(String id) async =>
      IssueHierarchy.fromJson(
        await _api.get('/api/v1/issues/$id/hierarchy') as Map<String, dynamic>,
      );

  Future<Issue> createIssue(Map<String, dynamic> body) async => Issue.fromJson(
    await _api.post('/api/v1/issues', body: body) as Map<String, dynamic>,
  );

  Future<Issue> updateIssue(String id, Map<String, dynamic> patch) async =>
      Issue.fromJson(
        await _api.patch('/api/v1/issues/$id', body: patch)
            as Map<String, dynamic>,
      );

  Future<void> deleteIssue(String id) => _api.delete('/api/v1/issues/$id');

  /// Creates a copy of [id] in the same project and returns it.
  ///
  /// Only the four things the clone dialog collects are sent; what the copy
  /// inherits from the original — and what it deliberately does not — is the
  /// server's decision, so this stays a thin call rather than a second place
  /// where "what a clone is" is written down.
  Future<Issue> cloneIssue(
    String id, {
    required String title,
    required List<String> assigneeIds,
    required bool includeLinks,
    required bool includeSprint,
  }) async => Issue.fromJson(
    await _api.post(
          '/api/v1/issues/$id/clone',
          body: {
            'title': title,
            'assigneeIds': assigneeIds,
            'includeLinks': includeLinks,
            'includeSprint': includeSprint,
          },
        )
        as Map<String, dynamic>,
  );

  /// Asks what moving [issueIds] into [targetProjectId] would do — which issues
  /// travel (sub-tasks always come along), how each source status maps onto the
  /// target workflow, and what detaches. Writes nothing.
  Future<MovePreflight> movePreflight(
    List<String> issueIds,
    String targetProjectId, {
    bool includeEpicChildren = false,
  }) async => MovePreflight.fromJson(
    await _api.post(
          '/api/v1/issues/move/preflight',
          body: {
            'issueIds': issueIds,
            'targetProjectId': targetProjectId,
            'includeEpicChildren': includeEpicChildren,
          },
        )
        as Map<String, dynamic>,
  );

  /// Executes the move confirmed in the wizard. [stateMap] maps each source
  /// status onto a status of the target workflow.
  Future<List<Issue>> moveIssues(
    List<String> issueIds,
    String targetProjectId, {
    required Map<String, String> stateMap,
    bool includeEpicChildren = false,
    bool keepSprint = true,
  }) async =>
      ((await _api.post(
                '/api/v1/issues/move',
                body: {
                  'issueIds': issueIds,
                  'targetProjectId': targetProjectId,
                  'stateMap': stateMap,
                  'includeEpicChildren': includeEpicChildren,
                  'keepSprint': keepSprint,
                },
              ))
              as List<dynamic>)
          .map((i) => Issue.fromJson(i as Map<String, dynamic>))
          .toList();

  /// Soft delete — any project member may archive; the issue disappears from
  /// all default listings but stays restorable.
  Future<Issue> archiveIssue(String id) async => Issue.fromJson(
    await _api.post('/api/v1/issues/$id/archive') as Map<String, dynamic>,
  );

  /// Restores an archived issue (and its archived sub-tasks).
  Future<Issue> unarchiveIssue(String id) async => Issue.fromJson(
    await _api.post('/api/v1/issues/$id/unarchive') as Map<String, dynamic>,
  );

  /// Sends a reply by e-mail to the original sender of an email-to-ticket issue.
  /// [attachmentIds] reference attachments already uploaded onto the issue.
  Future<void> replyEmail(
    String issueId, {
    required String subject,
    required String body,
    List<String> attachmentIds = const [],
  }) => _api.post(
    '/api/v1/issues/$issueId/reply-email',
    body: {'subject': subject, 'body': body, 'attachmentIds': attachmentIds},
  );

  /// Whether the current user may hard-delete the issue (platform admin,
  /// project lead, or Team-Admin of a team owning the project).
  Future<bool> canDeleteIssue(String id) async {
    final data =
        await _api.get('/api/v1/issues/$id/permissions')
            as Map<String, dynamic>;
    return data['canDelete'] as bool? ?? false;
  }

  // --- Watching ---------------------------------------------------------------

  /// Subscribes the caller to every change on the issue. Idempotent (204), and
  /// a pure notification opt-in — it grants no access, so the server only
  /// accepts it for issues the caller can already see.
  Future<void> watchIssue(String id) => _api.post('/api/v1/issues/$id/watch');

  /// Drops the caller's subscription again. Idempotent.
  Future<void> unwatchIssue(String id) =>
      _api.delete('/api/v1/issues/$id/watch');

  /// One page of the issues the caller watches plus the backend total — the
  /// "Watched" list's infinite scroll.
  ///
  /// Lives here rather than in `AccountRepository` even though the route is
  /// `/me/*`: repositories in this app are grouped by the domain they return
  /// (the timesheet and the notification feed are personal too), and the
  /// account repository deals in account models — it would have to reach into
  /// the work domain for this one endpoint.
  Future<({List<Issue> items, int total})> watchedIssues({
    int page = 0,
    int size = 50,
  }) async {
    final data =
        await _api.get(
              '/api/v1/me/watched',
              query: {'page': page, 'size': size},
            )
            as Map<String, dynamic>;
    return (
      items: ((data['content'] as List<dynamic>?) ?? [])
          .map((i) => Issue.fromJson(i as Map<String, dynamic>))
          .toList(),
      total: data['totalElements'] as int? ?? 0,
    );
  }

  // --- Issue links (typed relationships) -------------------------------------

  /// All links touching the issue, oriented for it (perspective-correct verbs).
  Future<List<IssueLink>> issueLinks(String issueId) async =>
      ((await _api.get('/api/v1/issues/$issueId/links')) as List<dynamic>)
          .map((l) => IssueLink.fromJson(l as Map<String, dynamic>))
          .toList();

  /// Links [issueId] to each of [targetIds] with the given [type]/direction;
  /// returns the refreshed, oriented link list.
  Future<List<IssueLink>> addIssueLinks(
    String issueId, {
    required String type,
    required bool outward,
    required List<String> targetIds,
  }) async =>
      ((await _api.post(
                '/api/v1/issues/$issueId/links',
                body: {
                  'type': type,
                  'outward': outward,
                  'targetIds': targetIds,
                },
              ))
              as List<dynamic>)
          .map((l) => IssueLink.fromJson(l as Map<String, dynamic>))
          .toList();

  /// Removes one link; returns the refreshed, oriented link list.
  Future<List<IssueLink>> deleteIssueLink(
    String issueId,
    String linkId,
  ) async =>
      ((await _api.delete('/api/v1/issues/$issueId/links/$linkId'))
              as List<dynamic>)
          .map((l) => IssueLink.fromJson(l as Map<String, dynamic>))
          .toList();

  /// Raw SSE byte stream of link changes for an issue (parse with [parseSse]).
  /// Carries a payload-free `changed` ping; the client re-fetches its links.
  Future<Stream<List<int>>> issueLinkEventStream(
    String issueId, {
    CancelToken? cancelToken,
  }) => _api.openEventStream(
    '/api/v1/issues/$issueId/links/stream',
    cancelToken: cancelToken,
  );

  /// One newest-first page of an issue's change history, plus the backend total.
  Future<({List<IssueActivity> items, int total})> issueActivity(
    String issueId, {
    int page = 0,
    int size = 30,
  }) async {
    final data =
        await _api.get(
              '/api/v1/issues/$issueId/activity',
              query: {'page': page, 'size': size},
            )
            as Map<String, dynamic>;
    return (
      items: ((data['content'] as List<dynamic>?) ?? [])
          .map((a) => IssueActivity.fromJson(a as Map<String, dynamic>))
          .toList(),
      total: data['totalElements'] as int? ?? 0,
    );
  }

  // --- Attachments ------------------------------------------------------------

  /// Uploads one file to an issue, reporting fractional progress (0–1) as the
  /// bytes are sent so the tile's ring can fill. Returns the updated issue.
  Future<Issue> uploadAttachment(
    String issueId,
    MultipartFile file, {
    void Function(double pct)? onProgress,
    CancelToken? cancelToken,
  }) async => Issue.fromJson(
    await _api.upload(
          '/api/v1/issues/$issueId/attachments',
          file,
          cancelToken: cancelToken,
          onSendProgress: onProgress == null
              ? null
              : (sent, total) => onProgress(total > 0 ? sent / total : 0),
        )
        as Map<String, dynamic>,
  );

  /// Short-lived presigned download URL for an attachment.
  Future<String> attachmentDownloadUrl(
    String issueId,
    String attachmentId,
  ) async =>
      ((await _api.get(
                '/api/v1/issues/$issueId/attachments/$attachmentId/download-url',
              ))
              as Map<String, dynamic>)['url']
          as String;

  Future<void> deleteAttachment(String issueId, String attachmentId) =>
      _api.delete('/api/v1/issues/$issueId/attachments/$attachmentId');

  /// Bulk delete. [ids] are the attachments the caller currently sees — the
  /// server removes only those, so a file someone else uploaded in the meantime
  /// is not swept away with them.
  Future<void> deleteAttachments(String issueId, List<String> ids) =>
      _api.delete(
        '/api/v1/issues/$issueId/attachments'
        '?ids=${ids.map(Uri.encodeQueryComponent).join(',')}',
      );

  /// Relative path of the ZIP archive holding every attachment of an issue
  /// (fetched through the authenticated client, like the single download).
  String attachmentsArchivePath(String issueId) =>
      '/api/v1/issues/$issueId/attachments/archive';

  /// Raw SSE byte stream of attachment changes for an issue (parse with
  /// [parseSse]). Cancel via [cancelToken] when the view is disposed.
  Future<Stream<List<int>>> attachmentEventStream(
    String issueId, {
    CancelToken? cancelToken,
  }) => _api.openEventStream(
    '/api/v1/issues/$issueId/attachments/stream',
    cancelToken: cancelToken,
  );

  // --- Time tracking ----------------------------------------------------------

  Future<List<WorkItem>> workItems(String issueId) async =>
      ((await _api.get('/api/v1/issues/$issueId/work-items')) as List<dynamic>)
          .map((w) => WorkItem.fromJson(w as Map<String, dynamic>))
          .toList();

  Future<WorkItem> addWorkItem(
    String issueId, {
    required int minutes,
    String? activityType,
    String? description,
    DateTime? date,
  }) async {
    return WorkItem.fromJson(
      await _api.post(
            '/api/v1/issues/$issueId/work-items',
            body: {
              'durationMinutes': minutes,
              'activityType': ?activityType,
              'description': ?description,
              if (date != null) 'date': date.toIso8601String().substring(0, 10),
            },
          )
          as Map<String, dynamic>,
    );
  }
}
