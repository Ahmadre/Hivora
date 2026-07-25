import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/widgets/glass_popup_menu.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/blocs/auth_bloc.dart';
import '../../core/events/issue_events.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/team_models.dart';
import '../../core/models/work_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/project_palette.dart';
import '../../core/widgets/hive_widgets.dart';
import '../../core/widgets/soft_card.dart';
import '../../core/widgets/subtask_widgets.dart';
import '../issues/issue_detail_sheet.dart';
import '../issues/issue_form.dart';
import '../issues/issues_screen.dart' show IssueRow;
import '../shell/page_chrome.dart';
import '../sprint/modals/glass_modal.dart'
    show GlassToastKind, showGlassErrorToast, showGlassToast;
import '../sprint/sprint_board_view.dart';
import 'board_filter.dart';
import 'board_manage_menu.dart';
import 'board_swimlanes.dart';
import 'create_board_dialog.dart';
import 'board_filter_popup.dart';
import 'board_people_strip.dart';
import 'board_timeline.dart';
import '../../core/repositories/board_repository.dart';
import '../../core/repositories/issue_repository.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/repositories/team_repository.dart';
import '../../core/repositories/user_repository.dart';

part 'board_screen.header.dart';
part 'board_screen.cards.dart';

// ─────────────────────────── BoardScreen ──────────────────────────────────
// Shown at /board — lists all boards across projects; can filter by project.
// Tapping a board card navigates to /boards/:id.

class BoardScreen extends StatefulWidget {
  const BoardScreen({super.key});

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  List<AgileBoard> _boards = const [];
  List<Project> _projects = const [];
  List<Team> _teams = const [];
  String? _projectFilter;
  bool _loading = true;
  String? _error;

  /// Owner / project-lead / team-lead / platform-admin may manage a board.
  bool _canManageBoard(AgileBoard board) {
    final me = context.read<AuthBloc>().state.user;
    if (me == null) return false;
    if (me.isAdmin || board.ownerId == me.id) return true;
    for (final pid in board.projectIds) {
      final project = _projects.where((p) => p.id == pid).firstOrNull;
      if (project != null && project.leadIds.contains(me.id)) return true;
      final teamLead = _teams.any(
        (t) =>
            t.projectIds.contains(pid) &&
            (t.membershipOf(me.id)?.isAdmin ?? false),
      );
      if (teamLead) return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        context.read<ProjectRepository>().projects(),
        context.read<BoardRepository>().boards(projectId: _projectFilter),
        context.read<TeamRepository>().teams(),
      ]);
      _projects = results[0] as List<Project>;
      _boards = results[1] as List<AgileBoard>;
      _teams = results[2] as List<Team>;
      setState(() => _loading = false);
    } on ApiFailure catch (failure) {
      setState(() {
        _loading = false;
        _error = failure.message;
      });
    }
  }

  Future<void> _showCreate() async {
    if (_projects.isEmpty) {
      showGlassToast(
        context,
        context.t('board.needsProject'),
        kind: GlassToastKind.warning,
      );
      return;
    }
    final created = await showCreateBoardDialog(
      context,
      projects: _projects,
      initialProjectId: _projectFilter,
    );
    if (created != null && mounted) {
      context.push('/boards/${created.id}');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _boards.isEmpty && _error == null) {
      return const Center(child: HiveLoader());
    }
    if (_error != null && _boards.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.t(_error!),
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _load,
              child: Text(context.t('common.retry')),
            ),
          ],
        ),
      );
    }

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            context.pageGutter,
            16 + context.topGutter,
            context.pageGutter,
            8,
          ),
          sliver: SliverToBoxAdapter(
            child: _BoardsListHeader(
              title: context.t('board.title'),
              filter: _projects.isEmpty
                  ? null
                  : _ProjectFilterChip(
                      projects: _projects,
                      selected: _projectFilter,
                      onChanged: (id) {
                        _projectFilter = id;
                        _load();
                      },
                    ),
              onCreate: _showCreate,
            ),
          ),
        ),
        if (_boards.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: context.pageGutter,
                vertical: 24,
              ),
              child: Center(
                child: HiveEmptyState(
                  title: context.t('board.title'),
                  message: context.t('board.empty'),
                  action: FilledButton.icon(
                    onPressed: _showCreate,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: const Color(0xFF2A2410),
                    ),
                    icon: const Icon(LucideIcons.plus, size: 18),
                    label: Text(context.t('board.newBoard')),
                  ),
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              context.pageGutter,
              context.pageGutter,
              context.pageGutter,
              context.pageGutter + context.bottomGutter,
            ),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: context.gridColumns(minTileWidth: 280),
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                mainAxisExtent: 150,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _BoardListCard(
                  board: _boards[index],
                  index: index,
                  projects: _projects,
                  canManage: _canManageBoard(_boards[index]),
                  onChanged: _load,
                ),
                childCount: _boards.length,
              ),
            ),
          ),
      ],
    );
  }
}

/// Header for the boards-list screen.
///
/// On compact (phone) layouts the title gets a full-width row of its own and the
/// project filter + create button wrap onto a second row, so the title is never
/// squeezed to an ellipsis. On wider layouts everything sits inline.
class _BoardsListHeader extends StatelessWidget {
  const _BoardsListHeader({
    required this.title,
    required this.filter,
    required this.onCreate,
  });

  final String title;
  final Widget? filter;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final titleText = Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final createButton = FilledButton.icon(
      onPressed: onCreate,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: const Color(0xFF2A2410),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
      icon: const Icon(LucideIcons.plus, size: 18),
      label: Text(context.t('board.newBoard')),
    );

    if (context.isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          titleText,
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (filter != null)
                Flexible(child: filter!)
              else
                const SizedBox.shrink(),
              const SizedBox(width: 8),
              createButton,
            ],
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: titleText),
        if (filter != null)
          Padding(padding: const EdgeInsets.only(right: 8), child: filter!),
        createButton,
      ],
    );
  }
}

// ─────────────────────────── KanbanBoardScreen ────────────────────────────
// Shown at /boards/:id — the actual drag-and-drop kanban for one board.

class KanbanBoardScreen extends StatefulWidget {
  const KanbanBoardScreen({super.key, required this.boardId});

  final String boardId;

  @override
  State<KanbanBoardScreen> createState() => _KanbanBoardScreenState();
}

/// Which view the kanban screen is showing.
enum BoardViewMode { board, backlog, timeline }

class _KanbanBoardScreenState extends State<KanbanBoardScreen> {
  String? _sprintId;
  BoardView? _view;
  bool _loading = true;
  String? _error;

  BoardViewMode _mode = BoardViewMode.board;
  Map<String, String> _names = const {};
  Map<String, String> _avatars = const {};
  Map<String, String> _projectNames = const {};

  /// The board's spanned projects by id. A cross-project board needs the full
  /// project — not just its name — to answer "which of this column's states does
  /// *this* card's project actually have?" when a card is dropped.
  Map<String, Project> _projectsById = const {};
  List<String> _projectLabels = const [];
  ProjectPalette _palette = ProjectPalette.empty;
  List<Issue> _backlog = const [];
  BoardFilter _filter = BoardFilter.empty;
  BoardGrouping _grouping = BoardGrouping.none;

  /// Every project issue keyed by id — resolves an issue's epic (a sub-task's
  /// epic is its grandparent) for swimlane grouping and the epic filter.
  Map<String, Issue> _issuesById = const {};

  /// Issue links of the board's projects, drawn as dependency connectors on the
  /// timeline. Only that view needs them, so they load on first switch to it.
  List<GanttLink> _links = const [];
  bool _linksLoaded = false;
  bool _linksLoading = false;

  final GlobalKey _filterKey = GlobalKey();

  /// Re-fetch when an issue is created/changed elsewhere (e.g. the global
  /// nav-rail "new issue" button, which can't reach this screen's state).
  StreamSubscription<void>? _issueSub;

  @override
  void initState() {
    super.initState();
    _issueSub = IssueEvents.instance.changes.listen((_) => _load());
    _load();
  }

  @override
  void dispose() {
    _issueSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Captured before the awaits so the directory lookup below doesn't reach
      // through `context` across an async gap.
      final userRepo = context.read<UserRepository>();
      final results = await Future.wait([
        context.read<BoardRepository>().boardView(
          widget.boardId,
          sprintId: _sprintId,
        ),
        context.read<ProjectRepository>().projects(),
        context.read<TeamRepository>().teams(),
      ]);
      final view = results[0] as BoardView;
      final projects = results[1] as List<Project>;
      final loaded = await _loadBacklog(view.board.projectIds);
      final backlog = loaded.backlog;
      // Resolve display names/avatars for only the people this board actually
      // references (issue assignees + reporters) via the capped by-ids endpoint,
      // rather than draining the whole org directory. The set is bounded by the
      // board's membership; the interactive assignee/author pickers derive their
      // own options from these same issues, so nothing here shows the directory.
      final users = await userRepo.usersByIds(_boardPeopleIds(view, backlog));
      if (!mounted) return;
      final boardProjectIds = view.board.projectIds.toSet();
      setState(() {
        _view = view;
        _names = {for (final u in users) u.id: u.displayName};
        _avatars = {
          for (final u in users)
            if (u.avatarUrl != null && u.avatarUrl!.isNotEmpty)
              u.id: u.avatarUrl!,
        };
        _projectNames = {for (final p in projects) p.id: p.name};
        _projectsById = {
          for (final p in projects)
            if (boardProjectIds.contains(p.id)) p.id: p,
        };
        _projectLabels = [
          for (final p in projects)
            if (boardProjectIds.contains(p.id)) ...p.labelNames,
        ];
        _palette = ProjectPalette.fromProjects(
          projects.where((p) => boardProjectIds.contains(p.id)),
        );
        _backlog = backlog;
        _issuesById = loaded.byId;
        _loading = false;
      });
      // Links can change with the issues (a reload is triggered by every issue
      // event), so re-pull them whenever the timeline is the visible view.
      _linksLoaded = false;
      if (_mode == BoardViewMode.timeline) await _loadLinks();
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = failure.message;
      });
    }
  }

  /// Switches view, pulling the link graph in the first time the timeline is
  /// shown — the kanban and backlog draw no connectors, so nothing else pays
  /// for it.
  void _switchMode(BoardViewMode mode) {
    setState(() => _mode = mode);
    if (mode == BoardViewMode.timeline) _loadLinks();
  }

  Future<void> _loadLinks() async {
    final view = _view;
    if (_linksLoaded || _linksLoading || view == null) return;
    _linksLoading = true;
    final repository = context.read<ProjectRepository>();
    try {
      final lists = await Future.wait(
        view.board.projectIds.map(repository.ganttLinks),
      );
      if (!mounted) return;
      setState(() {
        _links = [for (final list in lists) ...list];
        _linksLoaded = true;
      });
    } on ApiFailure {
      // Connectors are an overlay on a chart that already renders — a failed
      // graph must not take the board down with it.
    } finally {
      _linksLoading = false;
    }
  }

  /// Loads every project issue once: the backlog (no-sprint issues) plus a
  /// by-id index used to resolve an issue's epic for grouping / filtering.
  Future<({List<Issue> backlog, Map<String, Issue> byId})> _loadBacklog(
    List<String> projectIds,
  ) async {
    if (projectIds.isEmpty) {
      return (backlog: const <Issue>[], byId: const <String, Issue>{});
    }
    // allIssues pages through the whole backend result set (the search endpoint
    // clamps size to 100), so the by-id index and backlog never silently miss
    // issues beyond the first page.
    final pages = await Future.wait(
      projectIds.map(
        (p) => context.read<IssueRepository>().allIssues(projectId: p),
      ),
    );
    final seen = <String>{};
    final out = <Issue>[];
    final byId = <String, Issue>{};
    for (final page in pages) {
      for (final issue in page) {
        byId[issue.id] = issue;
        if (issue.sprintId == null && seen.add(issue.id)) out.add(issue);
      }
    }
    return (backlog: out, byId: byId);
  }

  /// The distinct directory ids this board needs to resolve to names/avatars:
  /// every assignee and reporter across the board columns and the backlog. Feeds
  /// the bounded by-ids lookup that replaces the old whole-directory fetch — the
  /// assignee/author pickers only ever offer people already present here.
  List<String> _boardPeopleIds(BoardView view, List<Issue> backlog) {
    final ids = <String>{};
    void collect(Issue i) {
      final a = i.assigneeId;
      if (a != null && a.isNotEmpty) ids.add(a);
      for (final id in i.assigneeIds) {
        if (id.isNotEmpty) ids.add(id);
      }
      final r = i.reporterId;
      if (r != null && r.isNotEmpty) ids.add(r);
    }

    for (final column in view.columns) {
      column.issues.forEach(collect);
    }
    backlog.forEach(collect);
    return ids.toList();
  }

  // ---- derived views ----

  List<Issue> get _allBoardIssues => [
    for (final c in _view?.columns ?? const <BoardColumnView>[]) ...c.issues,
  ];

  List<BoardColumnView> get _kanbanColumns =>
      (_view?.columns ?? const <BoardColumnView>[]).toList();

  /// Epics across the board's projects — drive grouping headers + the filter.
  List<Issue> get _epics =>
      _issuesById.values.where((i) => i.isEpic).toList()
        ..sort((a, b) => a.readableId.compareTo(b.readableId));

  Map<String, String> get _epicNames => {
    for (final e in _epics) e.id: '${e.readableId}  ${e.title}',
  };

  /// Combined predicate: every facet plus the epic facet (resolved per issue).
  bool _passes(Issue i) =>
      _filter.matches(i) && _filter.matchesEpic(boardEpicOf(i, _issuesById));

  List<String> get _peopleIds {
    final seen = <String>{};
    final out = <String>[];
    for (final issue in [..._allBoardIssues, ..._backlog]) {
      final a = issue.assigneeId;
      if (a != null && a.isNotEmpty && seen.add(a)) out.add(a);
    }
    return out;
  }

  BoardFilterOptions get _options => BoardFilterOptions.from(
    issues: [..._allBoardIssues, ..._backlog],
    boardSprints: _view?.sprints ?? const [],
    projectLabels: _projectLabels,
    epicIds: _epics.map((e) => e.id),
  );

  Map<String, String> get _sprintNames => {
    for (final s in _view?.sprints ?? const <Sprint>[]) s.id: s.name,
  };

  Sprint? get _activeSprint {
    final view = _view;
    if (view == null) return null;
    if (_sprintId != null) {
      return view.sprints.where((s) => s.id == _sprintId).firstOrNull;
    }
    final active = view.board.activeSprintId;
    if (active != null) {
      return view.sprints.where((s) => s.id == active).firstOrNull;
    }
    return null;
  }

  void _openIssue(Issue issue) =>
      showIssueDetailSheet(context, issueId: issue.id, onChanged: _load);

  /// Whether this board spans more than one project — the signal that turns on
  /// the cross-project affordances (project chip on cards, project swimlane).
  bool get _isCrossProject => (_view?.board.projectIds.length ?? 0) > 1;

  /// Project names for the card chips: empty on a single-project board, where
  /// tagging every card with the one project it can possibly belong to says
  /// nothing.
  Map<String, String> get _cardProjectNames =>
      _isCrossProject ? _projectNames : const {};

  Future<void> _moveIssue(Issue issue, BoardColumnView column) async {
    if (column.states.contains(issue.state) || column.states.isEmpty) return;
    final target = boardDropState(issue, column.states, _projectsById);
    if (target == null) {
      showGlassErrorToast(context, context.t('board.dropNotInWorkflow'));
      return;
    }
    if (target == issue.state) return;
    try {
      await context.read<IssueRepository>().updateIssue(issue.id, {
        'state': target,
      });
      await _load();
    } on ApiFailure catch (failure) {
      if (mounted) {
        showGlassErrorToast(context, context.t(failure.message));
      }
    }
  }

  Future<void> _addIssue(
    BoardColumnView column, {
    String? parentId,
    String? forcedType,
    String? assigneeId,
  }) async {
    final view = _view;
    if (view == null) return;
    final projectId = view.board.projectIds.isNotEmpty
        ? view.board.projectIds.first
        : null;
    // On a cross-project board the column carries one state per spanned
    // project, so pre-fill the one belonging to the project the form starts in
    // (the user can still switch project inside the form).
    final project = projectId == null ? null : _projectsById[projectId];
    final initialState = column.states.isEmpty
        ? null
        : (project == null
              ? column.states.first
              : column.states.firstWhere(
                  (s) => project.stateNames.any(
                    (own) => own.toLowerCase() == s.toLowerCase(),
                  ),
                  orElse: () => column.states.first,
                ));
    final created = await showIssueForm(
      context,
      projectId: projectId,
      initialState: initialState,
      parentId: parentId,
      forcedType: forcedType,
      initialAssigneeId: assigneeId,
    );
    if (created != null) await _load();
  }

  /// The parent to pre-fill when creating an issue inside a swimlane: the
  /// lane's epic under the epic grouping, the lane's parent issue under the
  /// sub-task grouping — never the catch-all "none" lane.
  String? _laneParentId(BoardLane lane) {
    if (lane.key == kBoardLaneNoneKey) return null;
    return switch (_grouping) {
      BoardGrouping.epic || BoardGrouping.subtask => lane.key,
      _ => null,
    };
  }

  void _openFilter() => openBoardFilter(
    context,
    anchorKey: _filterKey,
    filter: _filter,
    options: _options,
    names: _names,
    avatars: _avatars,
    sprintNames: _sprintNames,
    epicNames: _epicNames,
    onChanged: (f) => setState(() => _filter = f),
  );

  @override
  Widget build(BuildContext context) {
    if (_loading && _view == null) {
      return const Center(child: HiveLoader());
    }
    if (_error != null && _view == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.t(_error!),
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _load,
              child: Text(context.t('common.retry')),
            ),
          ],
        ),
      );
    }
    final view = _view!;
    // Scrum boards swap the Kanban/Backlog/Timeline surfaces for the sprint
    // planning · active · insights surfaces. The sprint view owns its own data
    // (sprints, story points, report) and reuses the loaded name maps.
    if (view.board.isScrum) {
      return PageChrome(
        title: view.board.name,
        child: ScrumBoardView(
          view: view,
          names: _names,
          avatars: _avatars,
          projectNames: _projectNames,
          projectsById: _projectsById,
          onOpenIssue: _openIssue,
        ),
      );
    }
    // Back navigation is handled by the shell app bar (via PageChrome). The
    // in-page PageHead already carries the board name, so the shell shows the
    // generic section title instead of repeating it.
    return PageChrome(
      title: context.t('nav.board'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              context.pageGutter,
              22 + context.topGutter,
              context.pageGutter,
              10,
            ),
            child: _header(view),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              context.pageGutter,
              0,
              context.pageGutter,
              10,
            ),
            child: _metaArea(view),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  // ---- header: title + view switcher ----

  /// Deletes the open board, then leaves for the boards overview (a fresh route
  /// so the list no longer shows it).
  Widget _header(BoardView view) {
    final projectLabel = view.board.projectIds
        .map((id) => _projectNames[id] ?? '')
        .where((s) => s.isNotEmpty)
        .join(', ');
    final subtitle = projectLabel.isEmpty
        ? context.t('board.agileBoard')
        : '$projectLabel · ${context.t('board.agileBoard')}';

    if (context.isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHead(title: view.board.name, subtitle: subtitle),
          const SizedBox(height: 12),
          // Right-aligned, collapsible, responsive-label switcher (mobile).
          _CompactViewSwitcher(
            items: _switcherItems(),
            selected: _viewModes.indexOf(_mode).clamp(0, _viewModes.length - 1),
            onChanged: (i) => _switchMode(_viewModes[i]),
          ),
        ],
      );
    }
    return PageHead(
      title: view.board.name,
      subtitle: subtitle,
      actions: [
        SegmentedControl(
          items: _switcherItems(),
          selected: _viewModes.indexOf(_mode).clamp(0, _viewModes.length - 1),
          onChanged: (i) => setState(() => _mode = _viewModes[i]),
        ),
      ],
    );
  }

  /// Views offered for a (Kanban) board. The Backlog view is a Scrum-only
  /// concept, so it isn't offered here — Scrum boards render the dedicated
  /// sprint planning surface instead.
  static const List<BoardViewMode> _viewModes = [
    BoardViewMode.board,
    BoardViewMode.timeline,
  ];

  SegmentItem _itemFor(BoardViewMode mode) => switch (mode) {
    BoardViewMode.board => SegmentItem(
      label: context.t('board.view.board'),
      icon: LucideIcons.squareKanban,
    ),
    BoardViewMode.backlog => SegmentItem(
      label: context.t('board.view.backlog'),
      icon: LucideIcons.list,
    ),
    BoardViewMode.timeline => SegmentItem(
      label: context.t('board.view.timeline'),
      icon: LucideIcons.waypoints,
    ),
  };

  List<SegmentItem> _switcherItems() => [
    for (final mode in _viewModes) _itemFor(mode),
  ];

  // ---- meta area: sprint header + people strip + filter ----

  Widget _metaArea(BoardView view) {
    final sprint = _activeSprint;
    final children = <Widget>[];
    if (sprint != null) {
      children.add(
        Row(
          children: [
            Expanded(child: _SprintHeader(sprint: sprint)),
            if (view.sprints.length > 1) ...[
              const SizedBox(width: 12),
              _SprintSelector(
                sprints: view.sprints,
                selected: _sprintId,
                onChanged: (value) {
                  _sprintId = value;
                  _load();
                },
              ),
            ],
          ],
        ),
      );
      children.add(const SizedBox(height: 10));
    }
    children.add(_controlsRow());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _controlsRow() {
    final people = BoardPeopleStrip(
      userIds: _peopleIds,
      names: _names,
      avatars: _avatars,
      selected: _filter.assignees,
      onToggle: (id) => setState(
        () => _filter = _filter.toggle(BoardFilterFacet.assignee, id),
      ),
    );
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: people,
          ),
        ),
        const SizedBox(width: 10),
        BoardGroupByButton(
          value: _grouping,
          options: boardGroupingsFor(crossProject: _isCrossProject),
          onChanged: (g) => setState(() => _grouping = g),
        ),
        const SizedBox(width: 10),
        _BoardFilterButton(
          key: _filterKey,
          count: _filter.activeCount,
          onTap: _openFilter,
        ),
      ],
    );
  }

  // ---- body ----

  Widget _body() {
    switch (_mode) {
      case BoardViewMode.board:
        return _kanban();
      case BoardViewMode.backlog:
        return _backlogList();
      case BoardViewMode.timeline:
        // The timeline is roadmap-like, so epics stay (they carry date ranges);
        // sub-tasks are nested detail and don't belong on it.
        return BoardTimeline(
          issues: _allBoardIssues
              .where((i) => _passes(i) && !i.isSubtask)
              .toList(),
          links: _links,
          onOpen: _openIssue,
          padding: EdgeInsets.fromLTRB(
            context.pageGutter,
            0,
            context.pageGutter,
            context.pageGutter + context.bottomGutter,
          ),
        );
    }
  }

  Widget _kanban() {
    final columns = _kanbanColumns;
    if (columns.isEmpty) {
      return Center(
        child: Text(
          context.t('board.empty'),
          style: TextStyle(color: AppColors.inkSoft),
        ),
      );
    }
    if (_grouping != BoardGrouping.none) return _groupedBoard(columns);
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.fromLTRB(
        context.pageGutter,
        0,
        context.pageGutter,
        context.pageGutter + context.bottomGutter,
      ),
      itemCount: columns.length,
      separatorBuilder: (_, _) => const SizedBox(width: 16),
      itemBuilder: (context, index) {
        final column = columns[index];
        final issues = column.issues
            .where((i) => _passes(i) && boardCardVisible(i, _grouping))
            .toList();
        return _BoardColumn(
          column: column,
          issues: issues,
          palette: _palette,
          names: _names,
          avatars: _avatars,
          projectNames: _cardProjectNames,
          onAccept: (issue) => _moveIssue(issue, column),
          onAddIssue: () => _addIssue(column),
          onOpenIssue: _openIssue,
        );
      },
    );
  }

  // ---- swimlanes (grouped board) ----

  /// Renders the grouped board via the shared [BoardSwimlanes]: lanes per the
  /// active grouping, each lane carrying the full column set and its own
  /// collapse toggle.
  Widget _groupedBoard(List<BoardColumnView> columns) {
    final lanes = computeBoardLanes(
      context: context,
      grouping: _grouping,
      issues: _allBoardIssues.where(_passes).toList(),
      issuesById: _issuesById,
      epics: _epics,
      names: _names,
      avatars: _avatars,
      palette: _palette,
      projectNames: _projectNames,
      onOpenIssue: _openIssue,
    );
    if (lanes.isEmpty) {
      return Center(
        child: Text(
          context.t('board.empty'),
          style: TextStyle(color: AppColors.inkSoft),
        ),
      );
    }
    return BoardSwimlanes(
      columns: columns,
      lanes: lanes,
      padding: EdgeInsets.fromLTRB(
        context.pageGutter,
        0,
        context.pageGutter,
        context.pageGutter + context.bottomGutter,
      ),
      columnBuilder: (column, issues, lane) => _BoardColumn(
        column: column,
        laneMode: true,
        issues: issues,
        palette: _palette,
        names: _names,
        avatars: _avatars,
        // The project lane already names the project in its header — repeating
        // it on every card inside would be noise.
        projectNames: _grouping == BoardGrouping.project
            ? const {}
            : _cardProjectNames,
        onAccept: (issue) => _moveIssue(issue, column),
        onAddIssue: () => _addIssue(
          column,
          parentId: _laneParentId(lane),
          // A sub-task lane's parent is a standard issue, so the only valid
          // child there is a sub-task.
          forcedType:
              _grouping == BoardGrouping.subtask &&
                  lane.key != kBoardLaneNoneKey
              ? 'SUBTASK'
              : null,
          // The assignee lane's user pre-fills the assignee (still editable).
          assigneeId:
              _grouping == BoardGrouping.assignee &&
                  lane.key != kBoardLaneNoneKey
              ? lane.key
              : null,
        ),
        onOpenIssue: _openIssue,
      ),
    );
  }

  Widget _backlogList() {
    const rank = {'URGENT': 4, 'HIGH': 3, 'NORMAL': 2, 'LOW': 1};
    int prio(Issue i) => switch (i.priority.toUpperCase()) {
      'SHOWSTOPPER' || 'CRITICAL' || 'URGENT' => 5,
      'MAJOR' || 'HIGH' => 3,
      'MINOR' || 'LOW' => 1,
      _ => rank[i.priority.toUpperCase()] ?? 2,
    };
    // The backlog lists the standard work items only — epics are containers and
    // sub-tasks live inside their parent (mirrors Jira's backlog).
    final items = _backlog.where((i) => _passes(i) && i.isStandard).toList()
      ..sort((a, b) => prio(b).compareTo(prio(a)));

    final padding = EdgeInsets.fromLTRB(
      context.pageGutter,
      0,
      context.pageGutter,
      context.pageGutter + context.bottomGutter,
    );

    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        color: AppColors.accent,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: padding,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 72),
              child: Center(
                child: Text(
                  context.t('board.backlogEmpty'),
                  style: TextStyle(color: AppColors.inkSoft),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Lazy builder (not a concrete children list): the backlog pages the whole
    // cross-project set into memory, so only visible IssueRows should be built.
    // Leading entries: the count subtitle, plus a table header on wide layouts.
    final leading = context.isCompact ? 1 : 2;
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.accent,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: padding,
        itemCount: items.length + leading,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                context.t(
                  'board.backlogSubtitle',
                  variables: {'count': '${items.length}'},
                ),
                style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
              ),
            );
          }
          if (leading == 2 && index == 1) return const _BacklogTableHeader();
          final issue = items[index - leading];
          return Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: IssueRow(
              issue: issue,
              assignee: _names[issue.assigneeId],
              assigneeAvatar: _avatars[issue.assigneeId],
              onTap: () => _openIssue(issue),
            ),
          );
        },
      ),
    );
  }
}
