import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'repositories.dart';

/// Re-provides every domain repository into a subtree that lives OUTSIDE the app
/// provider scope — e.g. a modal sheet / overlay pushed on the root navigator,
/// whose `BuildContext` cannot reach the `RepositoryProvider`s installed at the
/// app root.
///
/// Each repository is read from [source] (a context that *is* under the app
/// providers) and re-exposed by value, so descendants can `context.read<…>()`
/// the specific repository they need. Providing the full set (rather than a
/// hand-picked subset) keeps modals robust: adding a repository call deep in a
/// modal's widget tree can never crash at runtime for a missing provider.
List<RepositoryProvider> domainRepositoryProviders(BuildContext source) => [
  RepositoryProvider<MetaRepository>.value(
    value: source.read<MetaRepository>(),
  ),
  RepositoryProvider<AuthRepository>.value(
    value: source.read<AuthRepository>(),
  ),
  RepositoryProvider<AccountRepository>.value(
    value: source.read<AccountRepository>(),
  ),
  RepositoryProvider<UserRepository>.value(
    value: source.read<UserRepository>(),
  ),
  RepositoryProvider<ProjectRepository>.value(
    value: source.read<ProjectRepository>(),
  ),
  RepositoryProvider<IssueRepository>.value(
    value: source.read<IssueRepository>(),
  ),
  RepositoryProvider<CommentRepository>.value(
    value: source.read<CommentRepository>(),
  ),
  RepositoryProvider<MediaRepository>.value(
    value: source.read<MediaRepository>(),
  ),
  RepositoryProvider<BoardRepository>.value(
    value: source.read<BoardRepository>(),
  ),
  RepositoryProvider<SprintRepository>.value(
    value: source.read<SprintRepository>(),
  ),
  RepositoryProvider<TimesheetRepository>.value(
    value: source.read<TimesheetRepository>(),
  ),
  RepositoryProvider<SearchRepository>.value(
    value: source.read<SearchRepository>(),
  ),
  RepositoryProvider<ArticleRepository>.value(
    value: source.read<ArticleRepository>(),
  ),
  RepositoryProvider<DashboardRepository>.value(
    value: source.read<DashboardRepository>(),
  ),
  RepositoryProvider<WeeklySummaryRepository>.value(
    value: source.read<WeeklySummaryRepository>(),
  ),
  RepositoryProvider<NotificationRepository>.value(
    value: source.read<NotificationRepository>(),
  ),
  RepositoryProvider<ModerationRepository>.value(
    value: source.read<ModerationRepository>(),
  ),
  RepositoryProvider<AdminRepository>.value(
    value: source.read<AdminRepository>(),
  ),
  RepositoryProvider<TeamRepository>.value(
    value: source.read<TeamRepository>(),
  ),
  RepositoryProvider<GitRepository>.value(value: source.read<GitRepository>()),
];
