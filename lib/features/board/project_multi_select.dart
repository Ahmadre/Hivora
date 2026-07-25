import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/models/work_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/hue_colors.dart';

/// Checkable list of projects, used wherever a board's span is chosen — when
/// creating a board and when changing which projects an existing board covers.
///
/// Each row carries the project's own accent colour, which is the same signal
/// the board cards use to tell projects apart, so the choice made here is
/// visually recognisable on the resulting board.
class ProjectMultiSelect extends StatelessWidget {
  const ProjectMultiSelect({
    super.key,
    required this.projects,
    required this.selected,
    required this.onToggle,
    this.maxHeight = 210,
  });

  final List<Project> projects;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: projects.length,
        itemBuilder: (_, index) {
          final project = projects[index];
          final isSelected = selected.contains(project.id);
          // Deselecting the last project would leave a board spanning nothing —
          // the server rejects that, so don't offer it in the first place.
          final isLast = isSelected && selected.length == 1;
          return _ProjectRow(
            project: project,
            selected: isSelected,
            enabled: !isLast,
            onTap: () => onToggle(project.id),
          );
        },
      ),
    );
  }
}

class _ProjectRow extends StatelessWidget {
  const _ProjectRow({
    required this.project,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final Project project;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = _accent(project);
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            Icon(
              selected ? LucideIcons.squareCheck : LucideIcons.square,
              size: 18,
              color: selected
                  ? AppColors.accentStrong
                  : AppColors.textSecondary.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 10),
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                project.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: enabled
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                ),
              ),
            ),
            Text(
              project.key,
              style: TextStyle(
                fontSize: 11,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A project's accent colour: the configured hex, falling back to the hue of
/// its first workflow state so every project is still distinguishable.
Color _accent(Project project) {
  final hex = project.color.replaceFirst('#', '');
  final value = int.tryParse(hex, radix: 16);
  if (value != null && hex.length == 6) return Color(0xFF000000 | value);
  final states = project.workflowStates;
  return states.isEmpty ? AppColors.accent : hueColor(states.first.hue);
}
