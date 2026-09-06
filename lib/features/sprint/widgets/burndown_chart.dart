import 'package:flutter/material.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/work_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';

/// Sprint burndown: dashed guideline (committed → 0) with the solid actual line
/// drawn only up to today, animated in via a stroke reveal. Honours
/// `prefers-reduced-motion` (no draw-on). Mirrors `view_sprint.jsx` insights.
class BurndownChart extends StatefulWidget {
  const BurndownChart({super.key, required this.points, required this.top});

  final List<BurndownPoint> points;

  /// Y-axis maximum (committed story points at sprint start).
  final double top;

  @override
  State<BurndownChart> createState() => _BurndownChartState();
}

class _BurndownChartState extends State<BurndownChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return SizedBox(
      height: 240,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _BurndownPainter(
            points: widget.points,
            top: widget.top <= 0 ? 1 : widget.top,
            progress: reduceMotion ? 1 : _controller.value,
            grid: AppColors.hairline,
            axis: AppColors.inkFaint,
            ideal: AppColors.inkFaint,
            actual: AppColors.accentStrong,
            textColor: AppColors.inkFaint,
            startTick: context.t('sprint.burndownStart'),
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _BurndownPainter extends CustomPainter {
  _BurndownPainter({
    required this.points,
    required this.top,
    required this.progress,
    required this.grid,
    required this.axis,
    required this.ideal,
    required this.actual,
    required this.textColor,
    required this.startTick,
  });

  final List<BurndownPoint> points;
  final double top;
  final double progress;
  final Color grid;
  final Color axis;
  final Color ideal;
  final Color actual;
  final Color textColor;

  /// Localised one-letter tick for the sprint's first day (`S`, `A`, `н` …).
  final String startTick;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    const padLeft = 26.0;
    const padTop = 8.0;
    const padBottom = 20.0;
    const padRight = 8.0;
    final plotW = size.width - padLeft - padRight;
    final plotH = size.height - padTop - padBottom;
    final lastDay = points.last.day == 0 ? 1 : points.last.day;

    double xOf(int day) => padLeft + (day / lastDay) * plotW;
    double yOf(double value) =>
        padTop + (1 - (value / top).clamp(0.0, 1.0)) * plotH;

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    final textStyle = TextStyle(
      fontFamily: AppTheme.fontMono,
      fontSize: 10,
      color: textColor,
    );

    // Horizontal grid lines + Y ticks at 0/¼/½/¾/1.
    for (final g in [0.0, 0.25, 0.5, 0.75, 1.0]) {
      final y = yOf(top * g);
      canvas.drawLine(
        Offset(padLeft, y),
        Offset(size.width - padRight, y),
        gridPaint,
      );
      _text(canvas, '${(top * g).round()}', Offset(0, y - 6), textStyle);
    }
    // X ticks: S, 1..n
    for (final p in points) {
      final label = p.day == 0 ? startTick : '${p.day}';
      _text(
        canvas,
        label,
        Offset(xOf(p.day) - 4, size.height - 14),
        textStyle,
        maxWidth: 16,
        center: true,
      );
    }

    // Dashed guideline (ideal).
    final idealPath = Path();
    for (var i = 0; i < points.length; i++) {
      final o = Offset(xOf(points[i].day), yOf(points[i].ideal));
      if (i == 0) {
        idealPath.moveTo(o.dx, o.dy);
      } else {
        idealPath.lineTo(o.dx, o.dy);
      }
    }
    _drawDashed(
      canvas,
      idealPath,
      Paint()
        ..color = ideal
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );

    // Solid actual line up to today (points with a non-null remaining).
    final actualPts = [
      for (final p in points)
        if (p.remaining != null) Offset(xOf(p.day), yOf(p.remaining!)),
    ];
    if (actualPts.length >= 2) {
      final reveal = (actualPts.length - 1) * progress;
      final path = Path()..moveTo(actualPts.first.dx, actualPts.first.dy);
      for (var i = 1; i < actualPts.length; i++) {
        final seg = (reveal - (i - 1)).clamp(0.0, 1.0);
        if (seg <= 0) break;
        final a = actualPts[i - 1];
        final b = actualPts[i];
        path.lineTo(a.dx + (b.dx - a.dx) * seg, a.dy + (b.dy - a.dy) * seg);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = actual
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
    }
    // Dots on elapsed points (fade in with the reveal).
    final dotPaint = Paint()..color = actual;
    for (var i = 0; i < actualPts.length; i++) {
      final appear = (progress * actualPts.length) - i;
      if (appear <= 0) continue;
      canvas.drawCircle(actualPts[i], 3.5, dotPaint);
    }
  }

  void _text(
    Canvas canvas,
    String text,
    Offset at,
    TextStyle style, {
    double maxWidth = 24,
    bool center = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: center ? TextAlign.center : TextAlign.left,
    )..layout(maxWidth: maxWidth);
    tp.paint(canvas, at);
  }

  void _drawDashed(Canvas canvas, Path path, Paint paint) {
    const dash = 5.0;
    const gap = 5.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final end = (d + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(d, end), paint);
        d = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_BurndownPainter old) =>
      old.progress != progress ||
      old.points != points ||
      old.top != top ||
      old.startTick != startTick;
}
