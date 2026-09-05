import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/core_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/hive_widgets.dart';
import '../../../core/widgets/user_pronouns.dart';
import 'settings_common.dart';

/// Leads & members card: member rows with a star→lead toggle and remove.
class MembersSection extends StatelessWidget {
  const MembersSection({
    super.key,
    required this.memberIds,
    required this.leadIds,
    required this.users,
    required this.onToggleLead,
    required this.onRemove,
    required this.onAdd,
  });

  final List<String> memberIds;
  final List<String> leadIds;
  final Map<String, DirectoryUser> users;
  final ValueChanged<String> onToggleLead;
  final ValueChanged<String> onRemove;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: context.t('projectSettings.leadsMembers'),
      actionLabel: context.t('projectSettings.addMembers'),
      onAction: onAdd,
      note: context.t('projectSettings.leadsNote'),
      child: Column(
        children: [
          for (final id in memberIds)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _MemberRow(
                user: users[id],
                fallbackId: id,
                isLead: leadIds.contains(id),
                onToggleLead: () => onToggleLead(id),
                onRemove: () => onRemove(id),
              ),
            ),
        ],
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.user,
    required this.fallbackId,
    required this.isLead,
    required this.onToggleLead,
    required this.onRemove,
  });

  final DirectoryUser? user;
  final String fallbackId;
  final bool isLead;
  final VoidCallback onToggleLead;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final name = user?.displayName ?? fallbackId;
    final title = user?.title;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          HiveAvatar(name: name, imageUrl: user?.avatarUrl, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (normalizePronouns(user?.pronouns) != null) ...[
                      const SizedBox(width: 6),
                      Flexible(child: PronounsLabel(pronouns: user?.pronouns)),
                    ],
                  ],
                ),
                if (title != null)
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _LeadStar(isLead: isLead, onTap: onToggleLead),
          IconButton(
            tooltip: context.t('projectSettings.removeMember'),
            visualDensity: VisualDensity.compact,
            onPressed: onRemove,
            icon: Icon(
              LucideIcons.userMinus,
              size: 18,
              color: AppColors.inkSoft,
            ),
          ),
        ],
      ),
    );
  }
}

class _LeadStar extends StatelessWidget {
  const _LeadStar({required this.isLead, required this.onTap});
  final bool isLead;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isLead ? AppColors.accentSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusPill),
            border: Border.all(
              color: isLead ? AppColors.accentLine : AppColors.hairline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isLead ? LucideIcons.star : LucideIcons.star,
                size: 15,
                color: isLead ? AppColors.accentStrong : AppColors.inkFaint,
              ),
              if (isLead) ...[
                const SizedBox(width: 6),
                Text(
                  context.t('projectSettings.lead'),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accentStrong,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
