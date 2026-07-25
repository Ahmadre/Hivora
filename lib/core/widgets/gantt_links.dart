/// Dependency connectors for the timeline / Gantt views.
///
/// Everything here is model-agnostic: a screen hands over plain [GanttRow]s (the
/// Gantt screen builds them from `GanttTask`, the board timeline from `Issue`)
/// plus the project's [GanttLink] graph, and gets back the drawable geometry —
/// bar slots, routed connectors, schedule conflicts and the critical path.
///
/// The vocabulary follows the classic Gantt reading of a chart:
/// * a **dependency** is a `BLOCKS` link — a finish-to-start constraint, drawn
///   solid with an arrow head pointing into the blocked bar;
/// * every other link type is **informational** (relates to, duplicates,
///   tests …) and is drawn as a faint dash, off by default;
/// * a **conflict** is a dependency whose blocked issue starts on or before its
///   blocker finishes — the schedule cannot hold, so the connector turns red;
/// * the **critical path** is the longest chain of dependencies; delaying any
///   issue on it delays everything downstream.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../i18n/i18n.dart';
import '../models/work_models.dart';
import '../theme/app_colors.dart';

/// Half the footprint of a milestone diamond, in pixels — the anchor a
/// connector aims at instead of a bar edge. A [GanttMilestone] of the default
/// size rotated 45° reaches roughly this far from its centre.
const double kGanttMilestoneRadius = 10.5;

/// One row on a chart, reduced to what the connector maths needs.
class GanttRow {
  const GanttRow({required this.id, required this.from, required this.to});

  final String id;

  /// First day covered (inclusive).
  final DateTime from;

  /// Last day covered (inclusive).
  final DateTime to;

  /// A zero-length item — a deadline rather than a stretch of work.
  bool get isMilestone => !to.isAfter(from);

  int get days => to.difference(from).inDays + 1;
}

/// Where a row's bar sits on the chart, in chart-local pixels.
class GanttSlot {
  const GanttSlot({
    required this.id,
    required this.row,
    required this.left,
    required this.right,
    required this.isMilestone,
  });

  final String id;
  final int row;
  final double left;
  final double right;
  final bool isMilestone;

  double centerY(double rowHeight) => row * rowHeight + rowHeight / 2;
}

/// A connector between two slots, ready to paint.
class GanttEdge {
  const GanttEdge({
    required this.link,
    required this.from,
    required this.to,
    required this.conflict,
  });

  final GanttLink link;
  final GanttSlot from;
  final GanttSlot to;

  /// The blocked issue starts before its blocker finishes.
  final bool conflict;

  bool get isDependency => link.isDependency;

  bool touches(String id) => from.id == id || to.id == id;
}

/// What the chart draws on top of the bars.
class GanttLinkOptions {
  const GanttLinkOptions({
    this.showDependencies = true,
    this.showRelated = false,
    this.showCriticalPath = false,
  });

  /// `BLOCKS` connectors — the ones that actually constrain the schedule.
  final bool showDependencies;

  /// Every other link type, as faint dashes.
  final bool showRelated;

  /// Emphasise the longest dependency chain.
  final bool showCriticalPath;

  bool get anyLinks => showDependencies || showRelated;

  GanttLinkOptions copyWith({
    bool? showDependencies,
    bool? showRelated,
    bool? showCriticalPath,
  }) => GanttLinkOptions(
    showDependencies: showDependencies ?? this.showDependencies,
    showRelated: showRelated ?? this.showRelated,
    showCriticalPath: showCriticalPath ?? this.showCriticalPath,
  );
}

/// The link graph of one rendered chart: slot geometry, routed edges, schedule
/// conflicts and the critical path. Built once per layout pass.
class GanttGraph {
  GanttGraph._({
    required this.slots,
    required this.edges,
    required this.conflictIds,
    required this.criticalIds,
    required Map<String, Set<String>> neighbours,
  }) : _neighbours = neighbours;

  /// Builds the graph for [rows] (in render order — index = chart row) against
  /// [links]. Links pointing at rows that aren't on the chart are dropped: a
  /// connector needs both ends to have somewhere to land.
  factory GanttGraph.build({
    required List<GanttRow> rows,
    required List<GanttLink> links,
    required DateTime chartStart,
    required double pxPerDay,
    double minBarWidth = 8,
  }) {
    final slots = <String, GanttSlot>{};
    final byId = <String, GanttRow>{};
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      byId[row.id] = row;
      final left = row.from.difference(chartStart).inDays * pxPerDay;
      if (row.isMilestone) {
        // A diamond has no length: give it the marker's own footprint so
        // connectors land on its tips, whatever the zoom does to a day's width.
        final center = left + pxPerDay / 2;
        const half = kGanttMilestoneRadius;
        slots[row.id] = GanttSlot(
          id: row.id,
          row: i,
          left: center - half,
          right: center + half,
          isMilestone: true,
        );
      } else {
        slots[row.id] = GanttSlot(
          id: row.id,
          row: i,
          left: left,
          right: left + math.max(row.days * pxPerDay, minBarWidth),
          isMilestone: false,
        );
      }
    }

    final edges = <GanttEdge>[];
    final conflictIds = <String>{};
    final neighbours = <String, Set<String>>{};
    for (final link in links) {
      final from = slots[link.sourceId];
      final to = slots[link.targetId];
      if (from == null || to == null || from.id == to.id) continue;
      // Finish-to-start: the blocked issue may only begin after its blocker's
      // last day. Anything else is a conflict the chart should shout about.
      final conflict =
          link.isDependency && !byId[to.id]!.from.isAfter(byId[from.id]!.to);
      if (conflict) conflictIds.add(to.id);
      edges.add(GanttEdge(link: link, from: from, to: to, conflict: conflict));
      neighbours.putIfAbsent(from.id, () => <String>{}).add(to.id);
      neighbours.putIfAbsent(to.id, () => <String>{}).add(from.id);
    }

    return GanttGraph._(
      slots: slots,
      edges: edges,
      conflictIds: conflictIds,
      criticalIds: _criticalPath(byId, edges),
      neighbours: neighbours,
    );
  }

  final Map<String, GanttSlot> slots;
  final List<GanttEdge> edges;

  /// Issues that start before the issue blocking them is finished.
  final Set<String> conflictIds;

  /// Issues on the longest dependency chain — zero slack.
  final Set<String> criticalIds;

  final Map<String, Set<String>> _neighbours;

  bool get isEmpty => edges.isEmpty;

  int get dependencyCount => edges.where((e) => e.isDependency).length;

  int get relatedCount => edges.where((e) => !e.isDependency).length;

  /// [id] plus everything one hop away — the set kept bright in focus mode.
  Set<String> relatedTo(String id) => {id, ...?_neighbours[id]};

  /// Longest chain of finish-to-start dependencies, measured in days.
  ///
  /// A node is on the critical path when the longest chain running *through* it
  /// equals the longest chain in the whole graph — i.e. it has no slack. Cycles
  /// (which the link API permits) are cut by the visiting guard rather than
  /// hanging the layout pass.
  static Set<String> _criticalPath(
    Map<String, GanttRow> rows,
    List<GanttEdge> edges,
  ) {
    final deps = edges.where((e) => e.isDependency).toList();
    if (deps.isEmpty) return const {};

    final successors = <String, List<String>>{};
    final predecessors = <String, List<String>>{};
    for (final edge in deps) {
      successors.putIfAbsent(edge.from.id, () => []).add(edge.to.id);
      predecessors.putIfAbsent(edge.to.id, () => []).add(edge.from.id);
    }

    int days(String id) => rows[id]?.days ?? 0;

    final downstream = <String, int>{};
    final upstream = <String, int>{};

    int longest(
      String id,
      Map<String, List<String>> graph,
      Map<String, int> memo,
      Set<String> visiting,
    ) {
      final cached = memo[id];
      if (cached != null) return cached;
      if (!visiting.add(id)) return days(id); // cycle — stop unrolling
      var best = 0;
      for (final next in graph[id] ?? const <String>[]) {
        final value = longest(next, graph, memo, visiting);
        if (value > best) best = value;
      }
      visiting.remove(id);
      final total = days(id) + best;
      memo[id] = total;
      return total;
    }

    final ids = {...successors.keys, ...predecessors.keys};
    var longestChain = 0;
    final through = <String, int>{};
    for (final id in ids) {
      final ahead = longest(id, successors, downstream, <String>{});
      final behind = longest(id, predecessors, upstream, <String>{});
      final total = ahead + behind - days(id);
      through[id] = total;
      if (total > longestChain) longestChain = total;
    }
    if (longestChain == 0) return const {};
    return {
      for (final entry in through.entries)
        if (entry.value == longestChain) entry.key,
    };
  }
}

/// Paints the connectors of a [GanttGraph] behind the bars.
///
/// Routing is orthogonal, the way every Gantt tool draws it: out of the source's
/// right edge, along a lane, into the target's left edge. When the target starts
/// left of its blocker (the conflict case) the route dips into the gutter just
/// below the source row and travels back, so the line never disappears under a
/// bar.
class GanttLinksPainter extends CustomPainter {
  GanttLinksPainter({
    required this.graph,
    required this.rowHeight,
    required this.options,
    required this.baseColor,
    required this.conflictColor,
    required this.criticalColor,
    this.focusedId,
  });

  final GanttGraph graph;
  final double rowHeight;
  final GanttLinkOptions options;
  final Color baseColor;
  final Color conflictColor;
  final Color criticalColor;

  /// When set, only connectors touching this issue stay opaque.
  final String? focusedId;

  static const _stub = 11.0;
  static const _corner = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    for (final edge in graph.edges) {
      if (edge.isDependency
          ? !options.showDependencies
          : !options.showRelated) {
        continue;
      }
      final critical =
          options.showCriticalPath &&
          edge.isDependency &&
          graph.criticalIds.contains(edge.from.id) &&
          graph.criticalIds.contains(edge.to.id);
      final focused = focusedId == null || edge.touches(focusedId!);

      Color color;
      if (edge.conflict) {
        color = conflictColor;
      } else if (critical) {
        color = criticalColor;
      } else {
        color = baseColor;
      }
      var alpha = edge.isDependency ? 0.85 : 0.5;
      if (critical || edge.conflict) alpha = 1;
      if (!focused) alpha *= 0.16;
      color = color.withValues(alpha: alpha);

      final width = critical ? 2.2 : (edge.isDependency ? 1.5 : 1.1);
      final points = _route(edge);
      var path = _polyline(points, _corner);
      if (!edge.isDependency || edge.conflict) {
        path = _dashed(path, edge.conflict ? const [7, 4] : const [4, 4]);
      }

      final stroke = Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawPath(path, stroke);

      final fill = Paint()..color = color;
      // Origin dot on the blocker's finish, arrow head on the blocked start.
      canvas.drawCircle(points.first, width + 0.6, fill);
      _arrow(canvas, points[points.length - 2], points.last, width, fill);
    }
  }

  /// Orthogonal waypoints from the source's right edge to the target's left.
  List<Offset> _route(GanttEdge edge) {
    final y1 = edge.from.centerY(rowHeight);
    final y2 = edge.to.centerY(rowHeight);
    final start = Offset(edge.from.right, y1);
    final end = Offset(edge.to.left, y2);

    if (end.dx - start.dx >= _stub * 2) {
      final x = start.dx + _stub;
      return [start, Offset(x, y1), Offset(x, y2), end];
    }
    // Target sits left of (or right on top of) its blocker: leave the row, run
    // back through the gutter between two rows, then come in from the left.
    final lane = y1 + (y2 >= y1 ? rowHeight / 2 - 3 : -(rowHeight / 2 - 3));
    final outX = start.dx + _stub;
    final inX = end.dx - _stub;
    return [
      start,
      Offset(outX, y1),
      Offset(outX, lane),
      Offset(inX, lane),
      Offset(inX, y2),
      end,
    ];
  }

  /// Polyline with rounded corners, skipping degenerate segments.
  Path _polyline(List<Offset> raw, double radius) {
    final points = <Offset>[];
    for (final point in raw) {
      if (points.isEmpty || (point - points.last).distance > 0.01) {
        points.add(point);
      }
    }
    final path = Path();
    if (points.isEmpty) return path;
    path.moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length - 1; i++) {
      final previous = points[i - 1];
      final corner = points[i];
      final next = points[i + 1];
      final incoming = corner - previous;
      final outgoing = next - corner;
      final r = math.min(
        radius,
        math.min(incoming.distance, outgoing.distance) / 2,
      );
      final entry = corner - incoming / incoming.distance * r;
      final exit = corner + outgoing / outgoing.distance * r;
      path.lineTo(entry.dx, entry.dy);
      path.quadraticBezierTo(corner.dx, corner.dy, exit.dx, exit.dy);
    }
    path.lineTo(points.last.dx, points.last.dy);
    return path;
  }

  Path _dashed(Path source, List<double> pattern) {
    final out = Path();
    for (final metric in source.computeMetrics()) {
      var distance = 0.0;
      var index = 0;
      while (distance < metric.length) {
        final length = pattern[index % pattern.length];
        if (index.isEven) {
          out.addPath(
            metric.extractPath(
              distance,
              math.min(distance + length, metric.length),
            ),
            Offset.zero,
          );
        }
        distance += length;
        index++;
      }
    }
    return out;
  }

  void _arrow(Canvas canvas, Offset from, Offset to, double width, Paint fill) {
    final direction = to - from;
    if (direction.distance < 0.01) return;
    final unit = direction / direction.distance;
    final normal = Offset(-unit.dy, unit.dx);
    final length = 4.5 + width;
    final half = 2.6 + width / 2;
    final base = to - unit * length;
    canvas.drawPath(
      Path()
        ..moveTo(to.dx, to.dy)
        ..lineTo(base.dx + normal.dx * half, base.dy + normal.dy * half)
        ..lineTo(base.dx - normal.dx * half, base.dy - normal.dy * half)
        ..close(),
      fill,
    );
  }

  @override
  bool shouldRepaint(GanttLinksPainter old) =>
      !identical(old.graph, graph) ||
      old.rowHeight != rowHeight ||
      old.focusedId != focusedId ||
      old.baseColor != baseColor ||
      old.options.showDependencies != options.showDependencies ||
      old.options.showRelated != options.showRelated ||
      old.options.showCriticalPath != options.showCriticalPath;
}

/// Drop-in connector layer — put it in the chart's `Stack` between the grid and
/// the bars. Never takes pointer events; interaction belongs to the bars.
class GanttLinksLayer extends StatelessWidget {
  const GanttLinksLayer({
    super.key,
    required this.graph,
    required this.rowHeight,
    this.options = const GanttLinkOptions(),
    this.focusedId,
  });

  final GanttGraph graph;
  final double rowHeight;
  final GanttLinkOptions options;
  final String? focusedId;

  @override
  Widget build(BuildContext context) {
    if (graph.isEmpty || !options.anyLinks) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(
        painter: GanttLinksPainter(
          graph: graph,
          rowHeight: rowHeight,
          options: options,
          focusedId: focusedId,
          baseColor: AppColors.inkSoft,
          conflictColor: AppColors.danger,
          criticalColor: AppColors.accentStrong,
        ),
        size: Size.infinite,
      ),
    );
  }
}

/// The zero-duration marker every Gantt chart uses for a deadline: a diamond on
/// the day itself instead of a bar with no length.
class GanttMilestone extends StatelessWidget {
  const GanttMilestone({
    super.key,
    required this.color,
    this.size = 15,
    this.outlined = false,
  });

  final Color color;
  final double size;

  /// Draws the diamond hollow — used for a milestone that isn't done yet.
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: math.pi / 4,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: outlined ? AppColors.surface : color,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: color, width: 2),
        ),
      ),
    );
  }
}

/// Reads the connector styles back to the user. Shown inside the timeline's
/// view-options popover, where the toggles that produce them live.
class GanttLinkLegend extends StatelessWidget {
  const GanttLinkLegend({super.key, required this.options});

  final GanttLinkOptions options;

  @override
  Widget build(BuildContext context) {
    final entries = <(Color, bool, String)>[
      if (options.showDependencies)
        (AppColors.inkSoft, false, 'gantt.legend.dependency'),
      if (options.showRelated)
        (AppColors.inkSoft, true, 'gantt.legend.related'),
      if (options.showCriticalPath)
        (AppColors.accentStrong, false, 'gantt.legend.critical'),
      (AppColors.danger, true, 'gantt.legend.conflict'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (color, dashed, key) in entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                CustomPaint(
                  size: const Size(26, 10),
                  painter: _LegendLinePainter(color: color, dashed: dashed),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.t(key),
                    style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _LegendLinePainter extends CustomPainter {
  _LegendLinePainter({required this.color, required this.dashed});

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    if (dashed) {
      for (var x = 0.0; x < size.width - 8; x += 7) {
        canvas.drawLine(
          Offset(x, y),
          Offset(math.min(x + 4, size.width - 8), y),
          paint,
        );
      }
    } else {
      canvas.drawLine(Offset(0, y), Offset(size.width - 8, y), paint);
    }
    canvas.drawPath(
      Path()
        ..moveTo(size.width, y)
        ..lineTo(size.width - 6, y - 3.4)
        ..lineTo(size.width - 6, y + 3.4)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_LegendLinePainter old) =>
      old.color != color || old.dashed != dashed;
}
