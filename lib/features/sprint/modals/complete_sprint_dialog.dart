import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/work_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../sprint_format.dart';
import 'glass_modal.dart';

/// Liquid-Glass "Complete sprint" modal. Returns the destination for unfinished
/// work: a planned sprint id, or `backlog`. Null when dismissed.
Future<String?> showCompleteSprintDialog(
  BuildContext context, {
  required String sprintName,
  required int doneCount,
  required int donePoints,
  required int openCount,
  required int openPoints,
  required List<Sprint> plannedDestinations,
}) {
  return showGlassModal<String>(
    context,
    builder: (_) => _CompleteSprintBody(
      sprintName: sprintName,
      doneCount: doneCount,
      donePoints: donePoints,
      openCount: openCount,
      openPoints: openPoints,
      plannedDestinations: plannedDestinations,
    ),
  );
}

class _CompleteSprintBody extends StatefulWidget {
  const _CompleteSprintBody({
    required this.sprintName,
    required this.doneCount,
    required this.donePoints,
    required this.openCount,
    required this.openPoints,
    required this.plannedDestinations,
  });

  final String sprintName;
  final int doneCount;
  final int donePoints;
  final int openCount;
  final int openPoints;
  final List<Sprint> plannedDestinations;

  @override
  State<_CompleteSprintBody> createState() => _CompleteSprintBodyState();
}

class _CompleteSprintBodyState extends State<_CompleteSprintBody> {
  late String _dest = widget.plannedDestinations.isNotEmpty
      ? widget.plannedDestinations.first.id
      : 'backlog';

  @override
  Widget build(BuildContext context) {
    final total = widget.doneCount + widget.openCount;
    final pct = total == 0 ? 0 : ((widget.doneCount / total) * 100).round();
    final dests = <({String id, String label, String sub})>[
      for (final s in widget.plannedDestinations)
        (
          id: s.id,
          label: s.name,
          sub: context.t(
            'sprint.carryOver',
            variables: {
              'date': s.startDate != null ? prettyDate(s.startDate!) : '—',
            },
          ),
        ),
      (
        id: 'backlog',
        label: context.t('sprint.backlog'),
        sub: context.t('sprint.returnBacklog'),
      ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: LucideIcons.flag,
          title: context.t(
            'sprint.complete.title',
            variables: {'name': widget.sprintName},
          ),
          subtitle: context.t('sprint.complete.sub'),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 6, 22, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StatRow(
                  bubble: '${widget.doneCount}',
                  bubbleColor: SprintCompleteColors.doneBg,
                  bubbleInk: SprintCompleteColors.doneInk,
                  label: context.t('sprint.completed'),
                  sub: context.t(
                    'sprint.pointsDone',
                    variables: {'points': '${widget.donePoints}'},
                  ),
                  trailing: Text(
                    '$pct%',
                    style: const TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontWeight: FontWeight.w700,
                      color: SprintCompleteColors.doneInk,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _StatRow(
                  bubble: '${widget.openCount}',
                  bubbleColor: AppColors.canvas2,
                  bubbleInk: AppColors.inkSoft,
                  label: context.t('sprint.notCompleted'),
                  sub: context.t(
                    'sprint.pointsOpen',
                    variables: {'points': '${widget.openPoints}'},
                  ),
                ),
                if (widget.openCount > 0) ...[
                  const SizedBox(height: 16),
                  Text(
                    widget.openCount == 1
                        ? context.t(
                            'sprint.moveOpenOne',
                            variables: {'count': '1'},
                          )
                        : context.t(
                            'sprint.moveOpenMany',
                            variables: {'count': '${widget.openCount}'},
                          ),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkSoft,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final d in dests) ...[
                    _DestOption(
                      label: d.label,
                      sub: d.sub,
                      selected: _dest == d.id,
                      onTap: () => setState(() => _dest = d.id),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ],
            ),
          ),
        ),
        GlassModalFooter(
          confirmLabel: context.t('sprint.complete.cta'),
          onConfirm: () => Navigator.of(context).pop(_dest),
        ),
      ],
    );
  }
}

abstract final class SprintCompleteColors {
  static const doneBg = Color(0xFFD7F0E2);
  static const doneInk = Color(0xFF2C8862);
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.bubble,
    required this.bubbleColor,
    required this.bubbleInk,
    required this.label,
    required this.sub,
    this.trailing,
  });

  final String bubble;
  final Color bubbleColor;
  final Color bubbleInk;
  final String label;
  final String sub;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppColors.hairline.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              bubble,
              style: TextStyle(
                fontFamily: AppTheme.fontBrand,
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: bubbleInk,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  sub,
                  style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _DestOption extends StatelessWidget {
  const _DestOption({
    required this.label,
    required this.sub,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String sub;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accentSoft
              : AppColors.surface.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.hairline,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppColors.accentStrong : AppColors.inkFaint,
                  width: 1.5,
                ),
              ),
              child: selected
                  ? Container(
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.accentStrong,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
