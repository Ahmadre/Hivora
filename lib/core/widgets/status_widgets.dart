import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../i18n/i18n.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'hive_loader.dart';

/// Small rounded pill, e.g. "High Priority" or a workflow state.
class PillChip extends StatelessWidget {
  const PillChip({
    super.key,
    required this.label,
    this.background,
    this.foreground,
  });

  final String label;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background ?? AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.hairline2),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground ?? AppColors.inkSoft,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// State badge shown inline in issue rows. [color] overrides the global
/// state-palette color (used to honour a project's configured state hue).
class StateBadge extends StatelessWidget {
  const StateBadge({super.key, required this.state, this.color});
  final String state;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? AppColors.stateColor(state);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.soft(color),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        state.replaceAll('_', ' '),
        style: TextStyle(
          fontFamily: AppTheme.fontMono,
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }
}

/// Resolves priority → display color using the new design token mapping.
Color priorityColor(String priority) => AppColors.priorityColor(priority);

/// Centralized async UI: loading spinner, error with retry, empty hint.
class AsyncView extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.isLoading,
    required this.hasData,
    required this.builder,
    this.errorKey,
    this.onRetry,
    this.emptyKey = 'common.empty',
  });

  final bool isLoading;
  final bool hasData;
  final String? errorKey;
  final VoidCallback? onRetry;
  final String emptyKey;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    if (isLoading && !hasData) {
      return const Center(
        child: Padding(padding: EdgeInsets.all(40), child: HiveLoader()),
      );
    }
    if (errorKey != null && !hasData) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.cloudOff, size: 40, color: AppColors.inkFaint),
              const SizedBox(height: 12),
              Text(
                context.t(errorKey!),
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.inkSoft),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: onRetry,
                  child: Text(context.t('common.retry')),
                ),
              ],
            ],
          ),
        ),
      );
    }
    if (!hasData) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            context.t(emptyKey),
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.inkSoft),
          ),
        ),
      );
    }
    return builder(context);
  }
}
