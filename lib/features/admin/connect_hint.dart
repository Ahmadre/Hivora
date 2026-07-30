import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/blocs/auth_bloc.dart';
import '../../core/i18n/i18n.dart';
import '../../core/repositories/admin_repository.dart';
import '../../core/storage/app_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../sprint/modals/glass_modal.dart' show showGlassModal;

/// Shows the one-time "get a Hinata Connect licence" hint to an admin who has
/// just signed in to a self-hosted instance that isn't connected yet — so they
/// discover that a Connect account unlocks push + deep links for the published
/// app. Shown at most once per server (see [AppStorage.connectHintSeen]).
///
/// A no-op for non-admins, for instances that are already enrolled or mid-
/// handshake, or when Connect is disabled. Both call-to-actions route to
/// Adminbereich → Connect, where the automated and manual paths both live.
Future<void> maybeShowConnectHint(BuildContext context) async {
  final isAdmin = context.read<AuthBloc>().state.user?.isAdmin ?? false;
  if (!isAdmin) return;

  final storage = context.read<AppStorage>();
  if (storage.connectHintSeen) return;

  // Silent status probe — don't nag on a transient error (retry next launch).
  final Map<String, dynamic> status;
  try {
    status = await context.read<AdminRepository>().connectStatus();
  } on ApiFailure {
    return;
  }
  if (!context.mounted) return;

  // Connect disabled or already enrolled: nothing to prompt — never ask again.
  if (status['enabled'] != true || status['enrolled'] == true) {
    await storage.setConnectHintSeen();
    return;
  }
  // A handshake is already in flight: don't interrupt it, and keep the hint for
  // later in case the admin abandons the flow.
  if (status['handshakePending'] == true) return;

  await storage.setConnectHintSeen();
  if (!context.mounted) return;

  final choice = await showGlassModal<String>(
    context,
    width: 460,
    builder: (modalContext) => _ConnectHintBody(
      onConnectNow: () => Navigator.of(modalContext).pop('now'),
      onHaveToken: () => Navigator.of(modalContext).pop('token'),
      onLater: () => Navigator.of(modalContext).pop(),
    ),
  );
  if (!context.mounted) return;
  if (choice == 'now' || choice == 'token') {
    context.go('/admin?section=connect');
  }
}

class _ConnectHintBody extends StatelessWidget {
  const _ConnectHintBody({
    required this.onConnectNow,
    required this.onHaveToken,
    required this.onLater,
  });

  final VoidCallback onConnectNow;
  final VoidCallback onHaveToken;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 14, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  LucideIcons.radioTower,
                  size: 20,
                  color: AppColors.accentStrong,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    context.t('admin.connectHintTitle'),
                    style: const TextStyle(
                      fontFamily: AppTheme.fontBrand,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: context.t('common.cancel'),
                icon: Icon(LucideIcons.x, size: 20, color: AppColors.inkSoft),
                onPressed: onLater,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
          child: Text(
            context.t('admin.connectHintBody'),
            style: TextStyle(
              fontSize: 13.5,
              height: 1.45,
              color: AppColors.inkSoft,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed: onConnectNow,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(LucideIcons.zap, size: 17),
                label: Text(context.t('admin.connectHintConnectNow')),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: onHaveToken,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.ink,
                  side: BorderSide(color: AppColors.hairline),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(LucideIcons.ticket, size: 17),
                label: Text(context.t('admin.connectHintHaveToken')),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: onLater,
                child: Text(context.t('admin.connectHintLater')),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
