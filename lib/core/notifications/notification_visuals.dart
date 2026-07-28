import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_colors.dart';

/// Leading icon + tint for a notification type. Cases match the server's
/// `Notification.Type` enum; the loose legacy tokens are kept as fallbacks.
(IconData, Color) notificationVisual(String type) =>
    switch (type.toUpperCase()) {
      'MENTION' => (LucideIcons.atSign, AppColors.stReview),
      'ISSUE_ASSIGNED' ||
      'ASSIGN' ||
      'ASSIGNED' ||
      'ASSIGNMENT' => (LucideIcons.userCheck, AppColors.stTodo),
      'ISSUE_COMMENTED' ||
      'COMMENT' => (LucideIcons.messageSquare, AppColors.stProgress),
      'COMMENT_REPLY' || 'REPLY' => (LucideIcons.reply, AppColors.stReview),
      'ISSUE_UPDATED' => (LucideIcons.refreshCw, AppColors.accentBlue),
      'ISSUE_INGESTED' => (LucideIcons.inbox, AppColors.accentTeal),
      'SPRINT_STARTED' ||
      'SPRINT_COMPLETED' => (LucideIcons.goal, AppColors.accentPurple),
      'ISSUE_DUE_SOON' ||
      'DUE' ||
      'DEADLINE' => (LucideIcons.calendarDays, AppColors.priHigh),
      'DIGEST' => (LucideIcons.newspaper, AppColors.accentBlue),
      'SECURITY_ALERT' => (LucideIcons.shieldAlert, AppColors.priHigh),
      'TEAM_ADDED' ||
      'TEAM_ROLE_CHANGED' ||
      'TEAM_REMOVED' => (LucideIcons.usersRound, AppColors.accentBlue),
      'PROJECT_ADDED' => (LucideIcons.folderPlus, AppColors.accentPurple),
      'ACCOUNT_ACTIVATED' ||
      'ACCOUNT_DEACTIVATED' ||
      'ACCOUNT_ROLE_CHANGED' ||
      'ACCOUNT_DELETED' => (LucideIcons.shieldCheck, AppColors.inkSoft),
      'REVIEW' ||
      'REVIEW_REQUEST' => (LucideIcons.messageSquareText, AppColors.stReview),
      _ => (LucideIcons.bell, AppColors.inkSoft),
    };

/// Compact relative time ("now", "8m", "2h", "3d", "5w").
String? notificationTimeAgo(DateTime? time) {
  if (time == null) return null;
  final diff = DateTime.now().difference(time);
  if (diff.isNegative || diff.inSeconds < 60) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return '${(diff.inDays / 7).floor()}w';
}
