import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hinata/features/shell/app_shell.dart'
    show kNavGlassDark, kNavGlassLight, isNativeApp;
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassContainer, LiquidRoundedSuperellipse, LiquidOval;
import 'package:liquid_glass_widgets/widgets/interactive/glass_button.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../core/blocs/app_config_bloc.dart';
import '../../core/blocs/auth_bloc.dart';
import '../../core/blocs/paged_cubit.dart';
import '../../core/events/issue_events.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/core_models.dart';
import '../../core/models/work_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/project_palette.dart';
import '../../core/util/file_download.dart';
import '../../core/widgets/frosted_surface.dart';
import '../../core/widgets/glass_bulk_bar.dart';
import '../../core/widgets/glass_popup_menu.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/hive_widgets.dart';
import '../../core/widgets/subtask_widgets.dart';
import '../../core/widgets/soft_card.dart';
import '../../core/widgets/status_widgets.dart';
import '../sprint/modals/glass_modal.dart'
    show GlassToastKind, showGlassToast, showGlassDateRangePicker;
import '../reports/logo_raster.dart';
import '../shell/page_chrome.dart';
import 'issue_detail_sheet.dart';
import 'issue_export.dart';
import 'issue_filter.dart';
import 'issue_filter_popup.dart';
import 'issue_form.dart';
import 'issue_move_wizard.dart';
import '../../core/repositories/issue_repository.dart';
import '../../core/repositories/meta_repository.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/repositories/user_repository.dart';

part 'issues_screen.toolbar.dart';
part 'issues_screen.rows.dart';

/// Shared lookup data for rendering issue rows — loaded once alongside the
/// paginated issue stream (users → names/avatars, projects → names/palette and
/// the unioned workflow-state order for status grouping).
typedef _RefData = ({
  Map<String, String> names,
  Map<String, String> avatars,
  Map<String, String> projectNames,
  List<String> stateOrder,
  ProjectPalette palette,
});

class IssuesScreen extends StatefulWidget {
  const IssuesScreen({
    super.key,
    this.projectId,
    this.initialView,
    this.scopeProjectIds = const [],
  });

  final String? projectId;

  /// Optional preset the screen opens pre-filtered on (dashboard KPI deep-link).
  final IssuesInitialView? initialView;

  /// Project scope carried from the dashboard so a KPI deep-link reproduces the
  /// same project selection the card was counted with. Empty ⇒ all projects.
  final List<String> scopeProjectIds;

  @override
  State<IssuesScreen> createState() => _IssuesScreenState();
}

class _IssuesScreenState extends State<IssuesScreen> {
  /// Empty lookups so rows can still render if reference data fails to load
  /// (names fall back to ids) without blocking the issue list.
  static final _RefData _emptyRef = (
    names: const {},
    avatars: const {},
    projectNames: const {},
    stateOrder: const [],
    palette: ProjectPalette.empty,
  );

  static const int _pageSize = 100;

  late final PagedCubit<Issue> _issues;
  final ScrollController _scroll = ScrollController();

  // Reference data (users + projects), loaded once in parallel with page 0.
  _RefData? _ref;
  bool _refLoading = true;
  bool _refError = false;

  // Guards the "export everything" flow so the menu can't fire twice.
  bool _exporting = false;

  /// Multi-select for bulk actions (currently: move to another project).
  /// Entered by long-pressing a row — the same gesture the comment thread uses
  /// — after which a plain tap toggles instead of opening the issue.
  final Set<String> _selectedIds = {};
  bool _selectionMode = false;

  void _enterSelection(String issueId) => setState(() {
    _selectionMode = true;
    _selectedIds.add(issueId);
  });

  void _toggleSelection(String issueId) => setState(() {
    if (!_selectedIds.remove(issueId)) _selectedIds.add(issueId);
    // Deselecting the last row leaves selection mode, so a stray long-press
    // never strands the list with no way out but the ✕.
    if (_selectedIds.isEmpty) _selectionMode = false;
  });

  void _exitSelection() => setState(() {
    _selectionMode = false;
    _selectedIds.clear();
  });

  /// Bulk-moves the selected issues. The wizard asks for the target project and
  /// the status mapping once for the whole set.
  Future<void> _moveSelected() async {
    if (_selectedIds.isEmpty) return;
    // A selection may span projects (the unscoped list shows all of them); only
    // a single-project selection can pre-exclude its own project as a target.
    final projectIds = {
      for (final issue in _issues.state.items)
        if (_selectedIds.contains(issue.id)) issue.projectId,
    };
    final moved = await showIssueMoveWizard(
      context,
      issueIds: _selectedIds.toList(),
      currentProjectId: projectIds.length == 1 ? projectIds.first : null,
    );
    if (moved != true || !mounted) return;
    _exitSelection();
    await _reload();
  }

  IssueFilter _filter = IssueFilter.empty;
  IssueGrouping _grouping = IssueGrouping.none;
  IssueTimeRange _timeRange = IssueTimeRange.none;

  /// Server-side ordering. Changing it refetches from page 0 so the order is
  /// correct across the whole result set, not just the loaded pages.
  IssueSort _sort = IssueSort.defaultSort;

  // Memoized filter/section sweep. While a filter is active the screen pulls
  // every backend page in the background, and each intermediate rebuild would
  // otherwise re-run the full _filtered/_sections over the whole growing list.
  // These cache the last result keyed on the exact inputs, so a rebuild with
  // unchanged (loaded set + filter/time/grouping/ref) reuses it instead.
  List<Issue>? _viewAll;
  Object? _viewRef;
  IssueFilter? _viewFilter;
  IssueTimeRange? _viewTimeRange;
  IssueGrouping? _viewGrouping;
  List<Issue> _viewList = const [];
  List<_Section> _viewSections = const [];

  /// The deep-link preset is applied once, after projects load (so bucket
  /// presets can resolve to real state names); later refreshes keep the user's
  /// own filter choices.
  bool _initialViewApplied = false;

  /// Group keys currently collapsed in the grouped view (mirrors the board's
  /// swimlane collapse). Cleared whenever the grouping dimension changes.
  final Set<String> _collapsed = {};

  final GlobalKey _filterKey = GlobalKey();

  /// Re-fetch when an issue is created/changed elsewhere (e.g. the global
  /// nav-rail "new issue" button, which can't reach this screen's cubit).
  StreamSubscription<void>? _issueSub;

  @override
  void initState() {
    super.initState();
    _issueSub = IssueEvents.instance.changes.listen((_) => _reload());
    _issues = PagedCubit<Issue>(
      (page, size) async {
        final result = await context.read<IssueRepository>().issues(
          projectId: widget.projectId,
          archived: _filter.archivedOnly,
          states: _serverStates,
          priorities: _serverPriorities,
          types: _serverTypes,
          assigneeIds: _serverAssignees,
          sort: _sort.wire,
          page: page,
          size: size,
        );
        return (items: result.issues, total: result.total);
      },
      pageSize: _pageSize,
      keyOf: (i) => i.id,
    )..load();
    _scroll.addListener(_onScroll);
    _loadRef();
  }

  @override
  void dispose() {
    _issueSub?.cancel();
    _scroll.dispose();
    _issues.close();
    super.dispose();
  }

  /// Loads users + projects into [_ref]. Best-effort: a failure leaves rows to
  /// render with id fallbacks rather than blocking the whole screen.
  Future<void> _loadRef() async {
    if (mounted) {
      setState(() {
        _refLoading = true;
        _refError = false;
      });
    }
    try {
      final results = await Future.wait([
        context.read<UserRepository>().users(),
        context.read<ProjectRepository>().projects(),
      ]);
      final users = results[0] as List<DirectoryUser>;
      final projects = results[1] as List<Project>;
      // Workflow-state order (UPPER-CASE), unioned across projects in first-seen
      // order, so status grouping lists columns the way the projects define them.
      final stateOrder = <String>[];
      final seenStates = <String>{};
      for (final p in projects) {
        for (final name in p.stateNames) {
          final code = name.toUpperCase();
          if (seenStates.add(code)) stateOrder.add(code);
        }
      }
      if (!mounted) return;
      setState(() {
        _ref = (
          names: {for (final u in users) u.id: u.displayName},
          avatars: {
            for (final u in users)
              if (u.avatarUrl != null && u.avatarUrl!.isNotEmpty)
                u.id: u.avatarUrl!,
          },
          projectNames: {for (final p in projects) p.id: p.name},
          stateOrder: stateOrder,
          palette: ProjectPalette.fromProjects(projects),
        );
        _refLoading = false;
        // Apply a dashboard deep-link preset once, now that we know the
        // projects' workflow/resolved states.
        if (!_initialViewApplied && widget.initialView != null) {
          _applyInitialView(widget.initialView!, projects);
          _initialViewApplied = true;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _refLoading = false;
        _refError = true;
      });
    }
  }

  /// Translates a dashboard KPI deep-link preset into the concrete filter/time
  /// range. Bucket presets use the same rule as the dashboard's server-side
  /// completion split: done = the projects' resolved states, backlog =
  /// `Backlog`/`Open`, in-progress = everything else.
  void _applyInitialView(IssuesInitialView view, List<Project> projects) {
    // Each preset fully defines the view — start from a clean slate so nothing
    // from a previous state (filter or time range) leaks in.
    _filter = IssueFilter.empty;
    _timeRange = IssueTimeRange.none;
    // The dashboard's project scope (if any) applies to every preset so the
    // filtered list reproduces exactly what the KPI card counted.
    final scope = widget.scopeProjectIds.toSet();
    if (view == IssuesInitialView.today) {
      // "Today's tasks" = my open issues due today or overdue — the exact set the
      // dashboard KPI counts, so the filtered list length matches the card.
      final me = context.read<AuthBloc>().state.user?.id;
      _filter = IssueFilter(
        assignees: me == null ? const {} : {me},
        projects: scope,
      );
      _timeRange = const IssueTimeRange(preset: IssueTimePreset.dueByToday);
      return;
    }
    final done = <String>{};
    final all = <String>{};
    for (final p in projects) {
      for (final name in p.resolvedStates) {
        done.add(name.toUpperCase());
      }
      for (final name in p.stateNames) {
        all.add(name.toUpperCase());
      }
    }
    const backlog = {'BACKLOG', 'OPEN'};
    final states = switch (view) {
      IssuesInitialView.done => done,
      IssuesInitialView.backlog => all.intersection(backlog),
      IssuesInitialView.inProgress => all.difference(done).difference(backlog),
      IssuesInitialView.today => const <String>{},
    };
    _filter = IssueFilter(states: states, projects: scope);
  }

  /// Pull-to-refresh / retry: reload the first page and the reference data.
  Future<void> _reload() => Future.wait([_issues.load(), _loadRef()]);

  /// Infinite scroll: pull the next page as the user nears the bottom. The
  /// cubit guards against overlapping or past-the-end requests.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 600) {
      _issues.loadMore();
    }
  }

  // ── filtering / sorting ────────────────────────────────────────────────

  /// Applies the active filter + time-range to the loaded pages. Ordering is
  /// intentionally left to the backend (the `?sort=` param, see [_sort]) so it
  /// holds across the whole paginated result set — re-sorting here would only
  /// reorder the pages currently in memory and fight the server order.
  List<Issue> _filtered(List<Issue> issues) =>
      issues.where((i) => _filter.matches(i) && _timeRange.matches(i)).toList();

  /// Returns the filtered list + grouped sections for [all]/[ref], reusing the
  /// last computation when every input is unchanged. Cheap references — during
  /// the background page sweep `all` is a new list each page (so it correctly
  /// recomputes), but the many other rebuilds (SSE on peers, keyboard, theme)
  /// hit the cache instead of re-sweeping the whole accumulated set.
  ({List<Issue> list, List<_Section> sections}) _view(
    List<Issue> all,
    _RefData ref,
  ) {
    if (identical(all, _viewAll) &&
        identical(ref, _viewRef) &&
        identical(_filter, _viewFilter) &&
        identical(_timeRange, _viewTimeRange) &&
        _grouping == _viewGrouping) {
      return (list: _viewList, sections: _viewSections);
    }
    final list = _filtered(all);
    final sections = _sections(list, ref);
    _viewAll = all;
    _viewRef = ref;
    _viewFilter = _filter;
    _viewTimeRange = _timeRange;
    _viewGrouping = _grouping;
    _viewList = list;
    _viewSections = sections;
    return (list: list, sections: sections);
  }

  // ── grouping ──────────────────────────────────────────────────────────

  /// Buckets [list] into ordered sections for the active grouping. Returns an
  /// empty list when grouping is off (the caller renders a flat list instead).
  List<_Section> _sections(List<Issue> list, _RefData data) {
    if (_grouping == IssueGrouping.none) return const [];
    final buckets = <String, List<Issue>>{};
    String keyOf(Issue i) => switch (_grouping) {
      IssueGrouping.state => i.state.toUpperCase(),
      IssueGrouping.priority => i.priority.toUpperCase(),
      IssueGrouping.assignee =>
        (i.assigneeId?.isNotEmpty ?? false) ? i.assigneeId! : _kNone,
      IssueGrouping.project => i.projectId,
      IssueGrouping.type => i.type.toUpperCase(),
      IssueGrouping.none => '',
    };
    for (final issue in list) {
      buckets.putIfAbsent(keyOf(issue), () => []).add(issue);
    }
    final keys = buckets.keys.toList()..sort(_keyComparator(data));
    return [
      for (final k in keys)
        _Section(
          key: k,
          header: _groupHeader(k, buckets[k]!.length, data),
          issues: buckets[k]!,
        ),
    ];
  }

  int Function(String, String) _keyComparator(_RefData data) {
    switch (_grouping) {
      case IssueGrouping.state:
        return (a, b) {
          final ia = data.stateOrder.indexOf(a);
          final ib = data.stateOrder.indexOf(b);
          final ra = ia == -1 ? data.stateOrder.length : ia;
          final rb = ib == -1 ? data.stateOrder.length : ib;
          return ra != rb ? ra.compareTo(rb) : a.compareTo(b);
        };
      case IssueGrouping.priority:
        // Backend codes (see [kIssuePriorityCodes]) with the legacy aliases
        // interleaved at the matching severity, so old data still groups right.
        const order = [
          'SHOWSTOPPER',
          'CRITICAL',
          'URGENT',
          'MAJOR',
          'HIGH',
          'NORMAL',
          'MINOR',
          'LOW',
          'TRIVIAL',
        ];
        return (a, b) => _rankIn(order, a).compareTo(_rankIn(order, b));
      case IssueGrouping.type:
        const order = ['EPIC', 'STORY', 'TASK', 'BUG', 'FEATURE', 'SUBTASK'];
        return (a, b) => _rankIn(order, a).compareTo(_rankIn(order, b));
      case IssueGrouping.assignee:
        return (a, b) {
          if (a == _kNone) return 1;
          if (b == _kNone) return -1;
          return (data.names[a] ?? a).toLowerCase().compareTo(
            (data.names[b] ?? b).toLowerCase(),
          );
        };
      case IssueGrouping.project:
        return (a, b) => (data.projectNames[a] ?? a).toLowerCase().compareTo(
          (data.projectNames[b] ?? b).toLowerCase(),
        );
      case IssueGrouping.none:
        return (a, b) => 0;
    }
  }

  Widget _groupHeader(String key, int count, _RefData data) {
    Widget leading;
    String label;
    switch (_grouping) {
      case IssueGrouping.state:
        leading = _Dot(color: data.palette.stateColor(key));
        label = stateLabel(key);
      case IssueGrouping.priority:
        leading = PriorityFlag(priority: key);
        label = _enumLabel(context, 'priority', key);
      case IssueGrouping.type:
        leading = TypeGlyph(type: key, size: 18);
        label = _enumLabel(context, 'type', key);
      case IssueGrouping.assignee:
        if (key == _kNone) {
          leading = Icon(
            LucideIcons.userX,
            size: 18,
            color: AppColors.inkFaint,
          );
          label = context.t('issues.unassigned');
        } else {
          final name = data.names[key] ?? key;
          leading = HiveAvatar(
            name: name,
            imageUrl: data.avatars[key],
            size: 22,
          );
          label = name;
        }
      case IssueGrouping.project:
        leading = Icon(LucideIcons.folder, size: 17, color: AppColors.inkFaint);
        label = data.projectNames[key] ?? key;
      case IssueGrouping.none:
        leading = const SizedBox.shrink();
        label = '';
    }
    return _GroupHeader(leading: leading, label: label, count: count);
  }

  // ── actions ───────────────────────────────────────────────────────────

  void _openFilter(_RefData data) => openIssueFilter(
    context,
    anchorKey: _filterKey,
    filter: _filter,
    // Options come from reference data (all states/projects/users + the fixed
    // type/priority enums), not the loaded issues — the list is now
    // server-filtered, so deriving options from it would hide facet
    // values the current result page happens not to contain.
    options: IssueFilterOptions.reference(
      states: data.stateOrder,
      assignees: data.names.keys.toList(),
      projects: data.projectNames.keys.toList(),
    ),
    names: data.names,
    avatars: data.avatars,
    projectNames: data.projectNames,
    onChanged: (f) {
      // Facets the backend expresses (state/priority/type/assignee + archived)
      // change the server query, so the page cache must be refetched when the
      // server-query signature changes. Purely client-side facets (project /
      // time range / "unassigned") only need a rebuild.
      final before = _serverQuerySignature;
      setState(() => _filter = f);
      if (_serverQuerySignature != before) _issues.load();
    },
  );

  /// Opens the filter popup against the *current* loaded issues + reference
  /// data. Used as a stable callback for the pinned toolbar so its header
  /// delegate need not rebuild every time a new page loads (it reads the fresh
  /// data at tap time instead of closing over a build snapshot).
  void _openFilterCurrent() => _openFilter(_ref ?? _emptyRef);

  void _onGroupingChanged(IssueGrouping g) => setState(() {
    _grouping = g;
    _collapsed.clear();
  });

  /// Sort is server-side: change the order and refetch from page 0 so it
  /// applies to the whole result set, not just the loaded pages.
  void _onSortChanged(IssueSort s) {
    if (s == _sort) return;
    setState(() => _sort = s);
    _issues.load();
  }

  void _onTimeRangeChanged(IssueTimeRange r) => setState(() => _timeRange = r);

  /// Fixed height of the toolbar when docked into the app bar (compact).
  static const double _kDockedToolbarHeight = 56;

  /// The view-controls toolbar (group · sort · filter · time · export), built
  /// with the live state + stable callbacks. Docked into the app bar on compact
  /// (so it shares the bar's single glass blur — no separate band); rendered as
  /// a normal in-scroll row on wide.
  Widget _toolbar() => _Toolbar(
    grouping: _grouping,
    onGrouping: _onGroupingChanged,
    sort: _sort,
    onSort: _onSortChanged,
    filterCount: _filter.activeCount,
    filterKey: _filterKey,
    onFilter: _openFilterCurrent,
    timeRange: _timeRange,
    onTimeRange: _onTimeRangeChanged,
    onExport: _export,
    exporting: _exporting,
  );

  Future<void> _export(String format) async {
    if (_exporting) return;
    // Read inherited blocs / repositories before the first await to avoid using
    // context across async gaps.
    final cachedMeta = context.read<AppConfigBloc>().state.meta;
    final issueApi = context.read<IssueRepository>();
    final metaApi = context.read<MetaRepository>();
    setState(() => _exporting = true);
    try {
      // Export EVERY matching issue, not just the pages scrolled into view:
      // page through the whole backend result set first so the file is complete
      // regardless of how far the user has scrolled.
      final List<Issue> all;
      try {
        all = await issueApi.allIssues(
          projectId: widget.projectId,
          archived: _filter.archivedOnly,
          states: _serverStates,
          priorities: _serverPriorities,
          types: _serverTypes,
          assigneeIds: _serverAssignees,
          sort: _sort.wire,
        );
      } catch (_) {
        if (mounted) {
          _toast(context.t('reports.exportFailed'), kind: GlassToastKind.error);
        }
        return;
      }
      if (!mounted) return;
      final ref = _ref ?? _emptyRef;

      if (format == 'pdf') {
        ServerMeta? meta = cachedMeta;
        try {
          meta = await metaApi.meta();
        } catch (_) {
          meta = cachedMeta;
        }
        Uint8List? logoPng;
        try {
          final logoAsset = await metaApi.organizationLogo();
          if (logoAsset != null) {
            logoPng = await logoToPng(
              bytes: logoAsset.bytes,
              isSvg: logoAsset.isSvg,
            );
          }
        } catch (_) {
          logoPng = null;
        }
        if (!mounted) return;
        final failMsg = context.t('reports.exportFailed');
        try {
          await shareIssuesPdf(_buildExportData(ref, all, meta, logoPng));
        } catch (_) {
          _toast(failMsg, kind: GlassToastKind.error);
        }
        return;
      }

      final data = _buildExportData(ref, all, null, null);
      final isCsv = format == 'csv';
      final content = isCsv ? buildIssuesCsv(data) : buildIssuesJson(data);
      final mime = isCsv ? 'text/csv' : 'application/json';
      final exportedMsg = context.t(
        'reports.exported',
        variables: {'format': format.toUpperCase()},
      );
      final copiedMsg = context.t(
        'reports.copied',
        variables: {'format': format.toUpperCase()},
      );
      if (kIsWeb) {
        // Browsers block window.open() to a data: URL ("Not allowed to navigate
        // top frame to data URL"), so trigger a real Blob download instead —
        // and surface a proper error if it fails rather than a false success.
        final result = await downloadBytes(
          'issues-export.${isCsv ? 'csv' : 'json'}',
          Uint8List.fromList(utf8.encode(content)),
          mime,
        );
        if (!mounted) return;
        if (result.outcome == DownloadOutcome.failed) {
          _toast(context.t('reports.exportFailed'), kind: GlassToastKind.error);
        } else {
          _toast(exportedMsg, kind: GlassToastKind.success);
        }
      } else {
        await Clipboard.setData(ClipboardData(text: content));
        _toast(copiedMsg, kind: GlassToastKind.success);
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  IssueExportData _buildExportData(
    _RefData ref,
    List<Issue> allIssues,
    ServerMeta? meta,
    Uint8List? logoPng,
  ) {
    final list = _filtered(allIssues);
    final names = ref.names;
    final projectNames = ref.projectNames;

    IssueExportRow rowOf(Issue i) => (
      id: i.readableId,
      title: i.title,
      status: stateLabel(i.state),
      priority: _enumLabel(context, 'priority', i.priority.toUpperCase()),
      assignee: (i.assigneeId?.isNotEmpty ?? false)
          ? (names[i.assigneeId] ?? i.assigneeId!)
          : context.t('issues.unassigned'),
      project: projectNames[i.projectId] ?? i.projectId,
      type: _enumLabel(context, 'type', i.type.toUpperCase()),
      due: i.dueDate?.toIso8601String().substring(0, 10) ?? '',
    );

    final grouped = _grouping != IssueGrouping.none;
    final List<IssueExportGroup> groups;
    if (grouped) {
      groups = [
        for (final s in _sections(list, ref))
          (
            title: _sectionLabel(s.key, ref),
            rows: [for (final i in s.issues) rowOf(i)],
          ),
      ];
    } else {
      groups = [
        (title: '', rows: [for (final i in list) rowOf(i)]),
      ];
    }

    final scope = widget.projectId != null
        ? (projectNames[widget.projectId] ?? context.t('nav.issues'))
        : context.t('board.allProjects');

    return IssueExportData(
      orgName: (meta?.organizationName?.trim().isNotEmpty ?? false)
          ? meta!.organizationName!.trim()
          : 'Hinata',
      logoBytes: logoPng,
      scopeLabel: scope,
      generatedAt: DateTime.now(),
      locale: Localizations.localeOf(context).toString(),
      groups: groups,
      grouped: grouped,
      groupByLabel: grouped
          ? '${context.t('board.groupBy')}: ${_groupingLabel(context, _grouping)}'
          : null,
      filterSummary: _filterSummary(names, projectNames),
      labels: (
        reportTitle: context.t('reports.issuesReport'),
        issuesCount: context.t(
          'issues.countSummary',
          variables: {'count': '${list.length}'},
        ),
        generatedPrefix: context.t('reports.generatedPrefix'),
        pageLabel: context.t('reports.page'),
        colId: context.t('issues.colId'),
        colTitle: context.t('issues.colTitle'),
        colStatus: context.t('issues.colStatus'),
        colPriority: context.t('issues.colPriority'),
        colAssignee: context.t('issues.colAssignee'),
        colDue: context.t('issues.colDue'),
      ),
    );
  }

  /// A plain-text label for a group key (no widgets) — used by the PDF/CSV/JSON
  /// export, which can't render header widgets.
  String _sectionLabel(String key, _RefData data) => switch (_grouping) {
    IssueGrouping.state => stateLabel(key),
    IssueGrouping.priority => _enumLabel(context, 'priority', key),
    IssueGrouping.type => _enumLabel(context, 'type', key),
    IssueGrouping.assignee =>
      key == _kNone ? context.t('issues.unassigned') : (data.names[key] ?? key),
    IssueGrouping.project => data.projectNames[key] ?? key,
    IssueGrouping.none => '',
  };

  List<String> _filterSummary(
    Map<String, String> names,
    Map<String, String> projectNames,
  ) {
    final out = <String>[];
    String join(String prefix, Iterable<String> values) =>
        '$prefix: ${values.join(', ')}';
    if (_filter.states.isNotEmpty) {
      out.add(
        join(context.t('issues.colStatus'), _filter.states.map(stateLabel)),
      );
    }
    if (_filter.priorities.isNotEmpty) {
      out.add(
        join(
          context.t('issues.colPriority'),
          _filter.priorities.map((p) => _enumLabel(context, 'priority', p)),
        ),
      );
    }
    if (_filter.types.isNotEmpty) {
      out.add(
        join(
          context.t('issues.type'),
          _filter.types.map((t) => _enumLabel(context, 'type', t)),
        ),
      );
    }
    if (_filter.assignees.isNotEmpty) {
      out.add(
        join(
          context.t('issues.colAssignee'),
          _filter.assignees.map(
            (a) => a == IssueFilter.noAssignee
                ? context.t('issues.unassigned')
                : (names[a] ?? a),
          ),
        ),
      );
    }
    if (_filter.projects.isNotEmpty) {
      out.add(
        join(
          context.t('issues.project'),
          _filter.projects.map((p) => projectNames[p] ?? p),
        ),
      );
    }
    if (_filter.archivedOnly) {
      out.add(context.t('issues.filterArchived'));
    }
    if (_timeRange.isActive) {
      out.add(
        '${context.t('issues.timeRange')}: ${_timeLabel(context, _timeRange)}',
      );
    }
    return out;
  }

  void _toast(String message, {GlassToastKind kind = GlassToastKind.info}) {
    if (!mounted) return;
    showGlassToast(context, context.t(message), kind: kind);
  }

  // ── build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PagedCubit<Issue>, PagedState<Issue>>(
      bloc: _issues,
      builder: (context, state) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        final ref = _ref ?? _emptyRef;
        final all = state.items;
        final view = _view(all, ref);
        final list = view.list;
        final sections = view.sections;

        // Project-scoped view: surface which project is open — the project
        // name becomes the page title (and the shell app-bar title via
        // PageChrome), with the generic "Issues" label demoted to the
        // subtitle. Falls back to "Issues" while reference data loads.
        final projectName = widget.projectId != null
            ? ref.projectNames[widget.projectId]
            : null;

        // State/priority/type/assignee facets are now applied by the backend
        // so the returned pages are already reduced and normal paged
        // scroll suffices. Only the residual client-side facets (multi-project,
        // time range, "unassigned") still filter the loaded pages, so we eagerly
        // pull the remaining (already server-reduced) pages ONLY then —
        // otherwise a match beyond the first page would never surface.
        if (_hasClientResidual && state.hasMore && !state.isLoadingMore) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _issues.loadMore();
          });
        }

        // True while a residual client-side filter is still pulling pages but has
        // matched nothing yet — show a spinner instead of a premature "no results".
        final searchingMore =
            list.isEmpty &&
            (state.isLoadingMore || (_hasClientResidual && state.hasMore));

        final compact = context.isCompact;
        return PageChrome(
          title: projectName ?? context.t('nav.issues'),
          // On compact the toolbar docks into the app bar (shared blur, no
          // separate band); on wide it stays an in-scroll row below the title.
          bottom: compact
              ? Padding(
                  padding: EdgeInsets.symmetric(horizontal: context.pageGutter),
                  child: Center(child: _toolbar()),
                )
              : null,
          bottomHeight: compact ? _kDockedToolbarHeight : 0,
          child: Stack(
            children: [
              RefreshIndicator(
                onRefresh: _reload,
                color: AppColors.accent,
                edgeOffset: context.topGutter,
                child: AsyncView(
                  isLoading:
                      state.isLoading ||
                      (_refLoading && _ref == null && !_refError),
                  hasData: state.hasData && (_ref != null || _refError),
                  errorKey: state.errorKey,
                  onRetry: _reload,
                  builder: (context) => CustomScrollView(
                    controller: _scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          context.pageGutter,
                          // topGutter now includes the docked toolbar height on
                          // compact, so content clears the whole (taller) app bar.
                          24 + context.topGutter,
                          context.pageGutter,
                          14,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: PageHead(
                            title: projectName ?? context.t('nav.issues'),
                            subtitle: projectName != null
                                ? '${context.t('nav.issues')} · ${_subtitle(list.length, state.total)}'
                                : _subtitle(list.length, state.total),
                            actions: [
                              !isNativeApp
                                  ? PrimaryButton(
                                      label: context.t('issues.new'),
                                      collapseToIcon: true,
                                      onPressed: () async {
                                        final created = await showIssueForm(
                                          context,
                                          projectId: widget.projectId,
                                        );
                                        if (created != null && mounted) {
                                          _reload();
                                        }
                                      },
                                    )
                                  : Tooltip(
                                      message: context.t('issues.new'),
                                      child: GlassButton.custom(
                                        onTap: () async {
                                          final created = await showIssueForm(
                                            context,
                                            projectId: widget.projectId,
                                          );
                                          if (created != null && mounted) {
                                            _reload();
                                          }
                                        },
                                        width: context.isCompact ? 46 : null,
                                        height: 46,
                                        shape: !context.isCompact
                                            ? const LiquidRoundedSuperellipse(
                                                borderRadius: 15,
                                              )
                                            : const LiquidOval(),
                                        useOwnLayer: true,
                                        settings: dark
                                            ? kNavGlassDark
                                            : kNavGlassLight,
                                        glowColor: AppColors.accent,
                                        stretch: 0.15,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 8,
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              Icon(
                                                LucideIcons.plus,
                                                size: 18,
                                                color: dark
                                                    ? AppColors.inkDark
                                                    : AppColors.ink,
                                              ),
                                              if (!context.isCompact) ...[
                                                const SizedBox(width: 4),
                                                Text(
                                                  context.t('issues.new'),
                                                  style: TextStyle(
                                                    fontFamily:
                                                        AppTheme.fontBrand,
                                                    fontSize: 17,
                                                    fontWeight: FontWeight.w700,
                                                    letterSpacing: -0.3,
                                                    color: dark
                                                        ? AppColors.inkDark
                                                        : AppColors.ink,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                            ],
                          ),
                        ),
                      ),
                      // Toolbar (group · sort · filter · time · export). On compact
                      // it lives in the app bar (see PageChrome.bottom above); on
                      // wide it's an in-scroll row below the title.
                      if (!compact)
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            context.pageGutter,
                            0,
                            context.pageGutter,
                            14,
                          ),
                          sliver: SliverToBoxAdapter(child: _toolbar()),
                        ),
                      if (list.isEmpty && !searchingMore)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: context.pageGutter,
                              vertical: 40,
                            ),
                            child: HiveEmptyState(
                              title: context.t('nav.issues'),
                              message: _hasActiveView
                                  ? context.t('issues.emptyFiltered')
                                  : context.t('issues.empty'),
                              action: _hasActiveView
                                  ? OutlinedButton(
                                      onPressed: () {
                                        final refetch = _filter.archivedOnly;
                                        setState(() {
                                          _filter = IssueFilter.empty;
                                          _timeRange = IssueTimeRange.none;
                                        });
                                        if (refetch) _issues.load();
                                      },
                                      child: Text(
                                        context.t('board.clearFilters'),
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                        )
                      else if (list.isNotEmpty)
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            context.pageGutter,
                            12,
                            context.pageGutter,
                            14,
                          ),
                          sliver: Builder(
                            builder: (context) {
                              // Lightweight row descriptors (headers / issues /
                              // spacers) fed to a lazy builder, so only on-screen
                              // rows are ever built — a workspace with thousands of
                              // issues no longer constructs every SoftCard per frame.
                              final entries = _grouping == IssueGrouping.none
                                  ? _flatEntries(list)
                                  : _groupedEntries(sections);
                              return SliverList.builder(
                                itemCount: entries.length,
                                itemBuilder: (context, i) => _buildEntry(
                                  entries[i],
                                  ref.names,
                                  ref.avatars,
                                  ref.palette,
                                ),
                              );
                            },
                          ),
                        ),
                      // Infinite-scroll footer: the standard HiveLoader while the next
                      // page (or a filter's background sweep) is loading.
                      if (state.isLoadingMore || searchingMore)
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(child: HiveLoader(size: 30)),
                          ),
                        ),
                      SliverToBoxAdapter(
                        child: SizedBox(
                          // Extra room while selecting so the floating bulk bar
                          // never covers the last row.
                          height:
                              context.pageGutter +
                              context.bottomGutter +
                              (_selectionMode ? 72 : 0),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Bulk-action bar, docked above the nav while rows are selected.
              if (_selectionMode)
                Positioned(
                  left: context.pageGutter,
                  right: context.pageGutter,
                  bottom: context.bottomGutter + 12,
                  child: Center(
                    child: GlassBulkBar(
                      countLabel: context.t(
                        'issues.selectedCount',
                        variables: {'count': '${_selectedIds.length}'},
                      ),
                      onClear: _exitSelection,
                      actions: [
                        GlassBulkAction(
                          icon: LucideIcons.folderInput,
                          label: context.t('issues.move.action'),
                          onTap: _moveSelected,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  bool get _hasActiveView => !_filter.isEmpty || _timeRange.isActive;

  // ── server-pushed facets ──────────────────────────────────────────
  // The backend expresses state/priority/type/assignee directly, so a filtered
  // page comes back already reduced and we no longer drain every page for them.

  List<String>? get _serverStates =>
      _filter.states.isEmpty ? null : _filter.states.toList();
  List<String>? get _serverPriorities =>
      _filter.priorities.isEmpty ? null : _filter.priorities.toList();
  List<String>? get _serverTypes =>
      _filter.types.isEmpty ? null : _filter.types.toList();

  /// Assignee ids are server-pushable only when the "unassigned" sentinel is not
  /// among them — the backend `$in` can't also express "has no assignee", so
  /// that case falls back to client-side filtering (and paging).
  List<String>? get _serverAssignees =>
      (_filter.assignees.isEmpty ||
          _filter.assignees.contains(IssueFilter.noAssignee))
      ? null
      : _filter.assignees.toList();

  /// Facets that still run client-side ([_filtered]) because the backend can't
  /// express them: the multi-project facet, the schedule-aware time range, and
  /// the "unassigned" sentinel. While any is active a server page may still be
  /// reduced locally, so we page the (already server-reduced) result set to keep
  /// the filtered list complete — the same behaviour as before, over far less
  /// data.
  bool get _hasClientResidual =>
      _filter.projects.isNotEmpty ||
      _timeRange.isActive ||
      _filter.assignees.contains(IssueFilter.noAssignee);

  /// Signature of the facets sent to the backend; when it changes the paged
  /// cubit must refetch from page 0 because the server query itself changed.
  String get _serverQuerySignature {
    String csv(Iterable<String> v) => (v.toList()..sort()).join(',');
    return '${csv(_filter.states)}|${csv(_filter.priorities)}|'
        '${csv(_filter.types)}|${csv(_serverAssignees ?? const [])}|'
        '${_filter.archivedOnly}';
  }

  /// [shown] is the number of currently-matched rows; [total] is the backend's
  /// full count (so it reflects everything, not just the pages loaded so far).
  String _subtitle(int shown, int total) {
    if (_hasActiveView) {
      return context.t(
        'issues.countFiltered',
        variables: {'count': '$shown', 'total': '$total'},
      );
    }
    return context.t('issues.countSummary', variables: {'count': '$total'});
  }

  /// Flat (ungrouped) row descriptors: an optional table header then one entry
  /// per issue. Cheap to build every frame — the actual [IssueRow] widgets are
  /// constructed lazily by [_buildEntry] only when scrolled into view.
  List<_RowEntry> _flatEntries(List<Issue> list) => [
    if (!context.isCompact) const _RowEntry.tableHeader(),
    for (final issue in list) _RowEntry.issue(issue),
  ];

  /// Grouped row descriptors: a collapsible header per section, its issues (when
  /// expanded), and a trailing spacer.
  List<_RowEntry> _groupedEntries(List<_Section> sections) {
    final rows = <_RowEntry>[];
    for (final section in sections) {
      final collapsed = _collapsed.contains(section.key);
      rows.add(_RowEntry.sectionHeader(section, collapsed));
      if (!collapsed) {
        for (final issue in section.issues) {
          rows.add(_RowEntry.issue(issue));
        }
      }
      rows.add(_RowEntry.spacer(collapsed ? 6 : 10));
    }
    return rows;
  }

  /// Builds the widget for a single [_RowEntry] on demand.
  Widget _buildEntry(
    _RowEntry entry,
    Map<String, String> names,
    Map<String, String> avatars,
    ProjectPalette palette,
  ) {
    switch (entry.kind) {
      case _RowKind.tableHeader:
        return const _IssueTableHeader();
      case _RowKind.spacer:
        return SizedBox(height: entry.height);
      case _RowKind.sectionHeader:
        final section = entry.section!;
        return _CollapsibleHeader(
          collapsed: entry.collapsed,
          header: section.header,
          onTap: () => setState(() {
            if (!_collapsed.remove(section.key)) _collapsed.add(section.key);
          }),
        );
      case _RowKind.issue:
        final issue = entry.issue!;
        return Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: IssueRow(
            issue: issue,
            assignee: names[issue.assigneeId],
            assigneeAvatar: avatars[issue.assigneeId],
            palette: palette,
            selectionMode: _selectionMode,
            selected: _selectedIds.contains(issue.id),
            onToggleSelect: () => _toggleSelection(issue.id),
            onLongPress: () => _enterSelection(issue.id),
          ),
        );
    }
  }
}

enum _RowKind { tableHeader, sectionHeader, issue, spacer }

/// A lightweight descriptor for one row in the issues sliver, so the list can be
/// built lazily (only visible rows) instead of materializing every widget.
class _RowEntry {
  const _RowEntry.tableHeader()
    : kind = _RowKind.tableHeader,
      issue = null,
      section = null,
      collapsed = false,
      height = 0;
  const _RowEntry.issue(this.issue)
    : kind = _RowKind.issue,
      section = null,
      collapsed = false,
      height = 0;
  const _RowEntry.sectionHeader(this.section, this.collapsed)
    : kind = _RowKind.sectionHeader,
      issue = null,
      height = 0;
  const _RowEntry.spacer(this.height)
    : kind = _RowKind.spacer,
      issue = null,
      section = null,
      collapsed = false;

  final _RowKind kind;
  final Issue? issue;
  final _Section? section;
  final bool collapsed;
  final double height;
}

/// Sentinel group key for "no assignee".
const _kNone = '__none__';

/// Rank of [value] within [order] (its index), or [order].length when absent so
/// unknown codes sort after the known ones.
int _rankIn(List<String> order, String value) {
  final i = order.indexOf(value);
  return i == -1 ? order.length : i;
}
