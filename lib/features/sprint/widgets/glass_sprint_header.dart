import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/work_models.dart';
import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/hive_widgets.dart';
import '../sprint_format.dart';

/// The active-sprint header — the design's discreet single component: a small
/// white identity card (Active badge + sprint name + goal) with a thin
/// day-progress track and "Day X/Y" sitting on the canvas to its right.
/// Full-width (stacked) on phones, content-hugging on wider screens.
class GlassSprintHeader extends StatelessWidget {
  const GlassSprintHeader({super.key, required this.sprint});

  final Sprint sprint;

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    final day = sprintDay(sprint.startDate, sprint.endDate);
    final dayIndex = day?.day ?? 0;
    final dayTotal = day?.total ?? 0;
    final ringP = dayTotal == 0 ? 0.0 : dayIndex / dayTotal;

    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.zap, size: 13, color: Color(0xFF2A2410)),
          const SizedBox(width: 4),
          Text(
            context.t('board.active'),
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2A2410),
            ),
          ),
        ],
      ),
    );

    final id = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          sprint.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: AppTheme.fontBrand,
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
            height: 1.15,
          ),
        ),
        if ((sprint.goal ?? '').isNotEmpty)
          Text(
            sprint.goal!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
          ),
      ],
    );

    Widget card({required Widget child}) => Container(
      padding: const EdgeInsets.fromLTRB(14, 11, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hairline),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14191637),
            blurRadius: 16,
            offset: Offset(0, 6),
            spreadRadius: -8,
          ),
        ],
      ),
      child: child,
    );

    final dayLabel = Text(
      context.t(
        'board.sprintDay',
        variables: {'day': '$dayIndex', 'total': '$dayTotal'},
      ),
      style: TextStyle(
        fontFamily: AppTheme.fontMono,
        fontSize: 13,
        color: AppColors.inkSoft,
      ),
    );

    // The app's standard progress bar (a LinearProgressIndicator with a visible
    // canvas-2 track). Needs a bounded width, so it's always given one.
    Widget track({double? width}) => SizedBox(
      width: width,
      child: HiveProgress(value: ringP, height: 6),
    );

    if (compact) {
      // Phone: a full-width card — badge + name on top, progress spanning the
      // full width below.
      return card(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(padding: const EdgeInsets.only(top: 1), child: badge),
                const SizedBox(width: 12),
                Expanded(child: id),
              ],
            ),
            if (dayTotal > 0) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: track()),
                  const SizedBox(width: 10),
                  dayLabel,
                ],
              ),
            ],
          ],
        ),
      );
    }

    // Desktop / tablet: card hugs its content; progress floats on the canvas.
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: card(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  badge,
                  const SizedBox(width: 12),
                  Flexible(child: id),
                ],
              ),
            ),
          ),
          const SizedBox(width: 22),
          if (dayTotal > 0) ...[
            track(width: 200),
            const SizedBox(width: 12),
            dayLabel,
          ],
        ],
      ),
    );
  }
}
