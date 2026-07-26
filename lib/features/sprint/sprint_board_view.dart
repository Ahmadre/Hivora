import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api/api_client.dart';
import '../../core/events/issue_events.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/work_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/hive_widgets.dart'
    show SegmentItem, SegmentedControl;
import '../board/board_drag.dart';
import '../board/board_filter.dart';
import '../board/board_filter_popup.dart';
import '../board/board_people_strip.dart';
import '../board/board_swimlanes.dart';
import '../issues/issue_form.dart';
import 'modals/complete_sprint_dialog.dart';
import 'modals/glass_modal.dart' show GlassToastKind, showGlassToast;
import 'modals/create_sprint_dialog.dart';
import 'modals/estimate_dialog.dart';
import 'modals/start_sprint_dialog.dart';
import 'sprint_active_surface.dart';
import 'sprint_insights_surface.dart';
import 'sprint_planning_surface.dart';
import 'widgets/sprint_widgets.dart';
import '../../core/repositories/issue_repository.dart';
import '../../core/repositories/sprint_repository.dart';

/// Number of backlog issues per page in the planning surface.
const int kBacklogPageSize = 12;

/// The Scrum board: Planning · Active sprint · Insights, switched by a
/// segmented control. Owns the sprint working set (sprints, per-sprint issues,
/// the paginated backlog and the insights report) and every mutation, each of
/// which maps to a concrete repository call (optimistic + reconcile on error).
class ScrumBoardView extends StatefulWidget {
  const ScrumBoardView({
    super.key,
    required this.view,
    required this.names,
    this.avatars = const {},
    required this.projectNames,
    this.projectsById = const {},
    required this.onOpenIssue,
  });

  final BoardView view;
  final Map<String, String> names;
  final Map<String, String> avatars;
  final Map<String, String> projectNames;

  /// The board's spanned projects — needed to resolve which state of a merged
  /// column belongs to a dropped card's own project on a cross-project board.
  final Map<String, Project> projectsById;
  final void Function(Issue) onOpenIssue;

  @override
  State<ScrumBoardView> createState() => _ScrumBoardViewState();
}

enum _Tab { planning, active, insights }

class _ScrumBoardViewState extends State<ScrumBoardView> {
  AgileBoard get _board => widget.view.board;

  IssueRepository get _issueApi => context.read<IssueRepository>();
  SprintRepository get _sprintApi => context.read<SprintRepository>();

  // Store-screenshot builds open straight on the Active-sprint board (the kanban
  // columns) rather than Planning, so the marketing shot shows the live board.
  _Tab _tab = const bool.fromEnvironment('SCREENSHOT_MODE')
      ? _Tab.active
      : _Tab.planning;

  List<Sprint> _sprints = const [];
  String? _activeSprintId;
  final Map<String, List<Issue>> _bySprint = {};

  // Backlog (server-paginated for single-project boards; merged + client-paged
  // for multi-project boards).
  List<Issue> _backlog = const [];
  int _backlogTotal = 0;
  int _backlogPage = 0;
  String _query = '';

  bool _loading = true;
  String? _error;

  // Shared people/criteria filter for the Planning + Active surfaces.
  BoardFilter _filter = BoardFilter.empty;
  final GlobalKey _filterKey = GlobalKey();

  // Swimlane grouping for the active-sprint board.
  BoardGrouping _grouping = BoardGrouping.none;

  /// Every project issue keyed by id — resolves an issue's epic (a sub-task's
  /// epic is its grandparent) for swimlane grouping + the epic filter.
  Map<String, Issue> _issuesById = const {};

  // Planning selection / drag.
  final Set<String> _selected = {};

  // Insights report (lazy, for the active sprint).
  SprintReport? _report;
  bool _reportLoading = false;
  String? _reportError;

  /// Re-fetch when an issue changes anywhere — this view owns its own working
  /// set (sprint containers, backlog, project issue index), so a reload of the
  /// enclosing board screen never reaches it. Without this an edit made in the
  /// issue detail (a new sub-task, a sub-task ticked off, a title change) leaves
  /// the sprint cards showing stale data until the Scrum board is rebuilt.
  StreamSubscription<void>? _issueSub;

  @override
  void initState() {
    super.initState();
    _activeSprintId = _board.activeSprintId;
    _issueSub = IssueEvents.instance.changes.listen((_) => _loadAll());
    _loadAll();
  }

  @override
  void dispose() {
    _issueSub?.cancel();
    super.dispose();
  }

  List<Issue> get _activeIssues => _activeSprintId == null
      ? const []
      : (_bySprint[_activeSprintId] ?? const []);

  /// The active sprint's issues for the board surface. Under the "group by
  /// sub-task" grouping it also pulls in the sub-tasks (from the full project
  /// map [_issuesById]) of any standard issue in the sprint — sub-tasks aren't
  /// themselves sprint-assigned, so without this the sub-task swimlanes would be
  /// empty on the Scrum board (unlike Kanban, whose board view already loads the
  /// whole project). Sub-tasks stay hidden in the flat/other groupings because
  /// [boardCardVisible] only surfaces them under [BoardGrouping.subtask].
  List<Issue> get _activeBoardIssues {
    final base = _activeIssues;
    if (_grouping != BoardGrouping.subtask) return base;
    final present = {for (final i in base) i.id};
    final withSubtasks = [...base];
    for (final child in _issuesById.values) {
      if (!child.isSubtask) continue;
      final parentId = child.parentId;
      if (parentId != null &&
          present.contains(parentId) &&
          present.add(child.id)) {
        withSubtasks.add(child);
      }
    }
    return withSubtasks;
  }

  Sprint? get _activeSprint {
    for (final s in _sprints) {
      if (s.id == _activeSprintId) return s;
    }
    return null;
  }

  List<Sprint> get _plannedSprints =>
      _sprints.where((s) => s.id != _activeSprintId && !s.archived).toList();

  /// Active sprint first, then the planned ones — the planning containers.
  List<Sprint> get _planningSprints => [?_activeSprint, ..._plannedSprints];

  int get _backlogPages => _backlogTotal == 0
      ? 1
      : ((_backlogTotal + kBacklogPageSize - 1) ~/ kBacklogPageSize);

  /// Every issue currently loaded (all sprint containers + the backlog page) —
  /// the basis for the filter's facet options and the people strip.
  List<Issue> get _allLoadedIssues => [
    for (final list in _bySprint.values) ...list,
    ..._backlog,
  ];

  List<String> get _peopleIds {
    final seen = <String>{};
    final out = <String>[];
    for (final issue in _allLoadedIssues) {
      final a = issue.assigneeId;
      if (a != null && a.isNotEmpty && seen.add(a)) out.add(a);
    }
    return out;
  }

  Map<String, String> get _sprintNames => {
    for (final s in _sprints) s.id: s.name,
  };

  /// Epics across the board's projects — drive grouping headers + the filter.
  List<Issue> get _epics =>
      _issuesById.values.where((i) => i.isEpic).toList()
        ..sort((a, b) => a.readableId.compareTo(b.readableId));

  Map<String, String> get _epicNames => {
    for (final e in _epics) e.id: '${e.readableId}  ${e.title}',
  };

  void _openFilter() => openBoardFilter(
    context,
    anchorKey: _filterKey,
    filter: _filter,
    options: BoardFilterOptions.from(
      issues: _allLoadedIssues,
      boardSprints: _sprints,
      projectLabels: const [],
      epicIds: _epics.map((e) => e.id),
    ),
    names: widget.names,
    avatars: widget.avatars,
    sprintNames: _sprintNames,
    epicNames: _epicNames,
    onChanged: (f) => setState(() => _filter = f),
  );

  // ── loading ─────────────────────────────────────────────────────────────

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sprints = await _sprintApi.sprints(_board.id);
      // The active id is tracked locally across start/complete; drop it if the
      // referenced sprint is gone or archived (the stale board view can't be
      // trusted after a completion).
      if (_activeSprintId != null &&
          !sprints.any((s) => s.id == _activeSprintId && !s.archived)) {
        _activeSprintId = null;
      }
      _bySprint.clear();
      final issueLists = await Future.wait(
        sprints.map((s) => _issueApi.allIssues(sprintId: s.id)),
      );
      for (var i = 0; i < sprints.length; i++) {
        _bySprint[sprints[i].id] = issueLists[i];
      }
      await _loadBacklog();
      await _loadIssueIndex();
      if (!mounted) return;
      setState(() {
        _sprints = sprints;
        _loading = false;
      });
      // Insights are derived from this data, so keep them in step.
      // (Done/sprint/add changes all flow through here.)
      _invalidateReport();
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = failure.message;
      });
    }
  }

  /// Loads every project issue once into [_issuesById] so swimlane grouping can
  /// resolve an issue's epic (including a sub-task's grandparent epic), which
  /// the per-sprint working set alone can't reach.
  Future<void> _loadIssueIndex() async {
    final projectIds = _board.projectIds;
    if (projectIds.isEmpty) {
      _issuesById = const {};
      return;
    }
    // allIssues pages through the whole backend result set (search clamps size
    // to 100), so swimlane epic resolution sees every issue, not just page one.
    final pages = await Future.wait(
      projectIds.map((p) => _issueApi.allIssues(projectId: p)),
    );
    _issuesById = {
      for (final page in pages)
        for (final issue in page) issue.id: issue,
    };
  }

  Future<void> _loadBacklog() async {
    final projectIds = _board.projectIds;
    final query = _query.trim().isEmpty ? null : _query.trim();
    if (projectIds.length <= 1) {
      final res = await _issueApi.issues(
        projectId: projectIds.isEmpty ? null : projectIds.first,
        noSprint: true,
        query: query,
        page: _backlogPage,
        size: kBacklogPageSize,
      );
      _backlog = res.issues;
      _backlogTotal = res.total;
    } else {
      // Multiple projects: the search endpoint is single-project, so merge a
      // bounded page per project and paginate client-side.
      final pages = await Future.wait(
        projectIds.map(
          (p) => _issueApi.allIssues(projectId: p, noSprint: true),
        ),
      );
      var merged = [for (final pg in pages) ...pg];
      if (query != null) {
        final q = query.toLowerCase();
        merged = merged
            .where(
              (i) =>
                  i.readableId.toLowerCase().contains(q) ||
                  i.title.toLowerCase().contains(q) ||
                  i.tags.any((t) => t.toLowerCase().contains(q)),
            )
            .toList();
      }
      _backlogTotal = merged.length;
      final start = _backlogPage * kBacklogPageSize;
      _backlog = merged
          .skip(start)
          .take(kBacklogPageSize)
          .toList(growable: false);
    }
  }

  Future<void> _reloadBacklogOnly() async {
    try {
      await _loadBacklog();
      if (mounted) setState(() {});
    } on ApiFailure catch (failure) {
      _toastKey(failure.message, kind: GlassToastKind.error);
    }
  }

  Future<void> _loadReport() async {
    final id = _activeSprintId;
    if (id == null) return;
    setState(() {
      _reportLoading = true;
      _reportError = null;
    });
    try {
      final report = await _sprintApi.sprintReport(id);
      if (!mounted) return;
      setState(() {
        _report = report;
        _reportLoading = false;
      });
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _reportLoading = false;
        _reportError = failure.message;
      });
    }
  }

  // ── mutations ───────────────────────────────────────────────────────────

  /// Resolves [key] against i18n only after confirming the widget is still
  /// mounted, so [context] is never read across an async gap.
  void _toastKey(
    String key, {
    Map<String, dynamic>? vars,
    GlassToastKind kind = GlassToastKind.info,
  }) {
    if (!mounted) return;
    showGlassToast(context, context.t(key, variables: vars), kind: kind);
  }

  /// Locates an issue across the sprint containers and the backlog.
  Issue? _findIssue(String id) {
    for (final list in _bySprint.values) {
      for (final i in list) {
        if (i.id == id) return i;
      }
    }
    for (final i in _backlog) {
      if (i.id == id) return i;
    }
    return null;
  }

  Future<void> _moveIssueToSprint(Issue issue, String? sprintId) async {
    if (issue.sprintId == sprintId) return;
    final moved = issue.copyWith(sprintId: sprintId);
    setState(() => _applyLocalMove(issue, moved));
    try {
      await _issueApi.updateIssue(issue.id, {'sprintId': sprintId ?? ''});
      // A full (non-flashing) reload reconciles the server's truth — including
      // the backlog→working-state promotion when an issue enters a sprint.
      await _loadAll();
    } on ApiFailure catch (failure) {
      _toastKey(failure.message, kind: GlassToastKind.error);
      await _loadAll();
    }
  }

  /// Removes [from] from its current container and inserts [to] into its target.
  void _applyLocalMove(Issue from, Issue to) {
    for (final entry in _bySprint.entries) {
      entry.value.removeWhere((i) => i.id == from.id);
    }
    _backlog = _backlog.where((i) => i.id != from.id).toList();
    _selected.remove(from.id);
    if (to.sprintId != null) {
      (_bySprint[to.sprintId!] ??= []).insert(0, to);
    } else {
      _backlog = [to, ..._backlog];
      _backlogTotal += 1;
    }
  }

  Future<void> _bulkMove(String? sprintId) async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    setState(() {
      for (final id in ids) {
        final issue = _findIssue(id);
        if (issue != null) {
          _applyLocalMove(issue, issue.copyWith(sprintId: sprintId));
        }
      }
      _selected.clear();
    });
    try {
      await Future.wait(
        ids.map(
          (id) => _issueApi.updateIssue(id, {'sprintId': sprintId ?? ''}),
        ),
      );
      await _loadAll();
    } on ApiFailure catch (failure) {
      _toastKey(failure.message, kind: GlassToastKind.error);
      await _loadAll();
    }
  }

  Future<void> _estimate(Issue issue) async {
    final result = await showEstimateDialog(context, issue: issue);
    if (result == null) return;
    final patch = result.points == null
        ? {'clearStoryPoints': true}
        : {'storyPoints': result.points};
    setState(() {
      final updated = issue.copyWith(storyPoints: result.points);
      _replaceIssue(updated);
    });
    try {
      await _issueApi.updateIssue(issue.id, patch);
      // Story points feed committed/velocity/burndown — refresh insights.
      _invalidateReport();
    } on ApiFailure catch (failure) {
      _toastKey(failure.message, kind: GlassToastKind.error);
      await _loadAll();
    }
  }

  /// Drops the cached insights report (refreshing it if it's currently shown)
  /// so it never lags behind a change that affects the numbers.
  void _invalidateReport() {
    if (_tab == _Tab.insights) {
      _loadReport();
    } else {
      _report = null;
    }
  }

  void _replaceIssue(Issue updated) {
    for (final list in _bySprint.values) {
      final idx = list.indexWhere((i) => i.id == updated.id);
      if (idx != -1) list[idx] = updated;
    }
    final bi = _backlog.indexWhere((i) => i.id == updated.id);
    if (bi != -1) {
      _backlog = [..._backlog]..[bi] = updated;
    }
  }

  Future<void> _moveIssueState(Issue issue, String newState) async {
    if (issue.state == newState) return;
    // Let the card settle in visibly at its new home — the tail end of the
    // drag, not a separate effect.
    boardDrag.land(issue.id);
    setState(() => _replaceIssue(issue.copyWith(state: newState)));
    try {
      await _issueApi.updateIssue(issue.id, {'state': newState});
      await _loadAll();
    } on ApiFailure catch (failure) {
      _toastKey(failure.message, kind: GlassToastKind.error);
      await _loadAll();
    }
  }

  Future<void> _addIssue(String? sprintId) async {
    final projectId = _board.projectIds.isNotEmpty
        ? _board.projectIds.first
        : null;
    // Pre-select the target sprint so the issue is created straight into it
    // (the server starts it in the working state, not the backlog).
    final created = await showIssueForm(
      context,
      projectId: projectId,
      initialSprintId: sprintId,
    );
    if (created == null) return;
    await _loadAll();
  }

  int _nextSprintNumber() {
    var max = 0;
    final re = RegExp(r'(\d+)');
    for (final s in _sprints) {
      final m = re.allMatches(s.name).lastOrNull;
      final n = m == null ? null : int.tryParse(m.group(1)!);
      if (n != null && n > max) max = n;
    }
    return (max == 0 ? _sprints.length : max) + 1;
  }

  Future<void> _createSprint() async {
    final lastEnd = _sprints
        .map((s) => s.endDate)
        .whereType<DateTime>()
        .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
    final data = await showCreateSprintDialog(
      context,
      nextNumber: _nextSprintNumber(),
      defaultStart: lastEnd?.add(const Duration(days: 3)),
    );
    if (data == null) return;
    try {
      await _sprintApi.createSprint(
        boardId: _board.id,
        name: data.name,
        goal: data.goal,
        startDate: data.start,
        endDate: data.end,
      );
      _toastKey(
        'sprint.toast.created',
        vars: {'name': data.name},
        kind: GlassToastKind.success,
      );
      await _loadAll();
    } on ApiFailure catch (failure) {
      _toastKey(failure.message, kind: GlassToastKind.error);
    }
  }

  Future<void> _startSprint(Sprint sprint) async {
    final issues = _bySprint[sprint.id] ?? const [];
    final data = await showStartSprintDialog(
      context,
      sprintName: sprint.name,
      initialGoal: sprint.goal,
      start: sprint.startDate ?? DateTime.now(),
      issueCount: issues.length,
      committedPoints: sumPoints(issues),
      capacityPoints: sprint.capacityPoints,
    );
    if (data == null) return;
    try {
      await _sprintApi.startSprint(
        sprint.id,
        goal: data.goal,
        endDate: data.endDate,
      );
      _activeSprintId = sprint.id;
      _report = null;
      _toastKey(
        'sprint.toast.started',
        vars: {'name': sprint.name},
        kind: GlassToastKind.success,
      );
      if (mounted) setState(() => _tab = _Tab.active);
      await _loadAll();
    } on ApiFailure catch (failure) {
      _toastKey(failure.message, kind: GlassToastKind.error);
    }
  }

  Future<void> _completeSprint(Sprint sprint) async {
    final issues = _bySprint[sprint.id] ?? const [];
    final done = issues.where((i) => i.resolved).toList();
    final open = issues.where((i) => !i.resolved).toList();
    final dest = await showCompleteSprintDialog(
      context,
      sprintName: sprint.name,
      doneCount: done.length,
      donePoints: sumPoints(done),
      openCount: open.length,
      openPoints: sumPoints(open),
      plannedDestinations: _plannedSprints,
    );
    if (dest == null) return;
    try {
      await _sprintApi.completeSprint(sprint.id, moveOpenTo: dest);
      if (_activeSprintId == sprint.id) _activeSprintId = null;
      _report = null;
      _toastKey(
        'sprint.toast.completed',
        vars: {'name': sprint.name},
        kind: GlassToastKind.success,
      );
      if (mounted) setState(() => _tab = _Tab.planning);
      await _loadAll();
    } on ApiFailure catch (failure) {
      _toastKey(failure.message, kind: GlassToastKind.error);
    }
  }

  // ── build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading && _sprints.isEmpty && _error == null) {
      return const Center(child: HiveLoader());
    }
    if (_error != null && _sprints.isEmpty) {
      return _ErrorRetry(message: context.t(_error!), onRetry: _loadAll);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            context.pageGutter,
            18 + context.topGutter,
            context.pageGutter,
            10,
          ),
          child: _tabBar(),
        ),
        Expanded(child: _surface()),
      ],
    );
  }

  Widget _tabBar() {
    final compact = context.isCompact;
    // Labels are hidden on phones (icons only) to leave room for the filter;
    // the shared control moves them into tooltips when it does that.
    final switcher = SegmentedControl(
      iconsOnly: compact,
      items: [
        SegmentItem(
          icon: LucideIcons.listChecks,
          label: context.t('sprint.tab.planning'),
        ),
        SegmentItem(
          icon: LucideIcons.columns3,
          label: context.t('sprint.tab.active'),
        ),
        SegmentItem(
          icon: LucideIcons.chartLine,
          label: context.t('sprint.tab.insights'),
        ),
      ],
      selected: _tab.index,
      onChanged: (i) {
        setState(() => _tab = _Tab.values[i]);
        if (_tab == _Tab.insights && _report == null) _loadReport();
      },
    );

    // The filter applies to Planning + Active sprint (not Insights). The
    // people strip only appears on wide layouts (plenty of room); narrower
    // screens rely on the filter popup's assignee facet.
    final showFilter = _tab != _Tab.insights;
    final showPeople = context.isExpanded && _peopleIds.isNotEmpty;
    // A right-aligned cluster: the Expanded fills the space after the switcher
    // and the Align pins the people strip + filter button flush right.
    return Row(
      children: [
        switcher,
        Expanded(
          child: !showFilter
              ? const SizedBox.shrink()
              : Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showPeople) ...[
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 360),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            reverse: true,
                            child: BoardPeopleStrip(
                              userIds: _peopleIds,
                              names: widget.names,
                              avatars: widget.avatars,
                              selected: _filter.assignees,
                              onToggle: (id) => setState(
                                () => _filter = _filter.toggle(
                                  BoardFilterFacet.assignee,
                                  id,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      // Grouping applies to the active-sprint board only.
                      if (_tab == _Tab.active) ...[
                        BoardGroupByButton(
                          value: _grouping,
                          compact: compact,
                          options: boardGroupingsFor(
                            crossProject:
                                widget.view.board.projectIds.length > 1,
                          ),
                          onChanged: (g) => setState(() => _grouping = g),
                        ),
                        const SizedBox(width: 10),
                      ],
                      _SprintFilterButton(
                        key: _filterKey,
                        count: _filter.activeCount,
                        compact: compact,
                        onTap: _openFilter,
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _surface() {
    switch (_tab) {
      case _Tab.planning:
        return SprintPlanningSurface(
          sprints: _planningSprints,
          activeSprintId: _activeSprintId,
          issuesBySprint: _bySprint,
          filter: _filter,
          backlog: _backlog,
          backlogTotal: _backlogTotal,
          backlogPage: _backlogPage,
          backlogPages: _backlogPages,
          pageSize: kBacklogPageSize,
          selected: _selected,
          query: _query,
          onQuery: (q) {
            setState(() {
              _query = q;
              _backlogPage = 0;
            });
            _reloadBacklogOnly();
          },
          onPage: (p) {
            setState(() => _backlogPage = p);
            _reloadBacklogOnly();
          },
          onToggleSelect: (id) => setState(() {
            _selected.contains(id) ? _selected.remove(id) : _selected.add(id);
          }),
          onClearSelection: () => setState(_selected.clear),
          onOpenIssue: widget.onOpenIssue,
          onEstimate: _estimate,
          onMoveToSprint: _moveIssueToSprint,
          onBulkMove: _bulkMove,
          onAddIssue: _addIssue,
          onCreateSprint: _createSprint,
          onStartSprint: _startSprint,
          onCompleteSprint: _completeSprint,
        );
      case _Tab.active:
        final sprint = _activeSprint;
        if (sprint == null) {
          return _EmptyState(
            icon: LucideIcons.zap,
            title: context.t('sprint.noActive'),
            subtitle: context.t('sprint.noActiveSub'),
          );
        }
        return SprintActiveSurface(
          sprint: sprint,
          columns: widget.view.columns,
          issues: _activeBoardIssues,
          filter: _filter,
          grouping: _grouping,
          issuesById: _issuesById,
          epics: _epics,
          names: widget.names,
          avatars: widget.avatars,
          projectNames: widget.projectNames,
          projectsById: widget.projectsById,
          onOpenIssue: widget.onOpenIssue,
          onMoveState: _moveIssueState,
        );
      case _Tab.insights:
        final sprint = _activeSprint;
        if (sprint == null) {
          return _EmptyState(
            icon: LucideIcons.chartLine,
            title: context.t('sprint.noActive'),
            subtitle: context.t('sprint.noInsights'),
          );
        }
        return SprintInsightsSurface(
          report: _report,
          loading: _reportLoading,
          error: _reportError == null ? null : context.t(_reportError!),
          names: widget.names,
          onRetry: _loadReport,
        );
    }
  }
}

/// White pill that opens the glass filter popup; shows an amber count badge.
/// Collapses to an icon-only button on phones.
class _SprintFilterButton extends StatelessWidget {
  const _SprintFilterButton({
    super.key,
    required this.count,
    required this.compact,
    required this.onTap,
  });

  final int count;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = count > 0;
    final button = Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 11 : 14,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            border: Border.all(
              color: active ? AppColors.accentLine : AppColors.hairline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.slidersHorizontal,
                size: 16,
                color: AppColors.inkSoft,
              ),
              if (!compact) ...[
                const SizedBox(width: 7),
                Text(
                  context.t('board.filterButton'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (active) ...[
                const SizedBox(width: 7),
                Container(
                  constraints: const BoxConstraints(minWidth: 18),
                  height: 18,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: const BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2A2410),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    // Only where the label is gone — a tooltip repeating visible text is noise.
    return compact
        ? Tooltip(message: context.t('board.filterButton'), child: button)
        : button;
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(context.pageGutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.inkFaint),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                fontFamily: AppTheme.fontBrand,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onRetry,
            child: Text(context.t('common.retry')),
          ),
        ],
      ),
    );
  }
}
