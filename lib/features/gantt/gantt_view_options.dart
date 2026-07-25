import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/gantt_links.dart';
import '../../core/widgets/hive_widgets.dart';
import '../sprint/modals/glass_modal.dart'
    show
        kGlassPopoverBreakpoint,
        showGlassAnchoredPopover,
        showGlassBottomSheet;

/// Opens the timeline's view options — which connectors to draw and whether to
/// emphasise the critical path — as a glass popover beside [anchorKey] on wide
/// screens and as a bottom sheet on phones.
///
/// Every toggle applies live through [onChanged]; there is nothing to confirm,
/// so the panel has no footer. [summary] tells the user what the graph actually
/// holds (how many dependencies, how many of them conflict), which is the
/// context needed to decide what to switch on.
Future<void> showGanttViewOptions(
  BuildContext context, {
  required GlobalKey anchorKey,
  required GanttLinkOptions options,
  required GanttLinkSummary summary,
  required ValueChanged<GanttLinkOptions> onChanged,
}) {
  final box = anchorKey.currentContext?.findRenderObject() as RenderBox?;
  final anchorRect = (box != null && box.hasSize)
      ? (box.localToGlobal(Offset.zero) & box.size)
      : Rect.zero;

  Widget panel(BuildContext _) => _GanttOptionsPanel(
    initial: options,
    summary: summary,
    onChanged: onChanged,
  );

  if (MediaQuery.sizeOf(context).width >= kGlassPopoverBreakpoint) {
    return showGlassAnchoredPopover<void>(
      context,
      anchorRect: anchorRect,
      width: 330,
      minHeight: 200,
      maxHeight: 420,
      builder: panel,
    );
  }
  return showGlassBottomSheet<void>(context, builder: panel);
}

/// What the chart's link graph contains — drives the counts in the panel.
class GanttLinkSummary {
  const GanttLinkSummary({
    this.dependencies = 0,
    this.related = 0,
    this.conflicts = 0,
  });

  final int dependencies;
  final int related;
  final int conflicts;
}

class _GanttOptionsPanel extends StatefulWidget {
  const _GanttOptionsPanel({
    required this.initial,
    required this.summary,
    required this.onChanged,
  });

  final GanttLinkOptions initial;
  final GanttLinkSummary summary;
  final ValueChanged<GanttLinkOptions> onChanged;

  @override
  State<_GanttOptionsPanel> createState() => _GanttOptionsPanelState();
}

class _GanttOptionsPanelState extends State<_GanttOptionsPanel> {
  late GanttLinkOptions _options = widget.initial;

  void _apply(GanttLinkOptions next) {
    setState(() => _options = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      shrinkWrap: true,
      children: [
        Text(
          context.t('gantt.options.title'),
          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        _OptionRow(
          icon: LucideIcons.arrowRightLeft,
          label: context.t('gantt.options.dependencies'),
          hint: context.t(
            'gantt.options.dependenciesHint',
            count: summary.dependencies,
          ),
          value: _options.showDependencies,
          onChanged: (v) => _apply(_options.copyWith(showDependencies: v)),
        ),
        _OptionRow(
          icon: LucideIcons.link,
          label: context.t('gantt.options.related'),
          hint: context.t('gantt.options.relatedHint', count: summary.related),
          value: _options.showRelated,
          onChanged: (v) => _apply(_options.copyWith(showRelated: v)),
        ),
        _OptionRow(
          icon: LucideIcons.zap,
          label: context.t('gantt.options.criticalPath'),
          hint: context.t('gantt.options.criticalPathHint'),
          value: _options.showCriticalPath,
          onChanged: (v) => _apply(_options.copyWith(showCriticalPath: v)),
        ),
        if (summary.conflicts > 0) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(
                  LucideIcons.triangleAlert,
                  size: 15,
                  color: AppColors.danger,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.t('gantt.conflicts', count: summary.conflicts),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.danger,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        Text(
          context.t('gantt.legend.title').toUpperCase(),
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: AppColors.inkFaint,
          ),
        ),
        const SizedBox(height: 8),
        GanttLinkLegend(options: _options),
        const SizedBox(height: 12),
        Text(
          context.t('gantt.focusHint'),
          style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
        ),
      ],
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.icon,
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 17, color: AppColors.inkSoft),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hint,
                    style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            HiveSwitch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}
