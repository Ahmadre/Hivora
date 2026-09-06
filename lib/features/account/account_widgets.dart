import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// A titled card section used down the account screen. Header carries an amber
/// icon tile + title/subtitle and an optional trailing widget.
class AccountSection extends StatelessWidget {
  const AccountSection({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.children,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> children;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final accent = danger ? AppColors.danger : AppColors.accentStrong;
    final accentBg = danger
        ? AppColors.danger.withValues(alpha: 0.12)
        : AppColors.accentSoft;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(
          color: danger
              ? AppColors.danger.withValues(alpha: 0.35)
              : AppColors.hairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: accentBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 18, color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontFamily: AppTheme.fontBrand,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: danger ? AppColors.danger : AppColors.ink,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.hairline2),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

/// A label/value/control row that stacks the control below the label on phone
/// so it never overflows (per the responsive spec).
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.label,
    this.description,
    this.trailing,
    this.icon,
    this.stack = false,
    this.onTap,
  });

  final String label;
  final String? description;
  final Widget? trailing;
  final IconData? icon;

  /// When true, the trailing control wraps below the text (narrow widths).
  final bool stack;

  /// When set, the whole row becomes tappable (ListTile-style) with a ripple
  /// that spans the full card width — not just the text/trailing controls.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        if (description != null) ...[
          const SizedBox(height: 2),
          Text(
            description!,
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: AppColors.inkSoft,
            ),
            softWrap: true,
          ),
        ],
      ],
    );

    final body = stack
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16, color: AppColors.inkSoft),
                    const SizedBox(width: 10),
                  ],
                  Expanded(child: text),
                ],
              ),
              if (trailing != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: trailing!,
                ),
              ],
            ],
          )
        : Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: AppColors.inkSoft),
                const SizedBox(width: 10),
              ],
              Expanded(child: text),
              if (trailing != null) ...[const SizedBox(width: 12), trailing!],
            ],
          );

    if (onTap == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: body,
      );
    }

    // Tappable variant (ListTile-style): the whole row responds to taps with a
    // ripple. The padding lives inside the InkWell so the ink covers the full
    // row height, and matches the default row's vertical inset + horizontal
    // alignment so a tappable row sits flush with its static siblings.
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: body,
        ),
      ),
    );
  }
}

/// A small pill (e.g. "Verified", role badges, "Always on").
class AccountPill extends StatelessWidget {
  const AccountPill({
    super.key,
    required this.label,
    this.icon,
    this.color,
    this.background,
  });

  final String label;
  final IconData? icon;
  final Color? color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? AppColors.accentStrong;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: background ?? fg.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// A flat outline button used for in-section actions (Change, Reset…).
class AccountActionButton extends StatelessWidget {
  const AccountActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final fg = danger ? AppColors.danger : AppColors.ink;
    return Material(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            border: Border.all(
              color: danger
                  ? AppColors.danger.withValues(alpha: 0.4)
                  : AppColors.hairline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: fg),
                const SizedBox(width: 7),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An amber/red note banner used for the pending-email and danger hints.
class AccountNote extends StatelessWidget {
  const AccountNote({
    super.key,
    required this.text,
    this.icon = LucideIcons.info,
    this.tone = AccountNoteTone.warn,
  });

  final String text;
  final IconData icon;
  final AccountNoteTone tone;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      AccountNoteTone.warn => AppColors.warning,
      AccountNoteTone.danger => AppColors.danger,
      AccountNoteTone.info => AppColors.stTodo,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: AppColors.ink,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum AccountNoteTone { warn, danger, info }
