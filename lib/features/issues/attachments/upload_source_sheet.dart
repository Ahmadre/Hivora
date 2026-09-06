import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassContainer, GlassQuality, LiquidRoundedSuperellipse;

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../search/search_tokens.dart';
import '../../../core/widgets/hive_widgets.dart' show forwardChevron;

/// Where an attachment is being sourced from. Picked in [showUploadSourceSheet]
/// on touch platforms, where the OS offers distinct gallery / camera / document
/// flows (mirroring the native iOS "attach" action sheet).
enum UploadSource { gallery, photo, video, files }

/// A Liquid-Glass bottom action sheet letting the user choose how to attach a
/// file on mobile: from the photo library (images & videos), by capturing a new
/// photo or video, or from the system document browser.
///
/// Returns the chosen [UploadSource], or `null` if dismissed. Only meaningful on
/// touch platforms — desktop/web go straight to the file picker.
Future<UploadSource?> showUploadSourceSheet(BuildContext context) {
  return showModalBottomSheet<UploadSource>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.32),
    builder: (sheetContext) => const _UploadSourceSheet(),
  );
}

class _UploadSourceSheet extends StatelessWidget {
  const _UploadSourceSheet();

  static const double _radius = 24;

  @override
  Widget build(BuildContext context) {
    final tokens = SearchTokens.of(Theme.of(context).brightness);
    final dark = Theme.of(context).brightness == Brightness.dark;

    final rows = <Widget>[
      _SourceRow(
        tokens: tokens,
        icon: LucideIcons.images,
        tint: AppColors.accentStrong,
        label: context.t('issues.attachments.source.gallery'),
        subtitle: context.t('issues.attachments.source.galleryHint'),
        onTap: () => Navigator.of(context).pop(UploadSource.gallery),
      ),
      _SourceRow(
        tokens: tokens,
        icon: LucideIcons.camera,
        tint: const Color(0xFF3B82F6),
        label: context.t('issues.attachments.source.photo'),
        onTap: () => Navigator.of(context).pop(UploadSource.photo),
      ),
      _SourceRow(
        tokens: tokens,
        icon: LucideIcons.video,
        tint: const Color(0xFFEF4444),
        label: context.t('issues.attachments.source.video'),
        onTap: () => Navigator.of(context).pop(UploadSource.video),
      ),
      _SourceRow(
        tokens: tokens,
        icon: LucideIcons.folder,
        tint: AppColors.inkSoft,
        label: context.t('issues.attachments.source.files'),
        subtitle: context.t('issues.attachments.source.filesHint'),
        dividerAbove: true,
        onTap: () => Navigator.of(context).pop(UploadSource.files),
      ),
    ];

    final panel = GlassPanelShadow(
      radius: BorderRadius.circular(_radius),
      shadows: tokens.panelShadow,
      child: GlassContainer(
        useOwnLayer: true,
        quality: GlassQuality.premium,
        clipBehavior: Clip.antiAlias,
        shape: const LiquidRoundedSuperellipse(borderRadius: _radius),
        settings: liquidGlassPanelSettings(
          glassFill: tokens.glassFill,
          dark: dark,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              // Grab handle.
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: tokens.hairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    context.t('issues.attachments.source.title'),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: tokens.ink,
                    ),
                  ),
                ),
              ),
              ...rows,
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        child: panel,
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.tokens,
    required this.icon,
    required this.tint,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.dividerAbove = false,
  });

  final SearchTokens tokens;
  final IconData icon;
  final Color tint;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final bool dividerAbove;

  @override
  Widget build(BuildContext context) {
    final row = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 19, color: tint),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: tokens.ink,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 1),
                    Text(
                      subtitle!,
                      style: TextStyle(fontSize: 11.5, color: tokens.inkFaint),
                    ),
                  ],
                ],
              ),
            ),
            Icon(forwardChevron(context), size: 17, color: tokens.inkFaint),
          ],
        ),
      ),
    );

    if (!dividerAbove) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: row,
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 1,
          margin: const EdgeInsets.fromLTRB(20, 6, 20, 6),
          color: tokens.hairline,
        ),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: row),
      ],
    );
  }
}
