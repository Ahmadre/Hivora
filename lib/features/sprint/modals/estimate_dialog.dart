import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/work_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/responsive/responsive.dart';
import '../../../core/widgets/hive_widgets.dart';
import '../sprint_tokens.dart';
import 'glass_modal.dart';

/// Liquid-glass planning-poker picker. Returns the chosen story points on save
/// (null = cleared); a plain dismissal returns null. Reused for the sprint
/// planning rows and the issue detail / create form.
Future<({int? points})?> showStoryPointsDialog(
  BuildContext context, {
  required int? current,
  required String subtitle,
}) {
  return showGlassModal<({int? points})>(
    context,
    width: 460,
    builder: (_) => _EstimateBody(current: current, subtitle: subtitle),
  );
}

/// Convenience wrapper for an [Issue] (sprint planning poker).
Future<({int? points})?> showEstimateDialog(
  BuildContext context, {
  required Issue issue,
}) => showStoryPointsDialog(
  context,
  current: issue.storyPoints,
  subtitle: '${issue.readableId} · ${issue.title}',
);

class _EstimateBody extends StatefulWidget {
  const _EstimateBody({required this.current, required this.subtitle});

  final int? current;
  final String subtitle;

  @override
  State<_EstimateBody> createState() => _EstimateBodyState();
}

class _EstimateBodyState extends State<_EstimateBody> {
  late int? _value = widget.current;

  @override
  Widget build(BuildContext context) {
    // 3 columns on phones (sprint.css §responsive), 4 otherwise.
    final cols = context.isCompact ? 3 : 4;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: LucideIcons.swatchBook,
          title: context.t('sprint.estimate.title'),
          subtitle: widget.subtitle,
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 18),
            child: GridView.count(
              crossAxisCount: cols,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.74,
              children: [
                for (final p in SprintTokens.fib)
                  _PokerCard(
                    label: '$p',
                    selected: _value == p,
                    onTap: () => setState(() => _value = p),
                  ),
                _PokerCard(
                  label: '—',
                  muted: true,
                  selected: _value == null,
                  onTap: () => setState(() => _value = null),
                ),
              ],
            ),
          ),
        ),
        GlassModalFooter(
          confirmLabel: context.t('common.save'),
          hint: Text(
            context.t('sprint.fibScale'),
            style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
          ),
          onConfirm: () => Navigator.of(context).pop((points: _value)),
        ),
      ],
    );
  }
}

class _PokerCard extends StatelessWidget {
  const _PokerCard({
    required this.label,
    required this.selected,
    required this.onTap,
    this.muted = false,
  });

  final String label;
  final bool selected;
  final bool muted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        curve: hiveEase,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent
              : AppColors.surface.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.accentStrong : AppColors.hairline,
            width: 1.5,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontFamily: muted ? AppTheme.fontUi : AppTheme.fontBrand,
            fontSize: muted ? 14 : 24,
            fontWeight: FontWeight.w700,
            color: selected
                ? const Color(0xFF2A2410)
                : (muted ? AppColors.inkFaint : AppColors.ink),
          ),
        ),
      ),
    );
  }
}
