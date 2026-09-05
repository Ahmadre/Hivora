import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/models/work_models.dart';
import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/hive_widgets.dart';
import '../../../core/widgets/subtask_widgets.dart';
import '../../../core/widgets/user_pronouns.dart';

/// One draggable issue row in the planning surface: select checkbox · type
/// glyph · id · title · first tag · priority · points badge (tap → poker) ·
/// assignee. Drops the tag chip on phones to avoid overflow.
class PlanRow extends StatelessWidget {
  const PlanRow({
    super.key,
    required this.issue,
    required this.selected,
    required this.onToggleSelect,
    required this.onOpen,
    required this.onEstimate,
    this.assigneeName,
    this.assigneeAvatar,
    this.assigneePronouns,
  });

  final Issue issue;

  /// The assignee's display name and avatar, resolved by the surface from the
  /// board's user directory. The issue itself only carries the assignee *id*,
  /// and an id has no initials worth drawing.
  final String? assigneeName;
  final String? assigneeAvatar;
  final String? assigneePronouns;
  final bool selected;
  final VoidCallback onToggleSelect;
  final VoidCallback onOpen;
  final VoidCallback onEstimate;

  @override
  Widget build(BuildContext context) {
    final tag = issue.tags.isNotEmpty ? issue.tags.first : null;
    return Material(
      color: selected ? AppColors.accentSoft : AppColors.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.hairline,
            ),
          ),
          child: Row(
            children: [
              _Checkbox(selected: selected, onTap: onToggleSelect),
              const SizedBox(width: 10),
              TypeGlyph(type: issue.type, size: 18),
              const SizedBox(width: 8),
              IdMono(issue.readableId),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  issue.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (tag != null && !context.isCompact) ...[
                const SizedBox(width: 8),
                LabelTag(tag),
              ],
              if (issue.hasSubtasks) ...[
                const SizedBox(width: 8),
                SubtaskBadge(issue: issue),
              ],
              const SizedBox(width: 10),
              PriorityFlag(priority: issue.priority),
              const SizedBox(width: 10),
              _PointsBadge(points: issue.storyPoints, onTap: onEstimate),
              const SizedBox(width: 10),
              if (issue.assigneeId != null)
                Tooltip(
                  // The row owns this tooltip already, so the pronouns join it
                  // rather than nesting a second one inside the avatar.
                  message:
                      personTooltip(
                        name: assigneeName ?? issue.assigneeId!,
                        pronouns: assigneePronouns,
                      ) ??
                      issue.assigneeId!,
                  child: HiveAvatar(
                    name: assigneeName ?? issue.assigneeId!,
                    imageUrl: assigneeAvatar,
                    size: 24,
                  ),
                )
              else
                const SizedBox(width: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _Checkbox extends StatelessWidget {
  const _Checkbox({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.hairline,
            width: 1.5,
          ),
        ),
        child: selected
            ? const Icon(LucideIcons.check, size: 13, color: Color(0xFF2A2410))
            : null,
      ),
    );
  }
}

class _PointsBadge extends StatelessWidget {
  const _PointsBadge({required this.points, required this.onTap});

  final int? points;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final empty = points == null;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        constraints: const BoxConstraints(minWidth: 24),
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: empty ? Colors.transparent : AppColors.canvas2,
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          border: Border.all(
            color: empty ? AppColors.hairline : AppColors.hairline,
          ),
        ),
        child: Text(
          empty ? '—' : '$points',
          style: TextStyle(
            fontFamily: AppTheme.fontMono,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: empty ? AppColors.inkFaint : AppColors.ink,
          ),
        ),
      ),
    );
  }
}
