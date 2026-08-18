import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/blocs/paged_cubit.dart';
import '../../core/events/issue_events.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/core_models.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/issue_repository.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/repositories/user_repository.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/project_palette.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/hive_widgets.dart';
import '../../core/widgets/status_widgets.dart';
import 'issues_screen.dart' show IssueRow;

/// The issues the signed-in user subscribed to — every change on them reaches
/// them as a notification, whether or not they are assignee or reporter.
///
/// A personal list like the timesheet or the notification feed, so it lives in
/// the nav's secondary group rather than behind an issue filter (watching is
/// not a facet of the issue search; the server answers it from `/me/watched`).
class WatchedIssuesScreen extends StatefulWidget {
  const WatchedIssuesScreen({super.key});

  @override
  State<WatchedIssuesScreen> createState() => _WatchedIssuesScreenState();
}

class _WatchedIssuesScreenState extends State<WatchedIssuesScreen> {
  late final IssueRepository _repo;
  late final PagedCubit<Issue> _cubit;
  final ScrollController _scroll = ScrollController();
  StreamSubscription<void>? _watchSub;

  // Reference data for the rows (assignee name/avatar, per-project state hues).
  // Best-effort: a failed load only costs the rows their names, so it must not
  // block the list itself.
  Map<String, String> _names = const {};
  Map<String, String> _avatars = const {};
  ProjectPalette _palette = ProjectPalette.empty;

  @override
  void initState() {
    super.initState();
    // Resolved once — the fetcher closure outlives this build and every
    // loadMore would otherwise walk the element tree again.
    _repo = context.read<IssueRepository>();
    _cubit = PagedCubit<Issue>(
      (page, size) => _repo.watchedIssues(page: page, size: size),
      pageSize: 25,
      keyOf: (issue) => issue.id,
    )..load();
    _scroll.addListener(_onScroll);
    // Watching from the issue sheet broadcasts app-wide; this list is exactly
    // the surface that has to notice, and it holds no handle to that sheet.
    // The narrow watch bus, not IssueEvents: every other issue change leaves
    // this page's membership untouched.
    _watchSub = IssueWatchEvents.instance.changes.listen((_) => _cubit.load());
    _loadRef();
  }

  @override
  void dispose() {
    _watchSub?.cancel();
    _scroll.dispose();
    _cubit.close();
    super.dispose();
  }

  /// Infinite scroll: pull the next page as the user nears the bottom.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 480) _cubit.loadMore();
  }

  Future<void> _loadRef() async {
    try {
      final results = await Future.wait([
        context.read<UserRepository>().users(),
        context.read<ProjectRepository>().projects(),
      ]);
      if (!mounted) return;
      final users = results[0] as List<DirectoryUser>;
      final projects = results[1] as List<Project>;
      setState(() {
        _names = {for (final u in users) u.id: u.displayName};
        _avatars = {
          for (final u in users)
            if (u.avatarUrl != null && u.avatarUrl!.isNotEmpty)
              u.id: u.avatarUrl!,
        };
        _palette = ProjectPalette.fromProjects(projects);
      });
    } catch (_) {
      // Rows fall back to ids and the global state palette.
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PagedCubit<Issue>, PagedState<Issue>>(
      bloc: _cubit,
      builder: (context, state) => RefreshIndicator(
        onRefresh: _cubit.load,
        child: AsyncView(
          isLoading: state.isLoading,
          hasData: state.hasData,
          errorKey: state.errorKey,
          onRetry: _cubit.load,
          builder: (context) => _list(context, state),
        ),
      ),
    );
  }

  Widget _list(BuildContext context, PagedState<Issue> state) {
    final issues = state.items;
    final showEmpty = issues.isEmpty;
    final showLoader = state.isLoadingMore;
    // Lazy builder rather than a concrete child list: the page paginates, so as
    // pages accumulate only the on-screen rows should be built.
    final itemCount =
        1 + (showEmpty ? 1 : issues.length) + (showLoader ? 1 : 0);
    return ListView.builder(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: context.pagePadding,
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHead(
                title: context.t('watched.title'),
                subtitle: context.t('watched.subtitle'),
              ),
              const SizedBox(height: 14),
            ],
          );
        }
        final i = index - 1;
        if (showEmpty) {
          if (i == 0) {
            return HiveEmptyState(
              title: context.t('watched.empty.title'),
              message: context.t('watched.empty.message'),
            );
          }
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: HiveLoader(size: 30)),
          );
        }
        if (i < issues.length) {
          final issue = issues[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: IssueRow(
              issue: issue,
              assignee: issue.assigneeId == null
                  ? null
                  : _names[issue.assigneeId],
              assigneeAvatar: issue.assigneeId == null
                  ? null
                  : _avatars[issue.assigneeId],
              palette: _palette,
            ),
          );
        }
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Center(child: HiveLoader(size: 30)),
        );
      },
    );
  }
}
