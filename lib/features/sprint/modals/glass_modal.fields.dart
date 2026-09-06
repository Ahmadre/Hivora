part of 'glass_modal.dart';

/// A labelled form field on the glass material.
class GlassField extends StatelessWidget {
  const GlassField({
    super.key,
    required this.label,
    required this.child,
    this.trailing,
  });

  final String label;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.inkSoft,
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 6), trailing!],
          ],
        ),
        const SizedBox(height: 7),
        child,
      ],
    );
  }
}

/// Input decoration for text fields rendered on the glass material.
InputDecoration glassInputDecoration({String? hint}) => InputDecoration(
  hintText: hint,
  isDense: true,
  filled: true,
  fillColor: AppColors.surface.withValues(alpha: 0.7),
  contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppTheme.radiusControl),
    borderSide: BorderSide(color: AppColors.hairline),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppTheme.radiusControl),
    borderSide: BorderSide(color: AppColors.hairline),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppTheme.radiusControl),
    borderSide: const BorderSide(color: AppColors.accent, width: 1.6),
  ),
);

/// A segmented selector (e.g. sprint duration 1–4 weeks) sized to fill width.
class GlassSegmented extends StatelessWidget {
  const GlassSegmented({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 130),
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: i == selected
                      ? AppColors.navy
                      : AppColors.surface.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                  border: Border.all(
                    color: i == selected ? AppColors.navy : AppColors.hairline,
                  ),
                ),
                child: Text(
                  labels[i],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: i == selected ? Colors.white : AppColors.inkSoft,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A read-only "commitment" / info line used in the start & complete modals.
class GlassInfoLine extends StatelessWidget {
  const GlassInfoLine({super.key, required this.icon, required this.child});

  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppColors.hairline.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.inkSoft),
          const SizedBox(width: 10),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// One "include this too" row: a title, a sentence saying what leaving it off
/// means, and the app's single toggle.
///
/// A switch rather than a checkbox on purpose. [HiveSwitch] is the one toggle
/// the app has, so a checkbox here would be a second visual language for the
/// same yes/no — and every one of these rows sits next to other switches.
class GlassOptionRow extends StatelessWidget {
  const GlassOptionRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;

  /// Null disables the row — the option exists but cannot be changed right now.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          HiveSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// Header row shared by every sprint modal: an amber icon tile, title + sub,
/// and a close button.
class GlassModalHeader extends StatelessWidget {
  const GlassModalHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actions = const [],
    this.subtitleMaxLines = 2,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  /// How many lines the subtitle may take before it is cut off.
  ///
  /// Two is right for a 420–540 wide modal. A header reused inside an anchored
  /// dropdown has a third of that width, where the same sentence ran out
  /// mid-word — a description that stops at "ein/aus u…" is worse than no
  /// description at all.
  final int subtitleMaxLines;

  /// Extra trailing action buttons rendered to the left of the close (X)
  /// button — e.g. a maximize/minimize toggle on the email composer.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 14, 14),
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
            child: Icon(icon, size: 20, color: AppColors.accentStrong),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontBrand,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: subtitleMaxLines,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ...actions,
          IconButton(
            tooltip: context.t('common.cancel'),
            icon: Icon(LucideIcons.x, size: 20, color: AppColors.inkSoft),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}

/// Footer with an optional leading hint and the Cancel / confirm buttons.
class GlassModalFooter extends StatelessWidget {
  const GlassModalFooter({
    super.key,
    required this.confirmLabel,
    required this.onConfirm,
    this.confirmIcon = LucideIcons.check,
    this.hint,
    this.busy = false,
    this.confirmColor,
  });

  final String confirmLabel;
  final VoidCallback? onConfirm;
  final IconData confirmIcon;
  final Widget? hint;
  final bool busy;

  /// Background colour of the confirm button. Defaults to the app's navy;
  /// pass [AppColors.danger] for destructive confirmations.
  final Color? confirmColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      // The bottom inset is the footer's own: as a dialog it never touched the
      // screen edge, but as the last row of a bottom sheet it sits exactly where
      // the home indicator is. `top: false` because the sheet's top is the
      // header's problem, not this one's.
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 18) +
          EdgeInsets.only(bottom: MediaQuery.viewPaddingOf(context).bottom),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.hairline.withValues(alpha: 0.6)),
        ),
      ),
      child: Row(
        children: [
          if (hint != null) Expanded(child: hint!) else const Spacer(),
          const SizedBox(width: 8),
          TextButton(
            onPressed: busy ? null : () => Navigator.of(context).maybePop(),
            child: Text(context.t('common.cancel')),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: busy ? null : onConfirm,
            style: FilledButton.styleFrom(
              backgroundColor: confirmColor ?? AppColors.navy,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              ),
            ),
            icon: busy
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(confirmIcon, size: 15),
            label: Text(confirmLabel),
          ),
        ],
      ),
    );
  }
}
