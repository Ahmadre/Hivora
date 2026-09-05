import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/blocs/auth_bloc.dart';
import '../../core/blocs/fetch_cubit.dart';
import '../../core/events/board_events.dart';
import '../../core/events/issue_events.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/content_models.dart';
import '../../core/models/team_models.dart' show Team;
import '../../core/models/work_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hex_mark.dart' show HexMark;
import '../../core/widgets/hive_widgets.dart';
import '../../core/widgets/user_pronouns.dart';
import '../../core/widgets/status_widgets.dart';
import '../admin/connect_hint.dart';
import '../issues/issue_detail_sheet.dart';
import '../sprint/modals/glass_modal.dart'
    show
        showGlassAnchoredPopover,
        GlassModalHeader,
        GlassModalFooter,
        GlassToastKind,
        showGlassErrorToast,
        showGlassToast;
import '../../core/repositories/dashboard_repository.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/repositories/team_repository.dart';

part 'dashboard_screen.hero.dart';
part 'dashboard_screen.panels.dart';
part 'dashboard_screen.chrome.dart';

/// Exact segment colours for the completion donut / KPIs (design "Liquid Glass").
const _cDone = Color(0xFF2E8B62);
const _cProgress = Color(0xFFD9A032);
const _cBacklog = Color(0xFF6B6890);
const _cToday = Color(0xFF4E6FD0);
const _cAmberHi = Color(0xFFF0C464);
const _cAmberLo = Color(0xFFD9A032);
const _heroInk = Color(0xF2FFFFFF); // ~95% white — hero text on navy glass

/// Card-to-card gap on the dashboard grid.
const double _gap = 18;

/// Width of the edit-mode picker fields and their anchored popovers (kept equal
/// so the dropdown lines up exactly under its field).
const double _kPickerWidth = 300;

/// Stable card keys for show/hide personalisation. `hero` is the anchor card
/// (with the board picker) and is never hideable.
abstract final class _Card {
  static const hero = 'hero';
  static const focus = 'focus';
  static const git = 'git';
  static const kpis = 'kpis';
  static const completion = 'completion';
  static const tracker = 'tracker';
  static const ranking = 'ranking';
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) => const _DashboardView();
}

class _DashboardView extends StatefulWidget {
  const _DashboardView();

  @override
  State<_DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<_DashboardView> {
  late final FetchCubit<DashboardData> _cubit;

  DashboardRepository get _dashboardApi => context.read<DashboardRepository>();
  ProjectRepository get _projectApi => context.read<ProjectRepository>();
  TeamRepository get _teamApi => context.read<TeamRepository>();

  bool _editing = false;
  bool _saving = false;

  /// The pending personalisation while [_editing]; seeded from the saved prefs
  /// on entering edit mode. Scope/board changes re-fetch for a live preview;
  /// card show/hide is applied purely client-side.
  DashboardPrefs _draft = DashboardPrefs.empty;

  // Loaded once for the scope pickers (never blocks the dashboard itself).
  List<Project> _projects = const [];
  List<Team> _teams = const [];

  /// Re-fetch when an issue is created/changed elsewhere (e.g. the global
  /// nav-rail "new issue" button, which can't reach this screen's cubit).
  StreamSubscription<void>? _issueSub;

  /// Same, for boards: the hero board and the board the tiles are drawn from
  /// are chosen out of the set the payload carries, so a board created
  /// elsewhere has to reach the picker without a reload.
  StreamSubscription<void>? _boardSub;

  @override
  void initState() {
    super.initState();
    _cubit = FetchCubit<DashboardData>(
      () => _dashboardApi.dashboard(override: _editing ? _draft : null),
    )..load();
    _issueSub = IssueEvents.instance.changes.listen((_) => _cubit.load());
    _boardSub = BoardEvents.instance.changes.listen((_) => _cubit.load());
    _loadPickerData();
    // One-time nudge for admins on a not-yet-connected self-hosted instance.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeShowConnectHint(context);
    });
  }

  Future<void> _loadPickerData() async {
    try {
      final projects = await _projectApi.projects();
      final teams = await _teamApi.teams();
      if (!mounted) return;
      setState(() {
        _projects = projects;
        _teams = teams;
      });
    } catch (_) {
      // Pickers simply stay empty — the dashboard still works.
    }
  }

  @override
  void dispose() {
    _issueSub?.cancel();
    _boardSub?.cancel();
    _cubit.close();
    super.dispose();
  }

  void _enterEdit(DashboardData data) {
    setState(() {
      _draft = data.prefs;
      _editing = true;
    });
  }

  Future<void> _finishEdit() async {
    setState(() => _saving = true);
    try {
      await _dashboardApi.saveDashboardPrefs(_draft);
      if (!mounted) return;
      setState(() {
        _editing = false;
        _saving = false;
      });
      _cubit.load(); // reload with the persisted prefs (no override)
      showGlassToast(
        context,
        context.t('dashboard.saved'),
        kind: GlassToastKind.success,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showGlassErrorToast(context, context.t('dashboard.saveError'));
    }
  }

  /// A scope/board change: update the draft and re-fetch for live preview.
  void _applyScope(DashboardPrefs next) {
    setState(() => _draft = next);
    _cubit.load();
  }

  /// Card show/hide is client-side only — no server round trip.
  void _toggleCard(String key) {
    setState(
      () => _draft = _draft.toggleCard(key, hidden: !_draft.isHidden(key)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The ambient backdrop is painted app-wide by the shell; the dashboard just
    // renders its (glass) content on top of it.
    return BlocProvider.value(
      value: _cubit,
      child: BlocBuilder<FetchCubit<DashboardData>, FetchState<DashboardData>>(
        builder: (context, state) {
          return RefreshIndicator(
            color: AppColors.accent,
            backgroundColor: AppColors.surface,
            edgeOffset: context.topGutter,
            onRefresh: () => _cubit.load(),
            child: AsyncView(
              isLoading: state.isLoading,
              hasData: state.hasData,
              errorKey: state.errorKey,
              onRetry: () => _cubit.load(),
              builder: (context) => _content(context, state.data!),
            ),
          );
        },
      ),
    );
  }

  Widget _content(BuildContext context, DashboardData data) {
    final wide = !context.isCompact;
    // Effective personalisation: the live draft while editing, else the saved
    // snapshot from the server.
    final prefs = _editing ? _draft : data.prefs;
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        context.pageGutter,
        20 + context.topGutter,
        context.pageGutter,
        context.pageGutter + context.bottomGutter,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context, data),
          if (_editing) ...[
            const SizedBox(height: 16),
            _EditToolbar(
              boards: data.boards,
              draft: _draft,
              projects: _projects,
              teams: _teams,
              onChanged: _applyScope,
            ),
          ],
          const SizedBox(height: 22),
          if (wide)
            _wideGrid(context, data, prefs)
          else
            _stack(context, data, prefs),
        ],
      ),
    );
  }

  // Greeting + the responsive "Customize" toggle, aligned to the title's row.
  Widget _header(BuildContext context, DashboardData data) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _Greeting(sprint: data.activeBoard)),
        const SizedBox(width: 12),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: _CustomizeButton(
            editing: _editing,
            saving: _saving,
            compact: context.isCompact,
            onPressed: () => _editing ? _finishEdit() : _enterEdit(data),
          ),
        ),
      ],
    );
  }

  // Desktop / tablet: golden-ratio two columns (1.618 : 1).
  Widget _wideGrid(
    BuildContext context,
    DashboardData data,
    DashboardPrefs prefs,
  ) {
    final left = <(String, Widget)>[
      (_Card.hero, _sprintCard(data.activeBoard)),
      (_Card.focus, _FocusCard(issues: data.todayTasks)),
      if (data.gitActivity.isNotEmpty)
        (_Card.git, _GitCard(events: data.gitActivity)),
    ];
    final right = <(String, Widget)>[
      (
        _Card.kpis,
        _Kpis(
          today: data.todayCount,
          completion: data.completion,
          projectIds: prefs.projectIds,
        ),
      ),
      (_Card.completion, _CompletionCard(completion: data.completion)),
      (
        _Card.tracker,
        _TrackerCard(week: data.tracker, month: data.trackerMonth),
      ),
      (_Card.ranking, _LeaderboardCard(ranking: data.ranking)),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 1618, child: _column(left, prefs)),
        const SizedBox(width: _gap + 3),
        Expanded(flex: 1000, child: _column(right, prefs)),
      ],
    );
  }

  // Phone: one column.
  Widget _stack(
    BuildContext context,
    DashboardData data,
    DashboardPrefs prefs,
  ) {
    final items = <(String, Widget)>[
      (_Card.hero, _sprintCard(data.activeBoard)),
      (
        _Card.kpis,
        _Kpis(
          today: data.todayCount,
          completion: data.completion,
          projectIds: prefs.projectIds,
        ),
      ),
      (_Card.focus, _FocusCard(issues: data.todayTasks)),
      (_Card.completion, _CompletionCard(completion: data.completion)),
      (
        _Card.tracker,
        _TrackerCard(week: data.tracker, month: data.trackerMonth),
      ),
      if (data.gitActivity.isNotEmpty)
        (_Card.git, _GitCard(events: data.gitActivity)),
      (_Card.ranking, _LeaderboardCard(ranking: data.ranking)),
    ];
    return _column(items, prefs);
  }

  /// Builds a column from `(cardKey, widget)` pairs: in view mode hidden cards
  /// are dropped (and their gap with them); in edit mode every card renders,
  /// wrapped with a show/hide toggle (hidden ones dimmed).
  Widget _column(List<(String, Widget)> items, DashboardPrefs prefs) {
    final children = <Widget>[];
    for (final (key, widget) in items) {
      final hidden = prefs.isHidden(key);
      if (!_editing && hidden) continue;
      if (children.isNotEmpty) children.add(const SizedBox(height: _gap));
      children.add(_editableCard(key, widget, hidden));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _editableCard(String key, Widget child, bool hidden) {
    // The hero is the personalisation anchor (holds the board picker) — always on.
    if (!_editing || key == _Card.hero) return child;
    return _HideableCard(
      hidden: hidden,
      onToggle: () => _toggleCard(key),
      child: child,
    );
  }

  Widget _sprintCard(DashboardBoard? sprint) =>
      sprint == null ? const _SprintEmpty() : _SprintHero(sprint: sprint);
}
