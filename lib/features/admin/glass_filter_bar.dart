import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassContainer, GlassQuality, LiquidRoundedSuperellipse;

import '../../core/theme/app_colors.dart';
import '../../core/widgets/frosted_surface.dart';
import '../../core/widgets/glass_popup_menu.dart';
import '../shell/app_shell.dart' show isNativeApp;
import '../../core/theme/glass_chrome.dart' show kNavGlassDark, kNavGlassLight;

/// Height of one docked control row (search / chip row) — the pill height.
const double kAdminPillHeight = 42;

/// A liquid-glass pill surface used by every docked filter control. On native it
/// is a real [GlassContainer] (its own glass layer, iOS-26 refraction); on web it
/// is a [FrostedSurface] (a nested backdrop blur pixelates on Skia). [active]
/// lays an amber wash over the glass so a live filter reads clearly on both.
class AdminGlassPill extends StatelessWidget {
  const AdminGlassPill({
    super.key,
    required this.child,
    this.onTap,
    this.active = false,
    this.height = kAdminPillHeight,
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool active;
  final double height;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = height / 2;
    final br = BorderRadius.circular(radius);

    Widget inner = child;
    if (active) {
      inner = DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: dark ? 0.22 : 0.15),
          borderRadius: br,
        ),
        child: child,
      );
    }

    Widget surface;
    if (isNativeApp) {
      surface = GlassContainer(
        useOwnLayer: true,
        quality: GlassQuality.premium,
        clipBehavior: Clip.antiAlias,
        shape: LiquidRoundedSuperellipse(borderRadius: radius),
        settings: dark ? kNavGlassDark : kNavGlassLight,
        child: inner,
      );
    } else {
      surface = FrostedSurface(
        borderRadius: br,
        dark: dark,
        child: ClipRRect(borderRadius: br, child: inner),
      );
    }

    surface = SizedBox(height: height, child: surface);
    if (onTap == null) return surface;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: surface,
    );
  }
}

/// A glass search field for a docked toolbar — the pill surface wrapping a bare,
/// transparent [TextField].
class AdminGlassSearchField extends StatelessWidget {
  const AdminGlassSearchField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.controller,
  });

  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    return AdminGlassPill(
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: 14, end: 10),
        child: Row(
          children: [
            Icon(LucideIcons.search, size: 17, color: AppColors.inkSoft),
            const SizedBox(width: 9),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                textInputAction: TextInputAction.search,
                style: TextStyle(fontSize: 14, color: AppColors.ink),
                cursorColor: AppColors.accentStrong,
                // The pill itself is the surface — strip every field border/fill
                // so the theme's amber focus outline can't bleed through.
                decoration: InputDecoration(
                  isCollapsed: true,
                  filled: false,
                  hintText: hint,
                  hintStyle: TextStyle(fontSize: 14, color: AppColors.inkFaint),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A read-only amber count pill (e.g. "200 Ereignisse").
class AdminCountPill extends StatelessWidget {
  const AdminCountPill({
    super.key,
    required this.label,
    this.icon = LucideIcons.history,
  });

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return AdminGlassPill(
      active: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.accentStrong),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.accentStrong,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A glass dropdown filter chip ("Kategorie ▾"). The trigger is an [AdminGlassPill]
/// (real glass on native / frosted on web) and the menu itself is the app's glass
/// [GlassPopupMenu]. [value] `null` (or the first option) means "no filter".
class AdminFilterChip<T> extends StatelessWidget {
  const AdminFilterChip({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.menuWidth = 230,
  });

  final IconData icon;
  final String label;
  final T value;

  /// (value, label) pairs; the first is treated as the "all / any" reset.
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;
  final double menuWidth;

  @override
  Widget build(BuildContext context) {
    final active = value != null && value != options.first.$1;
    final current = options.firstWhere(
      (o) => o.$1 == value,
      orElse: () => options.first,
    );
    final text = active ? current.$2 : label;
    final fg = active ? AppColors.accentStrong : AppColors.inkSoft;

    return GlassPopupMenu<int>(
      value: -1,
      width: menuWidth,
      onSelected: (i) => onChanged(options[i].$1),
      items: [
        for (var i = 0; i < options.length; i++)
          GlassMenuItem(value: i, label: options[i].$2),
      ],
      child: AdminGlassPill(
        active: active,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: fg),
              const SizedBox(width: 7),
              Text(
                text,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
              const SizedBox(width: 5),
              Icon(
                LucideIcons.chevronDown,
                size: 14,
                color: AppColors.inkFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
