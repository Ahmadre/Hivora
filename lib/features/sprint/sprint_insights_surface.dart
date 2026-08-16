import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/models/work_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/hive_widgets.dart';
import 'sprint_format.dart';
import 'sprint_tokens.dart';
import 'widgets/burndown_chart.dart';

/// Insights surface: summary stats, an animated burndown, velocity history,
/// per-assignee work breakdown and the scope-change log — all from the
/// server-computed [SprintReport].
class SprintInsightsSurface extends StatelessWidget {
  const SprintInsightsSurface({
    super.key,
    required this.report,
    required this.loading,
    required this.error,
    required this.names,
    required this.onRetry,
  });

  final SprintReport? report;
  final bool loading;
  final String? error;
  final Map<String, String> names;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading && report == null) {
      return const Center(child: HiveLoader());
    }
    if (error != null && report == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error!, style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onRetry,
              child: Text(context.t('common.retry')),
            ),
          ],
        ),
      );
    }
    final r = report;
    if (r == null) return const SizedBox.shrink();

    final gutter = context.pageGutter;
    final wide = !context.isCompact;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        gutter,
        0,
        gutter,
        gutter + context.bottomGutter,
      ),
      children: [
        _summary(context, r.summary),
        const SizedBox(height: 14),
        _twoUp(
          wide: wide,
          wideLeftFlex: 2,
          left: _BurndownCard(
            points: r.burndown,
            top: r.summary.committed.toDouble(),
            remaining: r.summary.remaining,
          ),
          right: _VelocityCard(points: r.velocity),
        ),
        const SizedBox(height: 14),
        _twoUp(
          wide: wide,
          wideLeftFlex: 2,
          left: _BreakdownCard(breakdown: r.breakdown, names: names),
          right: _ScopeCard(scope: r.scope),
        ),
      ],
    );
  }

  Widget _twoUp({
    required bool wide,
    required Widget left,
    required Widget right,
    int wideLeftFlex = 1,
  }) {
    if (!wide) {
      return Column(children: [left, const SizedBox(height: 14), right]);
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: wideLeftFlex, child: left),
          const SizedBox(width: 14),
          Expanded(child: right),
        ],
      ),
    );
  }

  Widget _summary(BuildContext context, SprintSummary s) {
    final cards = [
      _StatCard(
        icon: LucideIcons.circleDot,
        label: context.t('sprint.committed'),
        value: '${s.committed}',
        sub: context.t('sprint.storyPoints'),
      ),
      _StatCard(
        icon: LucideIcons.circleCheck,
        label: context.t('sprint.completed'),
        value: '${s.completed}',
        valueColor: SprintTokens.done,
        sub: context.t(
          'sprint.percentOfCommitment',
          variables: {
            'percent':
                '${s.committed == 0 ? 0 : (s.completed / s.committed * 100).round()}',
          },
        ),
      ),
      _StatCard(
        icon: LucideIcons.flame,
        label: context.t('sprint.remaining'),
        value: '${s.remaining}',
        sub: context.t('sprint.pointsWord'),
      ),
      _StatCard(
        icon: LucideIcons.gauge,
        label: context.t('sprint.avgVelocity'),
        value: '${s.avgVelocity}',
        sub: context.t('sprint.lastSprints'),
      ),
    ];
    // 4-up on wide, 2-up otherwise — never overflows.
    final perRow = context.isExpanded ? 4 : 2;
    return LayoutBuilder(
      builder: (context, c) {
        const spacing = 14.0;
        final width = (c.maxWidth - spacing * (perRow - 1)) / perRow;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final card in cards) SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = const EdgeInsets.all(18)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppColors.hairline),
      ),
      child: child,
    );
  }
}

class _SectionHead extends StatelessWidget {
  const _SectionHead({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontFamily: AppTheme.fontBrand,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
            ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.sub,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final String sub;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return _Card(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: AppColors.inkSoft),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.inkSoft,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontFamily: AppTheme.fontBrand,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: valueColor ?? AppColors.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
          ),
        ],
      ),
    );
  }
}

class _BurndownCard extends StatelessWidget {
  const _BurndownCard({
    required this.points,
    required this.top,
    required this.remaining,
  });

  final List<BurndownPoint> points;
  final double top;
  final int remaining;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHead(
            title: context.t('sprint.burndown'),
            trailing: context.t(
              'sprint.ptsRemaining',
              variables: {'points': '$remaining'},
            ),
          ),
          if (points.isEmpty)
            _noData(context)
          else
            BurndownChart(points: points, top: top),
          const SizedBox(height: 8),
          Row(
            children: [
              _legend(
                context.t('sprint.actual'),
                AppColors.accentStrong,
                false,
              ),
              const SizedBox(width: 18),
              _legend(context.t('sprint.guideline'), AppColors.inkFaint, true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legend(String label, Color color, bool dashed) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 16,
          height: 2,
          child: dashed
              ? CustomPaint(painter: _DashLegendPainter(color))
              : ColoredBox(color: color),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft)),
      ],
    );
  }

  Widget _noData(BuildContext context) => SizedBox(
    height: 200,
    child: Center(
      child: Text(
        context.t('sprint.noBurndown'),
        style: TextStyle(fontSize: 12.5, color: AppColors.inkFaint),
      ),
    ),
  );
}

class _DashLegendPainter extends CustomPainter {
  _DashLegendPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset((x + 4).clamp(0, size.width), size.height / 2),
        paint,
      );
      x += 7;
    }
  }

  @override
  bool shouldRepaint(_DashLegendPainter old) => old.color != color;
}

class _VelocityCard extends StatelessWidget {
  const _VelocityCard({required this.points});

  final List<VelocityPoint> points;

  @override
  Widget build(BuildContext context) {
    final maxVal = points.fold<int>(
      1,
      (m, v) => [m, v.committed, v.completed].reduce((a, b) => a > b ? a : b),
    );
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHead(
            title: context.t('sprint.velocity'),
            trailing: context.t('sprint.committedDone'),
          ),
          SizedBox(
            height: 170,
            child: points.isEmpty
                ? Center(
                    child: Text(
                      context.t('sprint.noVelocity'),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.inkFaint,
                      ),
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final v in points)
                        Expanded(
                          child: _VelocityBar(
                            committed: v.committed,
                            completed: v.completed,
                            maxVal: maxVal,
                            label: _shortLabel(v.name),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  String _shortLabel(String name) {
    final m = RegExp(r'(\d+)').allMatches(name).lastOrNull;
    return m != null ? 'S${m.group(1)}' : name;
  }
}

class _VelocityBar extends StatelessWidget {
  const _VelocityBar({
    required this.committed,
    required this.completed,
    required this.maxVal,
    required this.label,
  });

  final int committed;
  final int completed;
  final int maxVal;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              final h = c.maxHeight;
              return Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  Container(
                    width: 18,
                    height: (committed / maxVal) * h,
                    decoration: BoxDecoration(
                      color: AppColors.canvas2,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 700),
                    curve: hiveEase,
                    tween: Tween(begin: 0, end: (completed / maxVal) * h),
                    builder: (_, value, _) => Container(
                      width: 18,
                      height: value,
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: TextStyle(
            fontFamily: AppTheme.fontMono,
            fontSize: 10.5,
            color: AppColors.inkSoft,
          ),
        ),
      ],
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({required this.breakdown, required this.names});

  final List<AssigneeLoad> breakdown;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHead(title: context.t('sprint.workBreakdown')),
          if (breakdown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(
                context.t('sprint.noBreakdown'),
                style: TextStyle(fontSize: 12.5, color: AppColors.inkFaint),
              ),
            )
          else
            for (final a in breakdown)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    if (a.userId.isEmpty)
                      CircleAvatar(
                        radius: 13,
                        backgroundColor: AppColors.canvas2,
                        child: Icon(
                          LucideIcons.user,
                          size: 15,
                          color: AppColors.inkFaint,
                        ),
                      )
                    else
                      // The label beside it already resolves the name; the
                      // avatar must not fall back to the raw id, whose
                      // "initial" is a digit shared by every user.
                      HiveAvatar(name: names[a.userId] ?? a.userId, size: 26),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 110,
                      child: Text(
                        a.userId.isEmpty
                            ? context.t('sprint.unassigned')
                            : (names[a.userId] ?? a.userId),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: HiveProgress(
                        value: a.total == 0 ? 0 : a.done / a.total,
                        height: 7,
                        color: SprintTokens.done,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${a.done}/${a.total} pts',
                      style: TextStyle(
                        fontFamily: AppTheme.fontMono,
                        fontSize: 11.5,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _ScopeCard extends StatelessWidget {
  const _ScopeCard({required this.scope});

  final List<SprintScopeChange> scope;

  @override
  Widget build(BuildContext context) {
    final net = scope.fold<int>(0, (s, c) => s + c.delta);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHead(title: context.t('sprint.scopeChanges')),
          if (scope.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(
                context.t('sprint.noScope'),
                style: TextStyle(fontSize: 12.5, color: AppColors.inkFaint),
              ),
            )
          else ...[
            for (final c in scope)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    SizedBox(
                      width: 52,
                      child: Text(
                        c.date != null ? shortDate(c.date!) : '—',
                        style: TextStyle(
                          fontFamily: AppTheme.fontMono,
                          fontSize: 11,
                          color: AppColors.inkFaint,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 38,
                      child: Text(
                        '${c.delta > 0 ? '+' : ''}${c.delta}',
                        style: TextStyle(
                          fontFamily: AppTheme.fontMono,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          // Added scope = red (more work); removed = green.
                          color: c.delta > 0
                              ? AppColors.danger
                              : AppColors.success,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        c.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Text(
              context.t(
                'sprint.netScope',
                variables: {'delta': '${net > 0 ? '+' : ''}$net'},
              ),
              style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
            ),
          ],
        ],
      ),
    );
  }
}
