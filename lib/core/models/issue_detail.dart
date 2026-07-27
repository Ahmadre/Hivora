import 'core_models.dart';
import 'work_models.dart';

/// First-paint bootstrap payload from `GET /api/v1/issues/{id}/detail`: the
/// issue plus everything the detail view needs, composed server-side in ONE
/// response. Replaces the old ~13-call fan-out that made native issue-open slow
/// (HTTP/1.1, a TLS handshake per request) and intermittently fail.
///
/// Comments and activity carry only page 0 — the "load more" paths keep using
/// the paged `/comments` and `/activity` endpoints.
class IssueDetail {
  const IssueDetail({
    required this.issue,
    required this.project,
    required this.comments,
    required this.commentsTotal,
    required this.pinnedComments,
    required this.activity,
    required this.activityTotal,
    required this.workItems,
    required this.hierarchy,
    required this.sprints,
    required this.users,
    required this.canDelete,
  });

  final Issue issue;
  final Project? project;
  final List<IssueComment> comments;
  final int commentsTotal;
  final List<IssueComment> pinnedComments;
  final List<IssueActivity> activity;
  final int activityTotal;
  final List<WorkItem> workItems;
  final IssueHierarchy hierarchy;
  final List<Sprint> sprints;

  /// The minimal set of users the view references (assignees, reporters,
  /// comment authors + reactors, activity actors, hierarchy people) — not the
  /// whole org directory. The full directory for pickers is fetched lazily.
  final List<DirectoryUser> users;
  final bool canDelete;

  factory IssueDetail.fromJson(Map<String, dynamic> json) {
    List<T> parseList<T>(
      dynamic value,
      T Function(Map<String, dynamic>) from,
    ) => ((value as List<dynamic>?) ?? const [])
        .map((e) => from(e as Map<String, dynamic>))
        .toList();
    final commentsPage =
        (json['comments'] as Map<String, dynamic>?) ?? const {};
    final activityPage =
        (json['activity'] as Map<String, dynamic>?) ?? const {};
    return IssueDetail(
      issue: Issue.fromJson(json['issue'] as Map<String, dynamic>),
      project: json['project'] == null
          ? null
          : Project.fromJson(json['project'] as Map<String, dynamic>),
      comments: parseList(commentsPage['content'], IssueComment.fromJson),
      commentsTotal: commentsPage['totalElements'] as int? ?? 0,
      pinnedComments: parseList(json['pinnedComments'], IssueComment.fromJson),
      activity: parseList(activityPage['content'], IssueActivity.fromJson),
      activityTotal: activityPage['totalElements'] as int? ?? 0,
      workItems: parseList(json['workItems'], WorkItem.fromJson),
      hierarchy: json['hierarchy'] == null
          ? IssueHierarchy.empty
          : IssueHierarchy.fromJson(json['hierarchy'] as Map<String, dynamic>),
      sprints: parseList(json['sprints'], Sprint.fromJson),
      users: parseList(json['users'], DirectoryUser.fromJson),
      canDelete: json['canDelete'] as bool? ?? false,
    );
  }
}
