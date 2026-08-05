/// Domain layer — one repository per domain, all sharing the single
/// [ApiClient] data source. Constructed once at startup via
/// [HinataRepositories] and provided app-wide with `MultiRepositoryProvider`.
library;

import '../api/api_client.dart';
import 'account_repository.dart';
import 'admin_repository.dart';
import 'article_repository.dart';
import 'auth_repository.dart';
import 'board_repository.dart';
import 'comment_repository.dart';
import 'dashboard_repository.dart';
import 'git_repository.dart';
import 'issue_repository.dart';
import 'media_repository.dart';
import 'meta_repository.dart';
import 'moderation_repository.dart';
import 'notification_repository.dart';
import 'project_repository.dart';
import 'search_repository.dart';
import 'sprint_repository.dart';
import 'team_repository.dart';
import 'timesheet_repository.dart';
import 'user_repository.dart';
import 'weekly_summary_repository.dart';

export 'account_repository.dart';
export 'admin_repository.dart';
export 'article_repository.dart';
export 'auth_repository.dart';
export 'board_repository.dart';
export 'comment_repository.dart';
export 'dashboard_repository.dart';
export 'git_repository.dart';
export 'issue_repository.dart';
export 'media_repository.dart';
export 'meta_repository.dart';
export 'moderation_repository.dart';
export 'notification_repository.dart';
export 'project_repository.dart';
export 'search_repository.dart';
export 'sprint_repository.dart';
export 'team_repository.dart';
export 'timesheet_repository.dart';
export 'user_repository.dart';
export 'weekly_summary_repository.dart';

/// Composition root for the domain layer: builds every repository exactly once
/// over the shared [ApiClient].
///
/// [moderation] is separate from [admin] on purpose: reporting and blocking are
/// capabilities every signed-in member has, while the queue those reports feed
/// is admin-only.
class HinataRepositories {
  factory HinataRepositories(ApiClient api) {
    final boards = BoardRepository(api);
    return HinataRepositories._(
      meta: MetaRepository(api),
      auth: AuthRepository(api),
      account: AccountRepository(api),
      users: UserRepository(api),
      projects: ProjectRepository(api),
      issues: IssueRepository(api),
      comments: CommentRepository(api),
      media: MediaRepository(api),
      boards: boards,
      sprints: SprintRepository(api, boards: boards),
      timesheet: TimesheetRepository(api),
      search: SearchRepository(api),
      articles: ArticleRepository(api),
      dashboard: DashboardRepository(api),
      weeklySummary: WeeklySummaryRepository(api),
      notifications: NotificationRepository(api),
      moderation: ModerationRepository(api),
      admin: AdminRepository(api),
      teams: TeamRepository(api),
      git: GitRepository(api),
    );
  }

  const HinataRepositories._({
    required this.meta,
    required this.auth,
    required this.account,
    required this.users,
    required this.projects,
    required this.issues,
    required this.comments,
    required this.media,
    required this.boards,
    required this.sprints,
    required this.timesheet,
    required this.search,
    required this.articles,
    required this.dashboard,
    required this.weeklySummary,
    required this.notifications,
    required this.moderation,
    required this.admin,
    required this.teams,
    required this.git,
  });

  final MetaRepository meta;
  final AuthRepository auth;
  final AccountRepository account;
  final UserRepository users;
  final ProjectRepository projects;
  final IssueRepository issues;
  final CommentRepository comments;
  final MediaRepository media;
  final BoardRepository boards;
  final SprintRepository sprints;
  final TimesheetRepository timesheet;
  final SearchRepository search;
  final ArticleRepository articles;
  final DashboardRepository dashboard;
  final WeeklySummaryRepository weeklySummary;
  final NotificationRepository notifications;
  final ModerationRepository moderation;
  final AdminRepository admin;
  final TeamRepository teams;
  final GitRepository git;
}
