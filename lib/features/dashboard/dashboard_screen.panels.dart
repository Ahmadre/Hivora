part of 'dashboard_screen.dart';

// ══════════════════════════ Focus list ═════════════════════════════════════

class _FocusCard extends StatelessWidget {
  const _FocusCard({required this.issues});
  final List<Issue> issues;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHead(
            title: context.t('dashboard.focus'),
            actionLabel: context.t('dashboard.allIssues'),
            onAction: () => context.go('/issues'),
          ),
          const SizedBox(height: 14),
          if (issues.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(
                context.t('dashboard.noTasks'),
                style: TextStyle(color: AppColors.inkSoft),
              ),
            )
          else
            for (final issue in issues.take(5))
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: _FocusItem(issue: issue),
              ),
        ],
      ),
    );
  }
}

class _FocusItem extends StatelessWidget {
  const _FocusItem({required this.issue});
  final Issue issue;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final compact = context.isCompact;
    final hasEstimate =
        issue.estimateMinutes != null && issue.estimateMinutes! > 0;
    final progress = hasEstimate
        ? (issue.spentMinutes / issue.estimateMinutes!).clamp(0.0, 1.0)
        : 0.0;
    final due = dueLabel(context, issue.dueDate);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        // No onChanged: the detail sheet broadcasts on IssueEvents, which the
        // dashboard already listens to — passing both reloads twice.
        onTap: () => showIssueDetailSheet(context, issueId: issue.id),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: _innerTile(dark),
          child: Row(
            children: [
              TypeGlyph(type: issue.type, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      issue.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        IdMono(issue.readableId),
                        if (due != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            due.text,
                            style: TextStyle(
                              fontFamily: AppTheme.fontMono,
                              fontSize: 11,
                              color: due.late
                                  ? AppColors.danger
                                  : AppColors.inkFaint,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (!compact && hasEstimate) ...[
                const SizedBox(width: 10),
                SizedBox(
                  width: 64,
                  child: HiveProgress(value: progress, height: 5),
                ),
              ],
              const SizedBox(width: 10),
              if (issue.assigneeId != null) _Assignee(issue: issue),
            ],
          ),
        ),
      ),
    );
  }
}

/// The focus list is "assigned to me", so the row's assignee is the signed-in
/// user — take their name and picture from the session rather than rendering
/// the raw assignee id, whose "initial" is a hex digit every account shares.
/// A secondary-assignee row (someone else holds the primary slot) falls back to
/// the neutral avatar placeholder.
class _Assignee extends StatelessWidget {
  const _Assignee({required this.issue});

  final Issue issue;

  @override
  Widget build(BuildContext context) {
    final me = context.select((AuthBloc bloc) => bloc.state.user);
    final mine = me != null && me.id == issue.assigneeId;
    return Tooltip(
      // This tile only ever knows the signed-in user by name, so the pronouns
      // join its existing tooltip rather than nesting a second one.
      message: mine
          ? personTooltip(name: me.displayName, pronouns: me.pronouns)
          : context.t('issues.assignee'),
      child: HiveAvatar(
        name: mine ? me.displayName : issue.assigneeId!,
        imageUrl: mine ? me.avatarUrl : null,
        size: 26,
      ),
    );
  }
}

// ══════════════════════════ Completion donut ═══════════════════════════════

class _CompletionCard extends StatelessWidget {
  const _CompletionCard({required this.completion});
  final ProjectCompletion completion;

  @override
  Widget build(BuildContext context) {
    final segs = <(String, int, Color)>[
      (context.t('dashboard.done'), completion.done, _cDone),
      (context.t('dashboard.inProgress'), completion.inProgress, _cProgress),
      (context.t('dashboard.backlog'), completion.backlog, _cBacklog),
    ];
    final total = completion.total;
    final donePct = (completion.donePercent * 100).round();
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHead(
            title: context.t('dashboard.projectProgress'),
            subLabel: context.t(
              'dashboard.issuesCount',
              variables: {'count': '$total'},
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              SizedBox(
                width: 132,
                height: 132,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: total == 0 ? 0.0 : 1.0),
                      duration: const Duration(milliseconds: 1200),
                      curve: hiveEase,
                      builder: (_, t, _) => RepaintBoundary(
                        child: CustomPaint(
                          size: const Size.square(132),
                          painter: _DonutPainter([
                            for (final (_, v, c) in segs) (v.toDouble(), c),
                          ], t),
                        ),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _CountUp(
                          value: donePct,
                          style: TextStyle(
                            fontFamily: AppTheme.fontBrand,
                            fontSize: 23,
                            fontWeight: FontWeight.w700,
                            height: 1,
                            color: AppColors.ink,
                          ),
                        ),
                        Text(
                          context.t('dashboard.resolved'),
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.inkFaint,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 22),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (label, value, color) in segs)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: Row(
                          children: [
                            Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                label,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.inkSoft,
                                ),
                              ),
                            ),
                            Text(
                              '${total == 0 ? 0 : (value / total * 100).round()}%',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.segments, this.t);
  final List<(double, Color)> segments;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 15.0;
    final center = size.center(Offset.zero);
    final radius = (size.width - stroke) / 2;
    final total = segments.fold<double>(0, (s, e) => s + e.$1);
    if (total <= 0 || t <= 0) return;
    const gap = 0.07;
    double start = -math.pi / 2;
    for (final (value, color) in segments) {
      if (value <= 0) continue;
      final frac = value / total;
      final full = 2 * math.pi * frac;
      final sweep = math.max(0.0, full - gap) * t;
      if (sweep > 0) {
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = color;
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          start,
          sweep,
          false,
          paint,
        );
      }
      start += full;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.t != t || old.segments != segments;
}

// ══════════════════════════ Focus-time tracker ═════════════════════════════

class _TrackerCard extends StatefulWidget {
  const _TrackerCard({required this.week, required this.month});
  final List<TrackerDay> week;
  final List<TrackerWeek> month;

  @override
  State<_TrackerCard> createState() => _TrackerCardState();
}

class _TrackerCardState extends State<_TrackerCard> {
  int _range = 0; // 0 = week, 1 = month

  @override
  Widget build(BuildContext context) {
    final monthly = _range == 1 && widget.month.isNotEmpty;
    final bars = <_BarData>[];
    if (monthly) {
      for (var i = 0; i < widget.month.length; i++) {
        final w = widget.month[i];
        bars.add(
          _BarData(
            label: context.t(
              'dashboard.weekLabel',
              variables: {'n': '${w.week}'},
            ),
            minutes: w.focusMinutes,
            today: i == widget.month.length - 1,
          ),
        );
      }
    } else {
      final code = Localizations.localeOf(context).languageCode;
      for (var i = 0; i < widget.week.length; i++) {
        final d = widget.week[i];
        String label;
        try {
          label = DateFormat.E(code).format(d.date);
        } catch (_) {
          label = DateFormat.E().format(d.date);
        }
        bars.add(
          _BarData(
            label: label.replaceAll('.', ''),
            minutes: d.focusMinutes,
            today: i == widget.week.length - 1,
          ),
        );
      }
    }
    final totalMinutes = bars.fold<int>(0, (s, b) => s + b.minutes);
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.t('dashboard.focusTime'),
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              Text(
                context.t(
                  'dashboard.hours',
                  variables: {'value': _hours(context, totalMinutes)},
                ),
                style: TextStyle(
                  fontFamily: AppTheme.fontMono,
                  fontSize: 12,
                  color: AppColors.inkSoft,
                ),
              ),
              const SizedBox(width: 10),
              _Segmented(
                options: [
                  context.t('dashboard.week'),
                  context.t('dashboard.month'),
                ],
                index: _range,
                onChanged: (i) => setState(() => _range = i),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(height: 150, child: _Bars(bars: bars)),
        ],
      ),
    );
  }

  String _hours(BuildContext context, int minutes) {
    final v = (minutes / 60).toStringAsFixed(1);
    return Localizations.localeOf(context).languageCode == 'de'
        ? v.replaceAll('.', ',')
        : v;
  }
}

class _BarData {
  const _BarData({
    required this.label,
    required this.minutes,
    required this.today,
  });
  final String label;
  final int minutes;
  final bool today;
}

class _Bars extends StatelessWidget {
  const _Bars({required this.bars});
  final List<_BarData> bars;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final max = bars.fold<int>(1, (m, b) => b.minutes > m ? b.minutes : m);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final b in bars)
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final areaH = c.maxHeight - 24;
                final frac = b.minutes / max;
                final target = math.max(
                  frac * areaH,
                  b.minutes > 0 ? 8.0 : 3.0,
                );
                return Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: target),
                      duration: const Duration(milliseconds: 900),
                      curve: hiveEase,
                      builder: (_, h, _) => Container(
                        width: 20,
                        height: h,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          gradient: b.today
                              ? const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [_cAmberHi, _cAmberLo],
                                )
                              : null,
                          color: b.today
                              ? null
                              : (dark
                                    ? Colors.white.withValues(alpha: .22)
                                    : AppColors.navy.withValues(alpha: .75)),
                          boxShadow: b.today
                              ? [
                                  BoxShadow(
                                    color: AppColors.accent.withValues(
                                      alpha: .4,
                                    ),
                                    blurRadius: 12,
                                    offset: const Offset(0, 3),
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      b.label,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                        fontFamily: AppTheme.fontMono,
                        fontSize: 10.5,
                        color: b.today
                            ? AppColors.accentStrong
                            : AppColors.inkFaint,
                        fontWeight: b.today ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented({
    required this.options,
    required this.index,
    required this.onChanged,
  });
  final List<String> options;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: .06)
            : Colors.black.withValues(alpha: .04),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, label) in options.indexed)
            GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: hiveEase,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: i == index ? AppColors.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: i == index
                        ? const Color(0xFF2A2410)
                        : AppColors.inkSoft,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ══════════════════════════ Git activity ═══════════════════════════════════

class _GitCard extends StatelessWidget {
  const _GitCard({required this.events});
  final List<GitEvent> events;

  @override
  Widget build(BuildContext context) {
    final repo = events
        .map((e) => e.repo)
        .firstWhere((r) => r != null && r.isNotEmpty, orElse: () => null);
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHead(title: context.t('dashboard.gitActivity'), subLabel: repo),
          const SizedBox(height: 8),
          for (final e in events.take(5))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: _GitRow(event: e),
            ),
        ],
      ),
    );
  }
}

class _GitRow extends StatelessWidget {
  const _GitRow({required this.event});
  final GitEvent event;

  @override
  Widget build(BuildContext context) {
    final (icon, hue) = _kindStyle(event.kind);
    final compact = context.isCompact;
    final meta = [
      if ((event.repo ?? '').isNotEmpty) event.repo!,
      if (event.at != null) _rel(event.at!),
      if ((event.authorName ?? '').isNotEmpty) event.authorName!,
    ].join(' · ');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: hue.withValues(alpha: .13),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 15, color: hue),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: event.ref,
                      style: const TextStyle(
                        fontFamily: AppTheme.fontMono,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accentStrong,
                      ),
                    ),
                    TextSpan(
                      text: '  ·  ${event.text}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
                ),
              ],
            ],
          ),
        ),
        if (!compact && (event.issueKey ?? '').isNotEmpty) ...[
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: AppColors.hairline2),
            ),
            child: IdMono(event.issueKey!),
          ),
        ],
      ],
    );
  }

  (IconData, Color) _kindStyle(String kind) => switch (kind) {
    'pr' => (LucideIcons.eye, _cToday),
    'deploy' => (LucideIcons.rocket, _cDone),
    'merge' => (LucideIcons.circleCheckBig, const Color(0xFFA45CC7)),
    _ => (LucideIcons.circleDot, AppColors.accentStrong),
  };

  String _rel(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }
}

// ══════════════════════════ Team ranking ═══════════════════════════════════

class _LeaderboardCard extends StatelessWidget {
  const _LeaderboardCard({required this.ranking});
  final List<RankEntry> ranking;

  @override
  Widget build(BuildContext context) {
    final shown = ranking.take(5).toList();
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHead(
            title: context.t('dashboard.teamRanking'),
            subLabel: context.t('dashboard.thisWeek'),
          ),
          const SizedBox(height: 6),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                context.t('dashboard.noRanking'),
                style: TextStyle(color: AppColors.inkSoft),
              ),
            ),
          for (final (i, entry) in shown.indexed)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                border: i == shown.length - 1
                    ? null
                    : Border(bottom: BorderSide(color: AppColors.hairline2)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    child: i == 0
                        ? const Icon(
                            LucideIcons.star,
                            size: 14,
                            color: AppColors.accentStrong,
                          )
                        : Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontFamily: AppTheme.fontMono,
                              fontSize: 12,
                              color: AppColors.inkFaint,
                            ),
                          ),
                  ),
                  HiveAvatar(
                    name: entry.displayName,
                    imageUrl: entry.avatarUrl,
                    pronouns: entry.pronouns,
                    size: 30,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (entry.title != null)
                          Text(
                            entry.title!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.inkSoft,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    context.t(
                      'dashboard.pointsShort',
                      variables: {'count': '${entry.points}'},
                    ),
                    style: const TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accentStrong,
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
