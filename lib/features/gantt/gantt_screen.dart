import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/work_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/gantt_links.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/glass_popup_menu.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/hive_widgets.dart';
import '../../core/widgets/soft_card.dart';
import '../search/search_tokens.dart';
import 'gantt_view_options.dart';

/// Zoom levels for the timeline. [week] shows individual day ticks under a
/// month band (Jira "Wochen"); [month] collapses to month columns only.
enum GanttZoom { week, month }

/// Localised short month label (e.g. `Jan` / `Mär`, or `Jan 2026` with year).
/// Uses `intl`'s [DateFormat] against the active locale — the date-symbol data
/// for that locale is loaded by `GlobalMaterialLocalizations`.
String _monthLabel(
  BuildContext context,
  DateTime date, {
  bool withYear = false,
}) {
  final locale = Localizations.localeOf(context).toString();
  return withYear
      ? DateFormat.yMMM(locale).format(date)
      : DateFormat.MMM(locale).format(date);
}

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime _firstOfMonth(DateTime d) => DateTime(d.year, d.month, 1);
int _daysInMonth(DateTime d) => DateTime(d.year, d.month + 1, 0).day;

/// Interactive project timeline. Bars sit on a continuous day grid; the
/// floating switcher (bottom-right) toggles zoom and jumps to today.
class GanttScreen extends StatefulWidget {
  const GanttScreen({super.key});

  @override
  State<GanttScreen> createState() => _GanttScreenState();
}

class _GanttScreenState extends State<GanttScreen> {
  List<Project> _projects = const [];
  String? _projectId;
  List<GanttTask> _tasks = const [];
  List<GanttLink> _links = const [];
  bool _loading = true;
  String? _error;

  GanttZoom _zoom = GanttZoom.week;
  GanttLinkOptions _linkOptions = const GanttLinkOptions();

  /// Issue whose relationships are pinned bright — set by tapping its bar,
  /// cleared by tapping it again or the empty grid.
  String? _focusedId;

  final _optionsKey = GlobalKey();

  // Body drives header (horizontal) and labels (vertical); followers use
  // [NeverScrollableScrollPhysics] and mirror the body's offset.
  final _hBody = ScrollController();
  final _hHeader = ScrollController();
  final _vBody = ScrollController();
  final _vLabels = ScrollController();

  bool _didInitialScroll = false;

  static const _rowHeight = 44.0;
  static const _headerHeight = 50.0;

  @override
  void initState() {
    super.initState();
    _hBody.addListener(() => _follow(_hHeader, _hBody.offset));
    _vBody.addListener(() => _follow(_vLabels, _vBody.offset));
    _load();
  }

  @override
  void dispose() {
    _hBody.dispose();
    _hHeader.dispose();
    _vBody.dispose();
    _vLabels.dispose();
    super.dispose();
  }

  /// Mirror [offset] onto a non-interactive follower controller, clamped to
  /// its own extent so a momentary size mismatch can never assert.
  void _follow(ScrollController follower, double offset) {
    if (!follower.hasClients) return;
    final max = follower.position.maxScrollExtent;
    final target = offset.clamp(0.0, max);
    if ((follower.offset - target).abs() > 0.5) follower.jumpTo(target);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final repository = context.read<ProjectRepository>();
    try {
      _projects = await repository.projects();
      if (_projects.isEmpty) {
        setState(() => _loading = false);
        return;
      }
      _projectId ??= _projects.first.id;
      final view = await repository.gantt(_projectId!);
      // Chronological order keeps most connectors running downwards, the way a
      // Gantt chart is read; the server returns insertion order.
      _tasks = [...view.tasks]
        ..sort((a, b) {
          final byStart = a.from.compareTo(b.from);
          if (byStart != 0) return byStart;
          final byEnd = a.to.compareTo(b.to);
          return byEnd != 0 ? byEnd : a.readableId.compareTo(b.readableId);
        });
      _links = view.links;
      _focusedId = null;
      _didInitialScroll = false;
      setState(() => _loading = false);
    } on ApiFailure catch (failure) {
      setState(() {
        _loading = false;
        _error = failure.message;
      });
    }
  }

  double get _pxPerDay => switch (_zoom) {
    GanttZoom.week => 32,
    GanttZoom.month => 4.6,
  };

  double _labelWidth(BuildContext context) => context.isCompact ? 136 : 188;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            context.pageGutter,
            22 + context.topGutter,
            context.pageGutter,
            14,
          ),
          child: PageHead(
            title: context.t('gantt.title'),
            subtitle: context.t('gantt.subtitle'),
            actions: [
              if (_projects.isNotEmpty)
                _ProjectPicker(
                  projects: _projects,
                  selected: _projectId,
                  onChanged: (value) {
                    _projectId = value;
                    _load();
                  },
                ),
            ],
          ),
        ),
        Expanded(child: _body(context)),
      ],
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) {
      return const Center(child: HiveLoader());
    }
    if (_error != null) {
      return Center(
        child: Text(
          context.t(_error!),
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    if (_tasks.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: context.pageGutter),
          child: HiveEmptyState(
            title: context.t('gantt.title'),
            message: context.t('gantt.empty'),
          ),
        ),
      );
    }

    final rawStart = _tasks
        .map((task) => task.from)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final rawEnd = _tasks
        .map((task) => task.to)
        .reduce((a, b) => a.isAfter(b) ? a : b);

    // Snap the window so columns are whole units: weeks start on Monday and
    // both modes pad to full months so the band reads cleanly on each edge.
    final monthStart = _firstOfMonth(rawStart);
    DateTime chartStart;
    if (_zoom == GanttZoom.week) {
      final monday = rawStart.subtract(Duration(days: rawStart.weekday - 1));
      chartStart = _dayOnly(monday.isBefore(monthStart) ? monday : monthStart);
    } else {
      chartStart = monthStart;
    }
    final lastMonthEnd = DateTime(rawEnd.year, rawEnd.month + 1, 0);
    final chartEnd = lastMonthEnd.add(const Duration(days: 1));
    final totalDays = chartEnd.difference(chartStart).inDays;
    final timelineWidth = totalDays * _pxPerDay;
    final rowsHeight = _tasks.length * _rowHeight;

    final labelWidth = _labelWidth(context);

    // Today marker, only when it falls inside the rendered window.
    final today = _dayOnly(DateTime.now());
    final inRange = !today.isBefore(chartStart) && today.isBefore(chartEnd);
    final todayX = inRange
        ? today.difference(chartStart).inDays * _pxPerDay + _pxPerDay / 2
        : null;

    _maybeInitialScroll(todayX, timelineWidth);

    // Bar geometry + the connector graph in one pass, so bars and the lines
    // between them can never drift apart.
    final graph = GanttGraph.build(
      rows: [
        for (final task in _tasks)
          GanttRow(id: task.id, from: task.from, to: task.to),
      ],
      links: _links,
      chartStart: chartStart,
      pxPerDay: _pxPerDay,
    );
    final focused = _focusedId == null
        ? const <String>{}
        : graph.relatedTo(_focusedId!);

    // Reserve just the floating nav *pill's* height so the card + switcher rest
    // snug above the nav — NOT the full gutter (pill + home-indicator safe-area),
    // which floats them too high, and NOT `bottomGutter - viewPaddingOf.bottom`
    // (the compact shell injects the nav footprint into `viewPadding.bottom` too,
    // so that collapses to 0 and hides the switcher behind the nav). Read the
    // REAL device safe-area straight from the FlutterView, which the shell's
    // MediaQuery override doesn't touch.
    final view = View.of(context);
    final safeArea = view.viewPadding.bottom / view.devicePixelRatio;
    final navClearance = (context.bottomGutter - safeArea).clamp(
      0.0,
      double.infinity,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        context.pageGutter,
        0,
        context.pageGutter,
        context.pageGutter + navClearance,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The card is only as tall as its rows, capped at the space we have.
          // Below the cap the body scrolls vertically; above it the card simply
          // shrinks to fit — so a single-issue chart no longer stretches its
          // grid to fill the screen.
          // SoftCard draws a 1px hairline border on each side, so its inner
          // height is 2px less than the box — fold that into the budget so the
          // body never overflows by those two pixels.
          const cardBorder = 2.0;
          final availableBody =
              (constraints.maxHeight - _headerHeight - 1 - cardBorder).clamp(
                0.0,
                double.infinity,
              );
          final bodyHeight = rowsHeight < availableBody
              ? rowsHeight
              : availableBody;
          final cardHeight = _headerHeight + 1 + bodyHeight + cardBorder;
          return Stack(
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  height: cardHeight,
                  child: SoftCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ---- Header strip: corner + horizontally-synced axis ----
                        SizedBox(
                          height: _headerHeight,
                          child: Row(
                            children: [
                              SizedBox(
                                width: labelWidth,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      context.t('gantt.column').toUpperCase(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.4,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Container(width: 1, color: AppColors.hairline),
                              Expanded(
                                child: SingleChildScrollView(
                                  controller: _hHeader,
                                  scrollDirection: Axis.horizontal,
                                  physics: const NeverScrollableScrollPhysics(),
                                  child: _TimeAxis(
                                    start: chartStart,
                                    days: totalDays,
                                    pxPerDay: _pxPerDay,
                                    zoom: _zoom,
                                    height: _headerHeight,
                                    width: timelineWidth,
                                    today: inRange ? today : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Divider(height: 1, color: AppColors.hairline),
                        // ---- Body: frozen labels + scrollable chart ----
                        SizedBox(
                          height: bodyHeight,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: labelWidth,
                                child: SingleChildScrollView(
                                  controller: _vLabels,
                                  physics: const NeverScrollableScrollPhysics(),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      for (final task in _tasks)
                                        _TaskLabel(
                                          task: task,
                                          height: _rowHeight,
                                          dimmed:
                                              focused.isNotEmpty &&
                                              !focused.contains(task.id),
                                          conflict: graph.conflictIds.contains(
                                            task.id,
                                          ),
                                          onTap: () =>
                                              context.go('/issues/${task.id}'),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              Container(width: 1, color: AppColors.hairline),
                              Expanded(
                                child: SingleChildScrollView(
                                  controller: _hBody,
                                  scrollDirection: Axis.horizontal,
                                  child: SizedBox(
                                    width: timelineWidth,
                                    child: SingleChildScrollView(
                                      controller: _vBody,
                                      child: SizedBox(
                                        width: timelineWidth,
                                        height: rowsHeight,
                                        child: Stack(
                                          children: [
                                            // Bottom of the stack: taps that miss
                                            // every bar drop the focus again.
                                            Positioned.fill(
                                              child: GestureDetector(
                                                behavior:
                                                    HitTestBehavior.opaque,
                                                onTap: _focusedId == null
                                                    ? null
                                                    : () => setState(
                                                        () => _focusedId = null,
                                                      ),
                                                child: CustomPaint(
                                                  painter: _GridPainter(
                                                    start: chartStart,
                                                    days: totalDays,
                                                    pxPerDay: _pxPerDay,
                                                    zoom: _zoom,
                                                    todayX: todayX,
                                                    rowHeight: _rowHeight,
                                                    rowCount: _tasks.length,
                                                    line: AppColors.hairline2,
                                                    monthLine:
                                                        AppColors.hairline,
                                                    weekend: AppColors.canvas2,
                                                    todayColor:
                                                        AppColors.stTodo,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            Positioned.fill(
                                              child: GanttLinksLayer(
                                                graph: graph,
                                                rowHeight: _rowHeight,
                                                options: _linkOptions,
                                                focusedId: _focusedId,
                                              ),
                                            ),
                                            for (
                                              var i = 0;
                                              i < _tasks.length;
                                              i++
                                            )
                                              _positionedBar(
                                                context,
                                                _tasks[i],
                                                i,
                                                graph,
                                                focused,
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // ---- Floating zoom / today switcher ----
              Positioned(
                right: 14,
                bottom: 14,
                child: _ViewSwitcher(
                  zoom: _zoom,
                  onZoom: (z) {
                    if (z == _zoom) return;
                    setState(() => _zoom = z);
                  },
                  onToday: () => _scrollToToday(todayX, timelineWidth),
                  optionsKey: _optionsKey,
                  linksActive: _linkOptions.anyLinks,
                  onOptions: () => showGanttViewOptions(
                    context,
                    anchorKey: _optionsKey,
                    options: _linkOptions,
                    summary: GanttLinkSummary(
                      dependencies: graph.dependencyCount,
                      related: graph.relatedCount,
                      conflicts: graph.conflictIds.length,
                    ),
                    onChanged: (next) => setState(() => _linkOptions = next),
                  ),
                  maxWidth:
                      MediaQuery.sizeOf(context).width -
                      2 * context.pageGutter -
                      28,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _positionedBar(
    BuildContext context,
    GanttTask task,
    int row,
    GanttGraph graph,
    Set<String> focused,
  ) {
    final slot = graph.slots[task.id]!;
    final dimmed = focused.isNotEmpty && !focused.contains(task.id);
    final critical =
        _linkOptions.showCriticalPath && graph.criticalIds.contains(task.id);
    final conflict = graph.conflictIds.contains(task.id);
    final child = task.isMilestone
        ? _MilestoneMarker(task: task, critical: critical, conflict: conflict)
        : _GanttBar(
            task: task,
            width: slot.right - slot.left,
            showLabel: _zoom == GanttZoom.week,
            critical: critical,
            conflict: conflict,
          );
    return Positioned(
      left: slot.left,
      top: row * _rowHeight,
      height: _rowHeight,
      width: slot.right - slot.left,
      child: Center(
        child: _FocusableBar(
          hint: _barTooltip(context, task, graph),
          dimmed: dimmed,
          // A tap pins the issue's relationships; a long-press opens it, as does
          // a tap on its label in the frozen column.
          onTap: () => setState(
            () => _focusedId = _focusedId == task.id ? null : task.id,
          ),
          onOpen: () => context.go('/issues/${task.id}'),
          child: child,
        ),
      ),
    );
  }

  /// "HIN-4 · In Arbeit · 40% — blocks HIN-9, is blocked by HIN-2".
  String _barTooltip(BuildContext context, GanttTask task, GanttGraph graph) {
    final buffer = StringBuffer(
      '${task.readableId} · ${stateLabel(task.state)} · ${task.progressPercent}%',
    );
    final byId = {for (final t in _tasks) t.id: t};
    final relations = <String>[];
    for (final edge in graph.edges) {
      if (!edge.touches(task.id)) continue;
      final outward = edge.from.id == task.id;
      final other = byId[outward ? edge.to.id : edge.from.id];
      if (other == null) continue;
      relations.add(
        '${context.t(issueLinkVerbKey(edge.link.type, outward))} '
        '${other.readableId}',
      );
    }
    if (relations.isNotEmpty) buffer.write('\n${relations.join('\n')}');
    if (graph.conflictIds.contains(task.id)) {
      buffer.write('\n⚠ ${context.t('gantt.conflictHint')}');
    }
    return buffer.toString();
  }

  void _maybeInitialScroll(double? todayX, double timelineWidth) {
    if (_didInitialScroll) return;
    _didInitialScroll = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToToday(todayX, timelineWidth, animate: false);
    });
  }

  void _scrollToToday(
    double? todayX,
    double timelineWidth, {
    bool animate = true,
  }) {
    if (!_hBody.hasClients) return;
    final viewport = _hBody.position.viewportDimension;
    final max = _hBody.position.maxScrollExtent;
    final anchor = todayX ?? 0;
    final target = (anchor - viewport / 2).clamp(0.0, max);
    if (animate) {
      _hBody.animateTo(
        target,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
      );
    } else {
      _hBody.jumpTo(target);
    }
  }
}

/// Compact white dropdown for choosing the active project.
class _ProjectPicker extends StatelessWidget {
  const _ProjectPicker({
    required this.projects,
    required this.selected,
    required this.onChanged,
  });

  final List<Project> projects;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final label = selected != null
        ? projects.where((p) => p.id == selected).firstOrNull?.name ??
              projects.first.name
        : projects.first.name;
    return GlassPopupMenu<String?>(
      value: selected,
      onSelected: onChanged,
      items: [
        for (final p in projects) GlassMenuItem(value: p.id, label: p.name),
      ],
      child: Container(
        constraints: const BoxConstraints(maxWidth: 220),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(LucideIcons.chevronDown, size: 16, color: AppColors.inkSoft),
          ],
        ),
      ),
    );
  }
}

/// Frozen left-column entry: readable id + title, tappable to open the issue.
class _TaskLabel extends StatelessWidget {
  const _TaskLabel({
    required this.task,
    required this.height,
    required this.onTap,
    this.dimmed = false,
    this.conflict = false,
  });

  final GanttTask task;
  final double height;
  final VoidCallback onTap;

  /// Faded because another issue's relationships are pinned.
  final bool dimmed;

  /// Scheduled to start before the issue blocking it is finished.
  final bool conflict;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: dimmed ? 0.35 : 1,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                TypeGlyph(type: task.type, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: RichText(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: const TextStyle(fontSize: 12),
                      children: [
                        TextSpan(
                          text: task.readableId,
                          style: TextStyle(
                            fontFamily: AppTheme.fontMono,
                            fontWeight: FontWeight.w700,
                            color: AppColors.inkSoft,
                          ),
                        ),
                        const TextSpan(text: '  '),
                        TextSpan(
                          text: task.title,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (conflict) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: context.t('gantt.conflictHint'),
                    child: const Icon(
                      LucideIcons.triangleAlert,
                      size: 14,
                      color: AppColors.danger,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Two-tier (week) or single-tier (month) timeline header.
class _TimeAxis extends StatelessWidget {
  const _TimeAxis({
    required this.start,
    required this.days,
    required this.pxPerDay,
    required this.zoom,
    required this.height,
    required this.width,
    required this.today,
  });

  final DateTime start;
  final int days;
  final double pxPerDay;
  final GanttZoom zoom;
  final double height;
  final double width;
  final DateTime? today;

  @override
  Widget build(BuildContext context) {
    final segments = _monthSegments();
    final bandHeight = zoom == GanttZoom.week ? 24.0 : height;

    return SizedBox(
      width: width,
      height: height,
      child: Column(
        children: [
          // ---- Month band ----
          SizedBox(
            height: bandHeight,
            child: Row(
              children: [
                for (final seg in segments)
                  _MonthCell(
                    label: _monthLabel(
                      context,
                      seg.date,
                      withYear: seg.width * pxPerDay > 96,
                    ),
                    width: seg.width * pxPerDay,
                    emphatic: zoom == GanttZoom.month,
                  ),
              ],
            ),
          ),
          // ---- Day ticks (week mode only) ----
          if (zoom == GanttZoom.week)
            SizedBox(
              height: height - bandHeight,
              child: Row(
                children: [
                  for (var i = 0; i < days; i++)
                    _DayTick(
                      date: start.add(Duration(days: i)),
                      width: pxPerDay,
                      isToday:
                          today != null &&
                          start.add(Duration(days: i)) == today,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<({DateTime date, int width})> _monthSegments() {
    final out = <({DateTime date, int width})>[];
    var i = 0;
    while (i < days) {
      final date = start.add(Duration(days: i));
      final monthStart = _firstOfMonth(date);
      // Days remaining in this month within the rendered window.
      final endOfMonth = _daysInMonth(date);
      final consumed = date.day - 1;
      final remainInMonth = endOfMonth - consumed;
      final remainInChart = days - i;
      final span = remainInMonth < remainInChart
          ? remainInMonth
          : remainInChart;
      out.add((date: monthStart, width: span));
      i += span;
    }
    return out;
  }
}

class _MonthCell extends StatelessWidget {
  const _MonthCell({
    required this.label,
    required this.width,
    required this.emphatic,
  });

  final String label;
  final double width;
  final bool emphatic;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: AppColors.hairline),
          bottom: BorderSide(color: AppColors.hairline2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.clip,
          softWrap: false,
          style: TextStyle(
            fontSize: emphatic ? 12 : 11,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
      ),
    );
  }
}

class _DayTick extends StatelessWidget {
  const _DayTick({
    required this.date,
    required this.width,
    required this.isToday,
  });

  final DateTime date;
  final double width;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final weekend = date.weekday >= DateTime.saturday;
    final child = Text(
      '${date.day}',
      style: TextStyle(
        fontSize: 10,
        fontWeight: isToday || date.day == 1
            ? FontWeight.w800
            : FontWeight.w400,
        color: isToday
            ? Colors.white
            : (weekend ? AppColors.inkSoft : AppColors.textSecondary),
      ),
    );
    return SizedBox(
      width: width,
      child: Center(
        child: isToday
            ? Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.stTodo,
                  shape: BoxShape.circle,
                ),
                child: child,
              )
            : child,
      ),
    );
  }
}

/// Background grid: per-day hairlines (week), month boundaries, weekend
/// shading and the today line — all painted once behind every row.
class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.start,
    required this.days,
    required this.pxPerDay,
    required this.zoom,
    required this.todayX,
    required this.rowHeight,
    required this.rowCount,
    required this.line,
    required this.monthLine,
    required this.weekend,
    required this.todayColor,
  });

  final DateTime start;
  final int days;
  final double pxPerDay;
  final GanttZoom zoom;
  final double? todayX;
  final double rowHeight;
  final int rowCount;
  final Color line;
  final Color monthLine;
  final Color weekend;
  final Color todayColor;

  @override
  void paint(Canvas canvas, Size size) {
    final weekendPaint = Paint()..color = weekend.withValues(alpha: 0.5);
    final dayPaint = Paint()
      ..color = line
      ..strokeWidth = 1;
    final monthPaint = Paint()
      ..color = monthLine
      ..strokeWidth = 1;
    final rowPaint = Paint()
      ..color = line.withValues(alpha: 0.6)
      ..strokeWidth = 1;

    // Weekend shading (week mode keeps the grid readable; month mode is dense).
    if (zoom == GanttZoom.week) {
      for (var i = 0; i < days; i++) {
        final date = start.add(Duration(days: i));
        if (date.weekday >= DateTime.saturday) {
          final x = i * pxPerDay;
          canvas.drawRect(
            Rect.fromLTWH(x, 0, pxPerDay, size.height),
            weekendPaint,
          );
        }
      }
    }

    // Vertical lines: emphasised on month boundaries.
    for (var i = 0; i <= days; i++) {
      final date = start.add(Duration(days: i));
      final isMonthEdge = i == 0 || i == days || date.day == 1;
      if (zoom == GanttZoom.week) {
        final x = i * pxPerDay;
        canvas.drawLine(
          Offset(x, 0),
          Offset(x, size.height),
          isMonthEdge ? monthPaint : dayPaint,
        );
      } else if (isMonthEdge) {
        final x = i * pxPerDay;
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), monthPaint);
      }
    }

    // Horizontal row separators.
    for (var r = 1; r < rowCount; r++) {
      final y = r * rowHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), rowPaint);
    }

    // Today line.
    if (todayX != null) {
      final p = Paint()
        ..color = todayColor
        ..strokeWidth = 1.5;
      canvas.drawLine(Offset(todayX!, 0), Offset(todayX!, size.height), p);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.start != start ||
      old.days != days ||
      old.pxPerDay != pxPerDay ||
      old.zoom != zoom ||
      old.todayX != todayX ||
      old.rowCount != rowCount;
}

/// Wraps a bar (or milestone) with the timeline's shared interaction: tap pins
/// the issue's relationships, long-press opens it, hovering previews the same
/// highlight on pointer devices. Unrelated rows fade while a focus is pinned.
class _FocusableBar extends StatelessWidget {
  const _FocusableBar({
    required this.child,
    required this.hint,
    required this.dimmed,
    required this.onTap,
    required this.onOpen,
  });

  final Widget child;
  final String hint;
  final bool dimmed;
  final VoidCallback onTap;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onOpen,
        onDoubleTap: onOpen,
        child: Tooltip(
          message: hint,
          waitDuration: const Duration(milliseconds: 350),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 160),
            opacity: dimmed ? 0.26 : 1,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Zero-duration issue — a deadline. Drawn as the diamond every Gantt chart
/// uses instead of a bar with no length.
class _MilestoneMarker extends StatelessWidget {
  const _MilestoneMarker({
    required this.task,
    required this.critical,
    required this.conflict,
  });

  final GanttTask task;
  final bool critical;
  final bool conflict;

  @override
  Widget build(BuildContext context) {
    final color = conflict
        ? AppColors.danger
        : critical
        ? AppColors.accentStrong
        : (task.resolved
              ? AppColors.stDone
              : AppColors.stateColor(task.state.toUpperCase()));
    return GanttMilestone(color: color, outlined: !task.resolved);
  }
}

class _GanttBar extends StatelessWidget {
  const _GanttBar({
    required this.task,
    required this.width,
    required this.showLabel,
    this.critical = false,
    this.conflict = false,
  });

  final GanttTask task;
  final double width;
  final bool showLabel;

  /// On the longest dependency chain — no slack, so it carries the accent ring.
  final bool critical;

  /// Starts before the issue blocking it is finished.
  final bool conflict;

  @override
  Widget build(BuildContext context) {
    final color = task.resolved
        ? AppColors.stDone
        : AppColors.stateColor(task.state.toUpperCase());
    final ring = conflict
        ? AppColors.danger
        : critical
        ? AppColors.accentStrong
        : null;
    return Container(
      width: width,
      height: 24,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
        border: ring == null ? null : Border.all(color: ring, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: (task.progressPercent / 100).clamp(0.0, 1.0),
              child: Container(color: Colors.white.withValues(alpha: 0.22)),
            ),
          ),
          if (showLabel && width > 28)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  task.readableId,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  softWrap: false,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontMono,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Floating bottom-right control on the liquid-glass material: a "today" action
/// separated from the zoom toggle. Horizontally scrollable internally so it can
/// never overflow.
class _ViewSwitcher extends StatelessWidget {
  const _ViewSwitcher({
    required this.zoom,
    required this.onZoom,
    required this.onToday,
    required this.optionsKey,
    required this.linksActive,
    required this.onOptions,
    required this.maxWidth,
  });

  final GanttZoom zoom;
  final ValueChanged<GanttZoom> onZoom;
  final VoidCallback onToday;

  /// Anchors the view-options popover to the chip that opens it.
  final GlobalKey optionsKey;
  final bool linksActive;
  final VoidCallback onOptions;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    // Phones give the chart every pixel they can: the switcher drops to icons
    // and keeps its labels in the tooltips.
    final iconOnly = context.isCompact;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tokens = SearchTokens.of(dark ? Brightness.dark : Brightness.light);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth.clamp(140.0, 420.0)),
      child: GlassFloatingSurface(
        // A pill, not a rounded box: half the switcher's own height, so the
        // ends stay perfectly round whichever mode it is in.
        radius: (iconOnly ? 44 : 42) / 2,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SwitchChip(
                  key: optionsKey,
                  label: context.t('gantt.options.short'),
                  icon: LucideIcons.gitFork,
                  active: linksActive,
                  iconOnly: iconOnly,
                  onTap: onOptions,
                ),
                const SizedBox(width: 2),
                _SwitchChip(
                  label: context.t('gantt.today'),
                  icon: LucideIcons.locateFixed,
                  active: false,
                  iconOnly: iconOnly,
                  onTap: onToday,
                ),
                Container(
                  width: 1,
                  height: 22,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  color: tokens.hairline,
                ),
                _SwitchChip(
                  label: context.t('gantt.week'),
                  // A span of days vs. the full month grid — the two zoom
                  // levels read apart at a glance without their labels.
                  icon: LucideIcons.calendarRange,
                  active: zoom == GanttZoom.week,
                  iconOnly: iconOnly,
                  onTap: () => onZoom(GanttZoom.week),
                ),
                const SizedBox(width: 2),
                _SwitchChip(
                  label: context.t('gantt.month'),
                  icon: LucideIcons.calendarDays,
                  active: zoom == GanttZoom.month,
                  iconOnly: iconOnly,
                  onTap: () => onZoom(GanttZoom.month),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SwitchChip extends StatelessWidget {
  const _SwitchChip({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    this.icon,
    this.iconOnly = false,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData? icon;

  /// Drops the label and keeps it as the tooltip — the compact layout, where a
  /// four-chip switcher with words would run past the screen.
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tokens = SearchTokens.of(dark ? Brightness.dark : Brightness.light);
    // On glass the active pill is a translucent amber wash, not an opaque
    // fill — an opaque chip would sit on the lens like a sticker.
    final fg = active
        ? (dark ? AppColors.accent : AppColors.accentStrong)
        : tokens.inkSoft;
    final compact = iconOnly && icon != null;
    final chip = Material(
      color: active
          ? AppColors.accent.withValues(alpha: dark ? 0.30 : 0.22)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 11 : 12,
            vertical: 7,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: compact ? 18 : 15, color: fg),
                if (!compact) const SizedBox(width: 5),
              ],
              if (!compact)
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return compact ? Tooltip(message: label, child: chip) : chip;
  }
}
