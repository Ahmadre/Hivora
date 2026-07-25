import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/i18n/i18n.dart';
import '../../core/models/work_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/gantt_links.dart';
import '../../core/widgets/hive_widgets.dart';
import '../../core/widgets/soft_card.dart';

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime _firstOfMonth(DateTime d) => DateTime(d.year, d.month, 1);
int _daysInMonth(DateTime d) => DateTime(d.year, d.month + 1, 0).day;

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

/// A week-grid timeline of every issue currently on the board (any status,
/// including the hidden backlog column). Issues with a start and/or due date
/// are placed on the day grid; those without dates are listed underneath.
///
/// Operates on [Issue] (not the Gantt read model), but shares the Gantt screen's
/// connector layer, so dependencies, conflicts and milestones read identically
/// on both surfaces. All axes scroll, so it never overflows.
class BoardTimeline extends StatefulWidget {
  const BoardTimeline({
    super.key,
    required this.issues,
    required this.onOpen,
    this.links = const [],
    this.padding = EdgeInsets.zero,
  });

  final List<Issue> issues;

  /// The board's issue-link graph. Empty until it has loaded — the chart simply
  /// draws no connectors until then.
  final List<GanttLink> links;

  final void Function(Issue) onOpen;
  final EdgeInsets padding;

  @override
  State<BoardTimeline> createState() => _BoardTimelineState();
}

class _BoardTimelineState extends State<BoardTimeline> {
  final _hBody = ScrollController();
  final _hHeader = ScrollController();
  final _vBody = ScrollController();
  final _vLabels = ScrollController();

  bool _didInitialScroll = false;

  static const _pxPerDay = 30.0;
  static const _rowHeight = 44.0;
  static const _headerHeight = 50.0;

  @override
  void initState() {
    super.initState();
    _hBody.addListener(() => _follow(_hHeader, _hBody.offset));
    _vBody.addListener(() => _follow(_vLabels, _vBody.offset));
  }

  @override
  void dispose() {
    _hBody.dispose();
    _hHeader.dispose();
    _vBody.dispose();
    _vLabels.dispose();
    super.dispose();
  }

  void _follow(ScrollController follower, double offset) {
    if (!follower.hasClients) return;
    final max = follower.position.maxScrollExtent;
    final target = offset.clamp(0.0, max);
    if ((follower.offset - target).abs() > 0.5) follower.jumpTo(target);
  }

  DateTime _start(Issue i) => _dayOnly(i.startDate ?? i.dueDate!);
  DateTime _end(Issue i) => _dayOnly(i.dueDate ?? i.startDate!);

  /// The server's link graph plus the issues' own `dependsOnIds`. The project
  /// link endpoint only knows about real [IssueLink]s, so the legacy dependency
  /// field is folded in here — "A depends on B" is "B blocks A" — and deduped
  /// against a real link that already says the same thing.
  List<GanttLink> _graphLinks(List<Issue> tasks) {
    final out = [...widget.links];
    final seen = {
      for (final link in out) '${link.type}|${link.sourceId}|${link.targetId}',
    };
    for (final issue in tasks) {
      for (final blockerId in issue.dependsOnIds) {
        final key = 'BLOCKS|$blockerId|${issue.id}';
        if (blockerId == issue.id || !seen.add(key)) continue;
        out.add(
          GanttLink(
            id: 'dep:$blockerId:${issue.id}',
            type: 'BLOCKS',
            sourceId: blockerId,
            targetId: issue.id,
          ),
        );
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final dated =
        widget.issues
            .where((i) => i.startDate != null || i.dueDate != null)
            .toList()
          ..sort((a, b) => _start(a).compareTo(_start(b)));
    final undated = widget.issues
        .where((i) => i.startDate == null && i.dueDate == null)
        .toList();

    if (dated.isEmpty && undated.isEmpty) {
      return Padding(
        padding: widget.padding,
        child: Center(
          child: Text(
            context.t('board.timelineEmpty'),
            style: TextStyle(color: AppColors.inkSoft),
          ),
        ),
      );
    }

    return Padding(
      padding: widget.padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Cap the undated list so a long one can't push past the viewport.
          // It still shrink-wraps to its content when short, leaving the rest
          // of the height to the chart; it scrolls only once it hits the cap.
          final undatedCap = constraints.maxHeight.isFinite
              ? constraints.maxHeight * 0.4
              : double.infinity;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (dated.isNotEmpty) ...[
                Expanded(child: _chart(context, dated)),
                if (undated.isNotEmpty)
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: undatedCap),
                    child: SingleChildScrollView(
                      child: _undatedSection(context, undated),
                    ),
                  ),
              ] else if (undated.isNotEmpty)
                // No dated rows: the undated list is the only content, so let
                // it take the whole viewport and scroll instead of overflowing.
                Expanded(
                  child: SingleChildScrollView(
                    child: _undatedSection(context, undated),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _chart(BuildContext context, List<Issue> tasks) {
    final rawStart = tasks.map(_start).reduce((a, b) => a.isBefore(b) ? a : b);
    final rawEnd = tasks.map(_end).reduce((a, b) => a.isAfter(b) ? a : b);

    final monthStart = _firstOfMonth(rawStart);
    final monday = rawStart.subtract(Duration(days: rawStart.weekday - 1));
    final chartStart = _dayOnly(
      monday.isBefore(monthStart) ? monday : monthStart,
    );
    final chartEnd = DateTime(
      rawEnd.year,
      rawEnd.month + 1,
      0,
    ).add(const Duration(days: 1));
    final totalDays = chartEnd.difference(chartStart).inDays;
    final timelineWidth = totalDays * _pxPerDay;
    final rowsHeight = tasks.length * _rowHeight;
    final labelWidth = context.isCompact ? 140.0 : 188.0;

    final today = _dayOnly(DateTime.now());
    final inRange = !today.isBefore(chartStart) && today.isBefore(chartEnd);
    final todayX = inRange
        ? today.difference(chartStart).inDays * _pxPerDay + _pxPerDay / 2
        : null;

    _maybeInitialScroll(todayX);

    final graph = GanttGraph.build(
      rows: [
        for (final task in tasks)
          GanttRow(id: task.id, from: _start(task), to: _end(task)),
      ],
      links: _graphLinks(tasks),
      chartStart: chartStart,
      pxPerDay: _pxPerDay,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // SoftCard draws a 1px hairline border that insets its child top &
        // bottom (2px total), so reserve it or the inner Column overflows.
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
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: cardHeight,
            child: SoftCard(
              padding: EdgeInsets.zero,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: _headerHeight,
                    child: Row(
                      children: [
                        SizedBox(
                          width: labelWidth,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                context.t('issues.colTitle').toUpperCase(),
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
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final task in tasks)
                                  _TaskLabel(
                                    task: task,
                                    height: _rowHeight,
                                    onTap: () => widget.onOpen(task),
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
                                      Positioned.fill(
                                        child: CustomPaint(
                                          painter: _GridPainter(
                                            start: chartStart,
                                            days: totalDays,
                                            pxPerDay: _pxPerDay,
                                            todayX: todayX,
                                            rowHeight: _rowHeight,
                                            rowCount: tasks.length,
                                            line: AppColors.hairline2,
                                            monthLine: AppColors.hairline,
                                            weekend: AppColors.canvas2,
                                            todayColor: AppColors.stTodo,
                                          ),
                                        ),
                                      ),
                                      Positioned.fill(
                                        child: GanttLinksLayer(
                                          graph: graph,
                                          rowHeight: _rowHeight,
                                        ),
                                      ),
                                      for (var i = 0; i < tasks.length; i++)
                                        _positionedBar(tasks[i], i, graph),
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
        );
      },
    );
  }

  Widget _positionedBar(Issue task, int row, GanttGraph graph) {
    final slot = graph.slots[task.id]!;
    final width = slot.right - slot.left;
    final fraction = (task.estimateMinutes != null && task.estimateMinutes! > 0)
        ? (task.spentMinutes / task.estimateMinutes!).clamp(0.0, 1.0)
        : (task.resolved ? 1.0 : 0.0);
    final conflict = graph.conflictIds.contains(task.id);
    final color = task.resolved
        ? AppColors.stDone
        : AppColors.stateColor(task.state.toUpperCase());
    return Positioned(
      left: slot.left,
      top: row * _rowHeight,
      height: _rowHeight,
      width: width,
      child: Center(
        child: GestureDetector(
          onTap: () => widget.onOpen(task),
          child: Tooltip(
            message: conflict
                ? '${task.readableId} · ${stateLabel(task.state)}'
                      '\n⚠ ${context.t('gantt.conflictHint')}'
                : '${task.readableId} · ${stateLabel(task.state)}',
            child: slot.isMilestone
                ? GanttMilestone(
                    color: conflict ? AppColors.danger : color,
                    outlined: !task.resolved,
                  )
                : _TimelineBar(
                    task: task,
                    width: width,
                    fraction: fraction.toDouble(),
                    conflict: conflict,
                  ),
          ),
        ),
      ),
    );
  }

  void _maybeInitialScroll(double? todayX) {
    if (_didInitialScroll) return;
    _didInitialScroll = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_hBody.hasClients) return;
      final viewport = _hBody.position.viewportDimension;
      final max = _hBody.position.maxScrollExtent;
      final target = ((todayX ?? 0) - viewport / 2).clamp(0.0, max);
      _hBody.jumpTo(target);
    });
  }

  Widget _undatedSection(BuildContext context, List<Issue> undated) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t('board.timelineNoDates').toUpperCase(),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: AppColors.inkFaint,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final issue in undated)
                GestureDetector(
                  onTap: () => widget.onOpen(issue),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                      border: Border.all(color: AppColors.hairline),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TypeGlyph(type: issue.type, size: 16),
                        const SizedBox(width: 7),
                        IdMono(issue.readableId),
                        const SizedBox(width: 7),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 180),
                          child: Text(
                            issue.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TaskLabel extends StatelessWidget {
  const _TaskLabel({
    required this.task,
    required this.height,
    required this.onTap,
  });

  final Issue task;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
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
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeAxis extends StatelessWidget {
  const _TimeAxis({
    required this.start,
    required this.days,
    required this.pxPerDay,
    required this.height,
    required this.width,
    required this.today,
  });

  final DateTime start;
  final int days;
  final double pxPerDay;
  final double height;
  final double width;
  final DateTime? today;

  @override
  Widget build(BuildContext context) {
    final segments = _monthSegments();
    const bandHeight = 24.0;
    return SizedBox(
      width: width,
      height: height,
      child: Column(
        children: [
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
                  ),
              ],
            ),
          ),
          SizedBox(
            height: height - bandHeight,
            child: Row(
              children: [
                for (var i = 0; i < days; i++)
                  _DayTick(
                    date: start.add(Duration(days: i)),
                    width: pxPerDay,
                    isToday:
                        today != null && start.add(Duration(days: i)) == today,
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
      final endOfMonth = _daysInMonth(date);
      final consumed = date.day - 1;
      final remainInMonth = endOfMonth - consumed;
      final remainInChart = days - i;
      final span = remainInMonth < remainInChart
          ? remainInMonth
          : remainInChart;
      out.add((date: _firstOfMonth(date), width: span));
      i += span;
    }
    return out;
  }
}

class _MonthCell extends StatelessWidget {
  const _MonthCell({required this.label, required this.width});
  final String label;
  final double width;

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
            fontSize: 11,
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

class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.start,
    required this.days,
    required this.pxPerDay,
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

    for (var i = 0; i < days; i++) {
      final date = start.add(Duration(days: i));
      if (date.weekday >= DateTime.saturday) {
        canvas.drawRect(
          Rect.fromLTWH(i * pxPerDay, 0, pxPerDay, size.height),
          weekendPaint,
        );
      }
    }
    for (var i = 0; i <= days; i++) {
      final date = start.add(Duration(days: i));
      final isMonthEdge = i == 0 || i == days || date.day == 1;
      final x = i * pxPerDay;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        isMonthEdge ? monthPaint : dayPaint,
      );
    }
    for (var r = 1; r < rowCount; r++) {
      final y = r * rowHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), rowPaint);
    }
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
      old.todayX != todayX ||
      old.rowCount != rowCount;
}

class _TimelineBar extends StatelessWidget {
  const _TimelineBar({
    required this.task,
    required this.width,
    required this.fraction,
    this.conflict = false,
  });

  final Issue task;
  final double width;
  final double fraction;

  /// Starts before the issue blocking it is finished.
  final bool conflict;

  @override
  Widget build(BuildContext context) {
    final color = task.resolved
        ? AppColors.stDone
        : AppColors.stateColor(task.state.toUpperCase());
    return Container(
      width: width,
      height: 24,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
        border: conflict ? Border.all(color: AppColors.danger, width: 2) : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: fraction,
              child: Container(color: Colors.white.withValues(alpha: 0.22)),
            ),
          ),
          if (width > 28)
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
