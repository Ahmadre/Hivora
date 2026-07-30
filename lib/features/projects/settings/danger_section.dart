import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import 'settings_common.dart';

/// Danger zone: permanently delete the project. The actual cascade (boards,
/// issues, etc.) runs in the streamed [showDeleteProjectFlow] modal; this card
/// is just the entry point.
class DangerSection extends StatelessWidget {
  const DangerSection({super.key, required this.onDelete});

  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: context.t('projectSettings.dangerZone'),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.t('projectSettings.deleteTitle'),
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  context.t('projectSettings.deleteNote'),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: AppColors.inkSoft,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          FilledButton.icon(
            onPressed: onDelete,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              ),
            ),
            icon: const Icon(LucideIcons.trash2, size: 16),
            label: Text(context.t('projectSettings.deleteCta')),
          ),
        ],
      ),
    );
  }
}
