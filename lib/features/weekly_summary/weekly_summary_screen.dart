import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/blocs/auth_bloc.dart';
import '../../core/blocs/fetch_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/weekly_summary_models.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/weekly_summary_repository.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hex_mark.dart' show HexMark;
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_widgets.dart';
import '../../core/widgets/status_widgets.dart';
import '../issues/issue_detail_sheet.dart';
import '../shell/page_chrome.dart';

// Exact stat hues, harmonised with the dashboard "Liquid Glass" palette.
const _cCompleted = Color(0xFF2E8B62);
const _cCreated = Color(0xFF4E6FD0);
const _cFocus = Color(0xFFB9831F);
const _cOverdue = Color(0xFFC0392B);
const _heroInk = Color(0xF2FFFFFF); // ~95% white — text on navy glass

/// The Weekly Summary page: the team's work over the past week and the caller's
/// own upcoming to-dos. Reached from the Monday digest notification / e-mail CTA
/// (`/weekly-summary`) and rendered inside the app shell as a sub-page.
class WeeklySummaryScreen extends StatelessWidget {
  const WeeklySummaryScreen({super.key});

  @override
  Widget build(BuildContext context) => const _WeeklySummaryView();
}

class _WeeklySummaryView extends StatefulWidget {
  const _WeeklySummaryView();

  @override
  State<_WeeklySummaryView> createState() => _WeeklySummaryViewState();
}

class _WeeklySummaryViewState extends State<_WeeklySummaryView> {
  late final FetchCubit<WeeklySummary> _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = FetchCubit<WeeklySummary>(
      () => context.read<WeeklySummaryRepository>().summary(),
    )..load();
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageChrome(
      title: context.t('weeklySummary.title'),
      child: BlocBuilder<FetchCubit<WeeklySummary>, FetchState<WeeklySummary>>(
        bloc: _cubit,
        builder: (context, state) {
          return RefreshIndicator(
            onRefresh: _cubit.load,
            child: AsyncView(
              isLoading: state.isLoading,
              hasData: state.hasData,
              errorKey: state.errorKey,
              onRetry: _cubit.load,
              builder: (context) => _content(context, state.data!),
            ),
          );
        },
      ),
    );
  }

  Widget _content(BuildContext context, WeeklySummary data) {
    // Constrain the reading column on wide screens (golden-ratio) so the summary
    // stays a focused, centred narrative instead of stretching edge-to-edge.
    final maxWidth = context.isExpanded ? 720.0 : double.infinity;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: context.pagePadding,
      children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Hero(data: data),
                const SizedBox(height: 22),
                _SectionLabel(
                  icon: LucideIcons.history,
                  label: context.t('weeklySummary.weekBehind'),
                ),
                const SizedBox(height: 12),
                _StatRow(team: data.team),
                if (data.team.sprint != null) ...[
                  const SizedBox(height: 14),
                  _SprintCard(sprint: data.team.sprint!),
                ],
                if (data.team.contributors.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _ContributorsCard(contributors: data.team.contributors),
                ],
                if (data.team.highlights.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _HighlightsCard(issues: data.team.highlights),
                ],
                const SizedBox(height: 26),
                _SectionLabel(
                  icon: LucideIcons.listTodo,
                  label: context.t('weeklySummary.weekAhead'),
                ),
                const SizedBox(height: 12),
                _UpcomingCard(upcoming: data.upcoming),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════ Shared glass card ══════════════════════════════

/// The page's card surface — a blurred translucent panel with a soft navy drop
/// shadow, matching the dashboard's Liquid-Glass cards. Optionally tappable.
class _GlassCard extends StatelessWidget {
  const _GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.gradient,
    this.borderColor,
    this.onTap,
  });

  static const double _radius = 24;

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
    final border =
        borderColor ??
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
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_radius),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2D2B55).withValues(alpha: dark ? .48 : .22),
            blurRadius: 38,
            spreadRadius: -24,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: content,
        ),
      ),
    );
  }
}

// ══════════════════════════ Hero ═══════════════════════════════════════════

class _Hero extends StatelessWidget {
  const _Hero({required this.data});
  final WeeklySummary data;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthBloc>().state.user;
    final first = (user?.displayName ?? '').trim().split(' ').first;
    final completed = data.team.completed;
    final range = _rangeLabel(context, data.weekStart, data.weekEnd);

    return _GlassCard(
      padding: EdgeInsets.all(context.isCompact ? 22 : 28),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xE01E1C3A), Color(0xD12D2B55)],
      ),
      borderColor: Colors.white.withValues(alpha: .14),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned(
            right: -210,
            bottom: -230,
            child: IgnorePointer(
              child: Opacity(
                opacity: .07,
                child: HexMark(size: 440, color: AppColors.accent),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.calendarRange,
                        size: 12, color: Color(0xFFEBCF8F)),
                    const SizedBox(width: 7),
                    Text(
                      range,
                      style: const TextStyle(
                        fontFamily: AppTheme.fontMono,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                        color: Color(0xFFEBCF8F),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                first.isEmpty
                    ? context.t('weeklySummary.title')
                    : context.t('weeklySummary.heroGreeting',
                        variables: {'name': first}),
                style: const TextStyle(
                  fontFamily: AppTheme.fontBrand,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _heroInk,
                ),
              ),
              const SizedBox(height: 6),
              // Big headline: what the team accomplished this week.
              RichText(
                text: TextSpan(
                  style: const TextStyle(
                    fontFamily: AppTheme.fontBrand,
                    height: 1.1,
                    letterSpacing: -0.6,
                    color: _heroInk,
                  ),
                  children: [
                    TextSpan(
                      text: '$completed',
                      style: TextStyle(
                        fontSize: context.isCompact ? 40 : 48,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFFF0C464),
                      ),
                    ),
                    TextSpan(
                      text:
                          '  ${context.t('weeklySummary.heroCompleted', variables: {'count': '$completed'})}',
                      style: TextStyle(
                        fontSize: context.isCompact ? 19 : 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _heroChip(LucideIcons.circleCheck,
                      context.t('weeklySummary.youClosed',
                          variables: {'count': '${data.team.myCompleted}'})),
                  _heroChip(LucideIcons.timer,
                      context.t('weeklySummary.youFocused',
                          variables: {'time': focusLabel(data.team.focusMinutes)})),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroChip(IconData icon, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: Colors.white.withValues(alpha: .12)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: Colors.white.withValues(alpha: .72)),
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

// ══════════════════════════ Section label ══════════════════════════════════

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.accentStrong),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontFamily: AppTheme.fontBrand,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            color: AppColors.ink,
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════ Stat row ═══════════════════════════════════════

class _StatRow extends StatelessWidget {
  const _StatRow({required this.team});
  final WeeklyTeam team;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _StatCard(
        label: context.t('weeklySummary.statCompleted'),
        value: '${team.completed}',
        icon: LucideIcons.circleCheckBig,
        hue: _cCompleted,
        onTap: () => context.go('/issues?view=done'),
      ),
      _StatCard(
        label: context.t('weeklySummary.statCreated'),
        value: '${team.created}',
        icon: LucideIcons.plus,
        hue: _cCreated,
        onTap: () => context.go('/issues'),
      ),
      _StatCard(
        label: context.t('weeklySummary.statFocus'),
        value: focusLabel(team.focusMinutes),
        icon: LucideIcons.timer,
        hue: _cFocus,
        onTap: () => context.go('/timesheet'),
      ),
    ];
    return Row(
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: cards[i]),
        ],
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.hue,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color hue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: hue.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(9),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 16, color: hue),
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontFamily: AppTheme.fontBrand,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                height: 1,
                letterSpacing: -0.5,
                color: AppColors.ink,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: AppColors.inkSoft,
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════ Sprint card ════════════════════════════════════

class _SprintCard extends StatelessWidget {
  const _SprintCard({required this.sprint});
  final WeeklySprint sprint;

  @override
  Widget build(BuildContext context) {
    final pct = sprint.progressPercent;
    return _GlassCard(
      onTap: () => context.go(
        sprint.boardId.isNotEmpty ? '/boards/${sprint.boardId}' : '/board',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: const Icon(LucideIcons.goal,
                    size: 18, color: AppColors.accentStrong),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t('weeklySummary.activeSprint').toUpperCase(),
                      style: const TextStyle(
                        fontFamily: AppTheme.fontMono,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: AppColors.accentStrong,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sprint.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTheme.fontBrand,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
              if (sprint.days > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.accentSoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    context.t('weeklySummary.sprintDay', variables: {
                      'day': '${sprint.day}',
                      'days': '${sprint.days}',
                    }),
                    style: const TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accentStrong,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: HiveProgress(value: pct, color: AppColors.accent)),
              const SizedBox(width: 12),
              Text(
                '${(pct * 100).round()}%',
                style: TextStyle(
                  fontFamily: AppTheme.fontBrand,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            context.t('weeklySummary.sprintProgress', variables: {
              'done': '${sprint.issuesDone}',
              'total': '${sprint.issuesTotal}',
            }),
            style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════ Contributors ═══════════════════════════════════

class _ContributorsCard extends StatelessWidget {
  const _ContributorsCard({required this.contributors});
  final List<WeeklyContributor> contributors;

  @override
  Widget build(BuildContext context) {
    final max = contributors.first.completed.clamp(1, 1 << 30);
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(
            icon: LucideIcons.trophy,
            label: context.t('weeklySummary.topContributors'),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < contributors.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _ContributorRow(
              rank: i + 1,
              contributor: contributors[i],
              fraction: contributors[i].completed / max,
            ),
          ],
        ],
      ),
    );
  }
}

class _ContributorRow extends StatelessWidget {
  const _ContributorRow({
    required this.rank,
    required this.contributor,
    required this.fraction,
  });

  final int rank;
  final WeeklyContributor contributor;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 18,
          child: Text(
            '$rank',
            style: TextStyle(
              fontFamily: AppTheme.fontMono,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: rank <= 3 ? AppColors.accentStrong : AppColors.inkFaint,
            ),
          ),
        ),
        HiveAvatar(
          name: contributor.displayName,
          imageUrl: contributor.avatarUrl,
          size: 30,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                contributor.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: fraction.clamp(0.05, 1.0),
                  minHeight: 5,
                  backgroundColor: AppColors.hairline2,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          context.t('weeklySummary.doneCount',
              variables: {'count': '${contributor.completed}'}),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.inkSoft,
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════ Highlights ═════════════════════════════════════

class _HighlightsCard extends StatelessWidget {
  const _HighlightsCard({required this.issues});
  final List<Issue> issues;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _CardTitle(
              icon: LucideIcons.sparkles,
              label: context.t('weeklySummary.completedHighlights'),
            ),
          ),
          const SizedBox(height: 6),
          for (final issue in issues)
            _IssueRow(issue: issue, showDue: false),
        ],
      ),
    );
  }
}

// ══════════════════════════ Upcoming ═══════════════════════════════════════

class _UpcomingCard extends StatelessWidget {
  const _UpcomingCard({required this.upcoming});
  final WeeklyUpcoming upcoming;

  @override
  Widget build(BuildContext context) {
    if (upcoming.total == 0) {
      return _GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: HiveEmptyState(
          card: false,
          title: context.t('weeklySummary.allCaughtUpTitle'),
          message: context.t('weeklySummary.allCaughtUpMessage'),
        ),
      );
    }
    final remaining = upcoming.total - upcoming.items.length;
    return _GlassCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.t('weeklySummary.upcomingCount',
                        variables: {'count': '${upcoming.total}'}),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ),
                if (upcoming.overdue > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _cOverdue.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      context.t('weeklySummary.overdueCount',
                          variables: {'count': '${upcoming.overdue}'}),
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: _cOverdue,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (final issue in upcoming.items)
            _IssueRow(issue: issue, showDue: true),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(right: 8, top: 2),
            child: Row(
              children: [
                if (remaining > 0)
                  Text(
                    context.t('weeklySummary.moreCount',
                        variables: {'count': '$remaining'}),
                    style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
                  ),
                const Spacer(),
                GhostButton(
                  label: context.t('weeklySummary.viewAll'),
                  icon: LucideIcons.arrowRight,
                  onPressed: () => context.go('/issues?view=today'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════ Issue row ══════════════════════════════════════

class _IssueRow extends StatelessWidget {
  const _IssueRow({required this.issue, required this.showDue});
  final Issue issue;
  final bool showDue;

  @override
  Widget build(BuildContext context) {
    final due = issue.dueDate;
    final overdue = due != null &&
        due.isBefore(DateTime(
            DateTime.now().year, DateTime.now().month, DateTime.now().day));
    return Material(
      color: Colors.transparent,
      child: InkWell(
        // The modal sheet, not `context.go('/issues/…')`: `go` replaces this
        // location instead of stacking on it, so the issue page would have
        // nothing to pop back to and its close button falls through to the
        // `/dashboard` fallback. The sheet leaves the summary mounted underneath.
        onTap: () => showIssueDetailSheet(context, issueId: issue.id),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              TypeGlyph(type: issue.type, size: 26),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      issue.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        IdMono(issue.readableId),
                        if (showDue && due != null) ...[
                          const SizedBox(width: 8),
                          Icon(
                            LucideIcons.calendar,
                            size: 11,
                            color: overdue ? _cOverdue : AppColors.inkFaint,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            DateFormat.MMMd(
                              Localizations.localeOf(context).languageCode,
                            ).format(due.toLocal()),
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight:
                                  overdue ? FontWeight.w700 : FontWeight.w500,
                              color: overdue ? _cOverdue : AppColors.inkSoft,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              PriorityFlag(priority: issue.priority),
              const SizedBox(width: 6),
              Icon(LucideIcons.chevronRight,
                  size: 15, color: AppColors.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════ Bits ═══════════════════════════════════════════

class _CardTitle extends StatelessWidget {
  const _CardTitle({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: AppColors.accentStrong),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
      ],
    );
  }
}

/// "3h 20m" / "45m" / "0m" from a minute count.
String focusLabel(int minutes) {
  if (minutes <= 0) return '0m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

String _rangeLabel(BuildContext context, DateTime? start, DateTime? end) {
  if (start == null || end == null) return '';
  final code = Localizations.localeOf(context).languageCode;
  final fmt = DateFormat.MMMd(code);
  return '${fmt.format(start)} – ${fmt.format(end)}';
}
