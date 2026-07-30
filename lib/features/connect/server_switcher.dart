import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/blocs/app_config_bloc.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/server_profile.dart';
import '../../core/storage/app_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import 'server_manager.dart';

/// Switches the app to an already-saved [url]: points the storage at it and asks
/// AppConfig to re-verify the new backend. Auth is re-checked centrally once the
/// switch settles (see `HinataApp._onAppConfig`), so the user either lands back
/// in the app (the server has a stored token) or on its sign-in screen.
Future<void> switchToServer(BuildContext context, String url) async {
  final storage = context.read<AppStorage>();
  if (storage.serverUrl == url) return;
  final appConfig = context.read<AppConfigBloc>();
  await storage.setCurrentServer(url);
  appConfig.add(const AppConfigStarted());
}

/// Resolves the currently-selected server's profile from storage.
ServerProfile _currentProfile(AppStorage storage) {
  final current = storage.serverUrl;
  return storage.servers.firstWhere(
    (s) => s.url == current,
    orElse: () => ServerProfile(url: current ?? ''),
  );
}

/// A full-width "current server" selector for the login screen: an amber-tinted
/// button showing the active server's status, name and host, opening the
/// [showServerManager] sheet to switch or add a backend.
class ServerSelectorButton extends StatelessWidget {
  const ServerSelectorButton({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = _currentProfile(context.read<AppStorage>());
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => showServerManager(context),
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.accentSoft,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.accentLine),
          ),
          child: Row(
            children: [
              const Icon(
                LucideIcons.server,
                size: 20,
                color: AppColors.accentStrong,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const _Dot(),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            profile.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      profile.host,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTheme.fontMono,
                        fontSize: 11.5,
                        color: AppColors.inkFaint,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                LucideIcons.chevronDown,
                size: 19,
                color: AppColors.accentStrong,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The "active server" card for the account → appearance section: shows the
/// connected server with a "Manage servers" action that opens the manager sheet.
class ServerCard extends StatelessWidget {
  const ServerCard({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = _currentProfile(context.read<AppStorage>());
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.t('server.activeConnected').toUpperCase(),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: AppColors.inkFaint,
            ),
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.32),
                  ),
                ),
                child: const Icon(
                  LucideIcons.server,
                  size: 22,
                  color: AppColors.accentStrong,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const _Dot(),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            profile.host,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: AppTheme.fontMono,
                              fontSize: 12,
                              color: AppColors.inkFaint,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Builder so the desktop popover anchors beneath this button, not the
          // whole card.
          Builder(
            builder: (btnContext) => OutlinedButton.icon(
              onPressed: () => showServerManager(btnContext),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                foregroundColor: AppColors.accentStrong,
                side: BorderSide(
                  color: AppColors.accent.withValues(alpha: 0.4),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              icon: const Icon(LucideIcons.settings2, size: 17),
              label: Text(context.t('server.manageAction')),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small success-tinted status dot for the "connected" selectors.
class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: AppColors.success,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.success.withValues(alpha: 0.5),
            blurRadius: 7,
          ),
        ],
      ),
    );
  }
}
