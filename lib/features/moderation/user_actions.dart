import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/moderation_models.dart';
import '../../core/repositories/moderation_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hive_widgets.dart' show HiveAvatar;
import '../sprint/modals/glass_modal.dart';
import 'report_modal.dart';

/// What the person popover offers.
enum _UserAction { report, block }

/// Opens the actions popover for another member — report them, or block them.
///
/// Both actions live on the person rather than only on their content because
/// that is what the store policies require and what reviewers look for: Apple
/// Guideline 1.2 asks for blocking abusive *users*, and Google's UGC policy asks
/// for in-app reporting of content **and users** — an app that can only report a
/// message has been rejected for exactly that gap.
///
/// Responsive like every other picker in the app: an anchored popover beside the
/// avatar from [kGlassPopoverBreakpoint] up, a bottom sheet below it. Pass
/// [anchorRect] (the avatar's global rect, captured before the tap's async gap)
/// to place the popover; without one it always falls back to the sheet.
///
/// [isSelf] hides both actions and shows a note instead. Reporting yourself is
/// noise in the queue, and blocking yourself would hide your own comments.
Future<void> showUserActions(
  BuildContext context, {
  required String userId,
  required String displayName,
  String? avatarUrl,
  String? subtitle,
  Rect? anchorRect,
  bool isSelf = false,
}) async {
  // Read across the root-navigator boundary before opening: the popover route
  // sits above the app's providers and cannot look either of these up itself.
  final repository = context.read<ModerationRepository>();
  final panel = _UserActionsPanel(
    displayName: displayName,
    avatarUrl: avatarUrl,
    subtitle: subtitle,
    isSelf: isSelf,
  );
  final wide = MediaQuery.sizeOf(context).width >= kGlassPopoverBreakpoint;
  final action = (wide && anchorRect != null)
      ? await showGlassAnchoredPopover<_UserAction>(
          context,
          anchorRect: anchorRect,
          width: 300,
          minHeight: 160,
          maxHeight: 320,
          builder: (_) => panel,
        )
      : await showGlassBottomSheet<_UserAction>(
          context,
          builder: (_) => panel,
        );
  if (action == null || !context.mounted) return;
  switch (action) {
    case _UserAction.report:
      await showReportModal(
        context,
        ReportTarget(
          type: ReportTargetType.user,
          id: userId,
          label: displayName,
        ),
      );
    case _UserAction.block:
      await confirmBlockUser(
        context,
        repository: repository,
        userId: userId,
        displayName: displayName,
      );
  }
}

/// Confirms and performs a block, then reports the outcome.
///
/// Confirmed rather than immediate because a block is invisible once it takes
/// effect: the blocked person's comments simply stop appearing, so someone who
/// tapped by accident would experience it as a bug in the feed rather than as
/// something they did. The confirmation spells out what changes *and* what does
/// not — this is a personal mute, not a ban, and a colleague who expects it to
/// remove someone from the project would otherwise be badly surprised.
Future<void> confirmBlockUser(
  BuildContext context, {
  required ModerationRepository repository,
  required String userId,
  required String displayName,
}) async {
  final confirmed = await showGlassConfirm(
    context,
    icon: LucideIcons.userX,
    title: context.t('moderation.block.title', variables: {'name': displayName}),
    message: context.t('moderation.block.message'),
    confirmLabel: context.t('moderation.block.confirm'),
    confirmIcon: LucideIcons.userX,
    destructive: true,
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await repository.blockUser(userId);
    if (context.mounted) {
      showGlassToast(
        context,
        context.t('moderation.block.done', variables: {'name': displayName}),
        kind: GlassToastKind.success,
      );
    }
  } on ApiFailure catch (failure) {
    if (context.mounted) {
      showGlassErrorToast(context, context.t(failure.message));
    }
  } catch (_) {
    if (context.mounted) {
      showGlassErrorToast(context, context.t('errors.unexpected'));
    }
  }
}

/// The popover/sheet body: who this is, then the two actions.
class _UserActionsPanel extends StatelessWidget {
  const _UserActionsPanel({
    required this.displayName,
    required this.avatarUrl,
    required this.subtitle,
    required this.isSelf,
  });

  final String displayName;
  final String? avatarUrl;
  final String? subtitle;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
          child: Row(
            children: [
              HiveAvatar(name: displayName, imageUrl: avatarUrl, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTheme.fontBrand,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.inkFaint,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: AppColors.hairline2),
        if (isSelf)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            child: Text(
              context.t('moderation.user.self'),
              style: TextStyle(fontSize: 12.5, color: AppColors.inkFaint),
            ),
          )
        else ...[
          _ActionRow(
            icon: LucideIcons.flag,
            label: context.t('moderation.user.report'),
            onTap: () => Navigator.of(context).pop(_UserAction.report),
          ),
          _ActionRow(
            icon: LucideIcons.userX,
            label: context.t('moderation.user.block'),
            danger: true,
            onTap: () => Navigator.of(context).pop(_UserAction.block),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.ink;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          child: Row(
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
