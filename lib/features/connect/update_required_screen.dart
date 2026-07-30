import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/i18n/i18n.dart';
import '../../core/models/core_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/soft_card.dart';

/// Resolves the configured app-store listing for the current platform, so the
/// update gate can send the user straight to the correct store. Returns null
/// on the web or when no URL is configured for the running platform.
String? storeUrlForPlatform(ServerMeta? meta) {
  if (meta == null || kIsWeb) return null;
  final url = Platform.isIOS
      ? meta.iosStoreUrl
      : Platform.isAndroid
      ? meta.androidStoreUrl
      : Platform.isMacOS
      ? meta.macosStoreUrl
      : '';
  return url.trim().isEmpty ? null : url.trim();
}

/// Hard version gate: shown when the server requires a newer app version.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({
    super.key,
    required this.appVersion,
    required this.minVersion,
    this.storeUrl,
  });

  final String appVersion;
  final String minVersion;

  /// Platform-specific app-store link to update the app, when configured.
  final String? storeUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SoftCard(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      LucideIcons.cloudDownload,
                      size: 56,
                      color: AppColors.navy,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      context.t('update.title'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      context.t(
                        'update.body',
                        variables: {
                          'current': appVersion,
                          'required': minVersion,
                        },
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                    if (storeUrl != null) ...[
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => launchUrl(
                            Uri.parse(storeUrl!),
                            mode: LaunchMode.externalApplication,
                          ),
                          icon: const Icon(LucideIcons.externalLink, size: 18),
                          label: Text(context.t('update.openStore')),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
