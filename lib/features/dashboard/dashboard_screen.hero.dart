part of 'dashboard_screen.dart';

// ══════════════════════════ Glass card ═════════════════════════════════════

class _GlassCard extends StatelessWidget {
  const _GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(21),
    this.gradient,
    this.borderColor,
    this.onTap,
  });

  static const double _radius = 26;

  final Widget child;
  final EdgeInsets padding;
  final Gradient? gradient;
  final Color? borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fill = dark
        ? Colors.white.withValues(alpha: .09)
        : Colors.white.withValues(alpha: .55);
    final border = borderColor ??
        (dark
            ? Colors.white.withValues(alpha: .13)
            : Colors.white.withValues(alpha: .62));
    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? fill : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(color: border),
      ),
      child: child,
    );
    if (onTap != null) {
      content = Stack(
        // Passthrough, NOT the default loose fit: loose hands the decorated box
        // `loose(biggest)`, so it shrink-wraps its content and a tappable card
        // with little to say (the KPI tiles) draws a small pill inside its slot
        // while the Stack alone fills it. Passthrough forwards the card's own
        // constraints, exactly as the untappable branch below gets them.
        fit: StackFit.passthrough,
        children: [
          content,
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(_radius),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      );
    }
    // Frosted translucent fill — deliberately NO per-card BackdropFilter. The
    // app-wide AmbientBackground behind the dashboard is already heavily blurred
    // (σ90 blobs over a soft gradient), so a real-time backdrop blur here only
    // re-blurs an already low-frequency image: visually negligible, yet each is
    // a full gaussian pass that cannot be raster-cached (it samples the moving
    // backdrop as the list scrolls). Stacked across the up-to-7 dashboard cards
    // that was ~7 blur passes per frame, pushing raster past the 120 Hz
    // (8.33 ms) budget so the surface quantised to 60 fps — the whole reason the
    // dashboard sat at 60 while every other screen reached 120. Frost, border
    // and shadow are unchanged; only the redundant blur is gone.
    //
    // RepaintBoundary: the dashboard scrolls inside a SingleChildScrollView
    // which — unlike a sliver list — does NOT isolate its children, so without
    // this every card's fill, border, shadow and CustomPaint re-rasterised on
    // each scroll frame. Isolated, a card is cached once and merely
    // re-composited at its new offset while scrolling.
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_radius),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2D2B55).withValues(alpha: dark ? .48 : .26),
              blurRadius: 40,
              spreadRadius: -24,
              offset: const Offset(0, 22),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_radius),
          child: content,
        ),
      ),
    );
  }
}

BoxDecoration _innerTile(bool dark) => BoxDecoration(
      color: dark
          ? Colors.white.withValues(alpha: .045)
          : Colors.white.withValues(alpha: .5),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: dark
            ? Colors.white.withValues(alpha: .07)
            : Colors.white.withValues(alpha: .55),
      ),
    );

// ══════════════════════════ Greeting header ════════════════════════════════

class _Greeting extends StatelessWidget {
  const _Greeting({required this.sprint});
  final DashboardBoard? sprint;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthBloc>().state.user;
    final first = (user?.displayName ?? '').trim().split(' ').first;
    final hour = DateTime.now().hour;
    final key = hour < 11
        ? 'dashboard.greetMorning'
        : hour < 18
            ? 'dashboard.greetAfternoon'
            : 'dashboard.greetEvening';
    final greeting = context.t(key, variables: {'name': first}).trim();
    final date = _dateLabel(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          greeting.endsWith(',') ? greeting.substring(0, greeting.length - 1) : greeting,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: AppTheme.fontBrand,
            fontSize: context.isCompact ? 27 : 34,
            fontWeight: FontWeight.w800,
            height: 1.05,
            letterSpacing: -0.8,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 6),
        DefaultTextStyle(
          style: TextStyle(fontSize: 13.5, color: AppColors.inkSoft),
          child: (sprint != null && sprint!.isSprint && sprint!.days > 0)
              ? Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('$date · '),
                    Text(
                      context.t('dashboard.sprintDay', variables: {
                        'day': '${sprint!.day}',
                        'days': '${sprint!.days}',
                      }),
                      style: const TextStyle(
                        color: AppColors.accentStrong,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                )
              : Text(date),
        ),
      ],
    );
  }

  String _dateLabel(BuildContext context) {
    final code = Localizations.localeOf(context).languageCode;
    try {
      return DateFormat.MMMMEEEEd(code).format(DateTime.now());
    } catch (_) {
      return DateFormat.MMMMEEEEd().format(DateTime.now());
    }
  }
}

// ══════════════════════════ Sprint hero ════════════════════════════════════

class _SprintHero extends StatelessWidget {
  const _SprintHero({required this.sprint});
  final DashboardBoard sprint;

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    final ring = _ProgressRing(pct: sprint.progressPercent, size: compact ? 104 : 150);
    return _GlassCard(
      padding: EdgeInsets.all(compact ? 20 : 26),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xE01E1C3A), Color(0xD12D2B55)],
      ),
      borderColor: Colors.white.withValues(alpha: .14),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Honeycomb watermark: large + pushed far off the bottom-right corner
          // so only a soft curve shows — reads as texture, never a cut-off logo.
          const Positioned(
            right: -220,
            bottom: -240,
            child: IgnorePointer(
              child: Opacity(
                opacity: .07,
                child: HexMark(size: 460, color: AppColors.accent),
              ),
            ),
          ),
          if (compact)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Expanded(child: _badge(context)), ring],
                ),
                const SizedBox(height: 14),
                _body(context),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [_badge(context), const SizedBox(height: 14), _body(context)],
                  ),
                ),
                const SizedBox(width: 22),
                ring,
              ],
            ),
        ],
      ),
    );
  }

  Widget _badge(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            context.t(sprint.isSprint ? 'dashboard.activeSprint' : 'dashboard.kanbanBoard'),
            style: const TextStyle(
              fontFamily: AppTheme.fontMono,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: Color(0xFFEBCF8F),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(
          sprint.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: AppTheme.fontBrand,
            fontSize: 23,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: _heroInk,
          ),
        ),
        if ((sprint.goal ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            sprint.goal!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: Colors.white.withValues(alpha: .72),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (sprint.isSprint) ...[
              _chip(LucideIcons.calendarDays,
                  context.t('dashboard.dayChip', variables: {'day': '${sprint.day}', 'days': '${sprint.days}'})),
              _chip(LucideIcons.gauge,
                  context.t('dashboard.spChip', variables: {'done': '${sprint.points}', 'total': '${sprint.pointsTotal}'})),
            ],
            _chip(LucideIcons.circleCheck,
                context.t('dashboard.issuesChip', variables: {'done': '${sprint.issuesDone}', 'total': '${sprint.issuesTotal}'})),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            _boardButton(context),
            const SizedBox(width: 14),
            if (sprint.members.isNotEmpty)
              Flexible(child: _AvatarStack(members: sprint.members)),
          ],
        ),
      ],
    );
  }

  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: .12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white.withValues(alpha: .7)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontFamily: AppTheme.fontMono,
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: _heroInk,
            ),
          ),
        ],
      ),
    );
  }

  Widget _boardButton(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.go(
          sprint.boardId.isNotEmpty ? '/boards/${sprint.boardId}' : '/board',
        ),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFE4AC3E), Color(0xFFCE9526)]),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFD9A032).withValues(alpha: .35),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.columns3, size: 15, color: Color(0xFF2A2410)),
              const SizedBox(width: 8),
              Text(
                context.t('dashboard.toBoard'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2A2410),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SprintEmpty extends StatelessWidget {
  const _SprintEmpty();

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 24),
      child: Column(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(LucideIcons.goal, color: AppColors.accentStrong, size: 22),
          ),
          const SizedBox(height: 14),
          Text(
            context.t('dashboard.noSprint'),
            style: TextStyle(
              fontFamily: AppTheme.fontBrand,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.t('dashboard.noSprintMessage'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
          ),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: const Color(0xFF2A2410),
            ),
            onPressed: () => context.go('/board'),
            child: Text(context.t('dashboard.planSprint')),
          ),
        ],
      ),
    );
  }
}

class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.members});
  final List<SprintMember> members;

  static const _size = 30.0;
  static const _ring = 2.0;
  static const _outer = _size + _ring * 2; // 34 — ring sits outside the avatar
  static const _step = _outer * 0.68; // overlap; leaves the initials readable

  @override
  Widget build(BuildContext context) {
    final shown = members.take(5).toList();
    final extra = members.length - shown.length;
    final count = shown.length + (extra > 0 ? 1 : 0);
    if (count == 0) return const SizedBox.shrink();
    return SizedBox(
      height: _outer,
      width: _outer + (count - 1) * _step,
      child: Stack(
        children: [
          for (final (i, m) in shown.indexed)
            Positioned(
              left: i * _step,
              child: _ringed(HiveAvatar(name: m.displayName, imageUrl: m.avatarUrl, size: _size)),
            ),
          if (extra > 0)
            Positioned(
              left: shown.length * _step,
              child: _ringed(Container(
                width: _size,
                height: _size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: .16),
                ),
                child: Text(
                  '+$extra',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _heroInk),
                ),
              )),
            ),
        ],
      ),
    );
  }

  // A solid ring drawn *around* (not over) the avatar so initials stay intact.
  Widget _ringed(Widget child) => Container(
        padding: const EdgeInsets.all(_ring),
        decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF262450)),
        child: child,
      );
}

// ══════════════════════════ Progress ring ══════════════════════════════════

class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.pct, this.size = 148});
  final double pct;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: pct.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 1400),
        curve: hiveEase,
        builder: (_, v, _) => Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(size: Size.square(size), painter: _RingPainter(v)),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${(v * 100).round()}%',
                  style: TextStyle(
                    fontFamily: AppTheme.fontBrand,
                    fontSize: size < 120 ? 22 : 29,
                    fontWeight: FontWeight.w700,
                    height: 1,
                    color: _heroInk,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  context.t('dashboard.sprintCompleted'),
                  style: TextStyle(fontSize: 10.5, color: Colors.white.withValues(alpha: .7)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.pct);
  final double pct;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 11.0;
    final center = size.center(Offset.zero);
    final radius = (size.width - stroke) / 2;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: .13);
    canvas.drawCircle(center, radius, track);
    if (pct <= 0) return;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        colors: [_cAmberHi, _cAmberLo],
        transform: GradientRotation(-math.pi / 2),
      ).createShader(rect);
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * pct, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.pct != pct;
}

// ══════════════════════════ KPIs ═══════════════════════════════════════════

class _Kpis extends StatelessWidget {
  const _Kpis({
    required this.today,
    required this.completion,
    this.projectIds = const [],
  });
  final int today;
  final ProjectCompletion completion;

  /// The dashboard's active project scope, forwarded so the Issues page shows
  /// exactly the same set the counts were computed from.
  final List<String> projectIds;

  void _open(BuildContext context, String view) {
    final scope = projectIds.isEmpty ? '' : '&projects=${projectIds.join(',')}';
    context.go('/issues?view=$view$scope');
  }

  @override
  Widget build(BuildContext context) {
    final items = [
      _KpiCard(label: context.t('dashboard.kpiToday'), value: today, icon: LucideIcons.inbox, hue: _cToday, onTap: () => _open(context, 'today')),
      _KpiCard(label: context.t('dashboard.inProgress'), value: completion.inProgress, icon: LucideIcons.loader, hue: AppColors.accentStrong, onTap: () => _open(context, 'inprogress')),
      _KpiCard(label: context.t('dashboard.backlog'), value: completion.backlog, icon: LucideIcons.layers, hue: _cBacklog, onTap: () => _open(context, 'backlog')),
      _KpiCard(label: context.t('dashboard.done'), value: completion.done, icon: LucideIcons.circleCheckBig, hue: _cDone, onTap: () => _open(context, 'done')),
    ];
    if (context.isCompact) {
      return SizedBox(
        height: 104,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          padding: EdgeInsets.zero,
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (_, i) => SizedBox(width: 156, child: items[i]),
        ),
      );
    }
    return Column(
      children: [
        Row(children: [
          Expanded(child: items[0]),
          const SizedBox(width: _gap),
          Expanded(child: items[1]),
        ]),
        const SizedBox(height: _gap),
        Row(children: [
          Expanded(child: items[2]),
          const SizedBox(width: _gap),
          Expanded(child: items[3]),
        ]),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.hue,
    this.onTap,
  });
  final String label;
  final int value;
  final IconData icon;
  final Color hue;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: hue.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 15, color: hue),
              ),
              const SizedBox(width: 9),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.inkSoft),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: _CountUp(
                value: value,
                style: TextStyle(
                  fontFamily: AppTheme.fontBrand,
                  fontSize: 31,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  letterSpacing: -0.5,
                  color: AppColors.ink,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CountUp extends StatelessWidget {
  const _CountUp({required this.value, required this.style});
  final int value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: const Duration(milliseconds: 1000),
      curve: Curves.easeOutQuart,
      builder: (_, v, _) => Text('${v.round()}', style: style),
    );
  }
}
