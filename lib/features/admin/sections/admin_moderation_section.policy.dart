part of 'admin_moderation_section.dart';

/// The content policy: what is scanned, at which score, and what happens when
/// the score is reached.
///
/// Mirrors the server's `ServerSettings.Moderation` block one field at a time,
/// which is also why every control here writes an explicit value: a `null` on
/// the server means "use the environment default", and the moment an admin
/// touches this panel they have expressed an intent that must outlive whatever
/// `HINATA_MODERATION_*` the container was started with. The defaults shown
/// below are the env defaults from `HinataProperties.Moderation`, so an
/// untouched panel saves exactly what was already in effect.
class _PolicyPanel extends StatefulWidget {
  const _PolicyPanel({required this.settings, this.imageTier});

  final Map<String, dynamic> settings;

  /// What the image tier is actually doing, or null while it is still unknown.
  ///
  /// Separate from the `imageEnabled` switch below because they answer different
  /// questions: the switch is an intention, this is the outcome, and on a fresh
  /// install they disagree — image moderation is on by default and no classifier
  /// ships with the product.
  final ImageTierState? imageTier;

  @override
  State<_PolicyPanel> createState() => _PolicyPanelState();
}

class _PolicyPanelState extends State<_PolicyPanel> {
  Map<String, dynamic> get _moderation =>
      (widget.settings['moderation'] ??= <String, dynamic>{})
          as Map<String, dynamic>;

  int _intVal(String key, int def) => (_moderation[key] as num?)?.toInt() ?? def;

  bool _boolVal(String key, {required bool def}) =>
      (_moderation[key] as bool?) ?? def;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ─── What runs ────────────────────────────────────────────
        AdminSectionCard(
          icon: LucideIcons.shieldCheck,
          title: context.t('moderation.policy.title'),
          subtitle: context.t('moderation.policy.hint'),
          children: [
            AdminToggle(
              label: context.t('moderation.policy.enabled'),
              subtitle: context.t('moderation.policy.enabledHint'),
              value: _boolVal('enabled', def: true),
              onChanged: (v) => setState(() => _moderation['enabled'] = v),
            ),
            const SizedBox(height: 4),
            AdminToggle(
              label: context.t('moderation.policy.text'),
              subtitle: context.t('moderation.policy.textHint'),
              value: _boolVal('textEnabled', def: true),
              onChanged: (v) => setState(() => _moderation['textEnabled'] = v),
            ),
            const SizedBox(height: 4),
            AdminToggle(
              label: context.t('moderation.policy.image'),
              subtitle: context.t('moderation.policy.imageHint'),
              value: _boolVal('imageEnabled', def: true),
              onChanged: (v) => setState(() => _moderation['imageEnabled'] = v),
            ),
            if (widget.imageTier != null) ...[
              const SizedBox(height: 10),
              _ImageTierNotice(state: widget.imageTier!),
            ],
          ],
        ),
        const SizedBox(height: 16),

        // ─── Thresholds ───────────────────────────────────────────
        AdminSectionCard(
          icon: LucideIcons.gauge,
          title: context.t('moderation.policy.thresholds'),
          subtitle: context.t('moderation.policy.thresholdsHint'),
          children: [
            AdminNumberField(
              label: context.t('moderation.policy.blockThreshold'),
              value: _intVal('blockThreshold', 85),
              min: 1,
              max: 100,
              suffix: context.t('moderation.policy.score'),
              onChanged: (v) =>
                  setState(() => _moderation['blockThreshold'] = v),
            ),
            AdminNumberField(
              label: context.t('moderation.policy.flagThreshold'),
              value: _intVal('flagThreshold', 55),
              min: 1,
              max: 100,
              suffix: context.t('moderation.policy.score'),
              onChanged: (v) =>
                  setState(() => _moderation['flagThreshold'] = v),
            ),
            AdminNote(
              text: context.t('moderation.policy.thresholdNote'),
              icon: LucideIcons.slidersHorizontal,
              tone: AdminNoteTone.info,
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ─── What happens on a hit ────────────────────────────────
        AdminSectionCard(
          icon: LucideIcons.gavel,
          title: context.t('moderation.policy.handling'),
          subtitle: context.t('moderation.policy.handlingHint'),
          children: [
            AdminToggle(
              label: context.t('moderation.policy.longFormFlagOnly'),
              // The one setting nobody guesses from its label: it decides
              // whether a long description is refused outright or quietly
              // queued, and getting it wrong loses people's written work.
              subtitle: context.t('moderation.policy.longFormFlagOnlyHint'),
              value: _boolVal('longFormFlagOnly', def: true),
              onChanged: (v) =>
                  setState(() => _moderation['longFormFlagOnly'] = v),
            ),
            const SizedBox(height: 4),
            AdminToggle(
              label: context.t('moderation.policy.failOpen'),
              subtitle: context.t('moderation.policy.failOpenHint'),
              value: _boolVal('failOpen', def: true),
              onChanged: (v) => setState(() => _moderation['failOpen'] = v),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ─── The two categories nobody may tune ───────────────────
        AdminSectionCard(
          icon: LucideIcons.lock,
          title: context.t('moderation.policy.locked'),
          subtitle: context.t('moderation.policy.lockedHint'),
          children: [
            for (final category in ModerationCategoryKind.all)
              if (!category.overridable)
                _LockedCategoryRow(category: category),
            const SizedBox(height: 10),
            AdminNote(
              text: context.t('moderation.policy.lockedNote'),
              icon: LucideIcons.shieldAlert,
              tone: AdminNoteTone.warning,
            ),
          ],
        ),
      ],
    );
  }
}

/// A read-only row for a category the settings above deliberately do not reach.
class _LockedCategoryRow extends StatelessWidget {
  const _LockedCategoryRow({required this.category});

  final ModerationCategoryKind category;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          border: Border.all(color: AppColors.hairline2),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.lock, size: 15, color: AppColors.inkFaint),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.t(category.labelKey),
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              context.t('moderation.policy.notConfigurable'),
              style: TextStyle(
                fontFamily: AppTheme.fontMono,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
                color: AppColors.inkFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// One line saying whether images are genuinely being classified.
///
/// It sits under the switch it contradicts. Image moderation defaults to on and
/// Hinata ships no classifier, so on a fresh install the switch reads "on" and
/// every upload goes unchecked — this is the only place in the product where
/// those two facts are shown together.
///
/// Rendered as an advisory row rather than a warning banner: running without an
/// image tier is a supported, documented configuration, and a red block on every
/// visit would teach operators to ignore the panel.
class _ImageTierNotice extends StatelessWidget {
  const _ImageTierNotice({required this.state});

  final ImageTierState state;

  @override
  Widget build(BuildContext context) {
    final attention = state.warrantsAttention;
    final color = attention ? AppColors.warning : AppColors.inkFaint;
    final icon = switch (state) {
      ImageTierState.active => LucideIcons.circleCheck,
      ImageTierState.disabledByPolicy => LucideIcons.circleMinus,
      _ => LucideIcons.triangleAlert,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: attention ? 0.10 : 0.06),
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: color.withValues(alpha: attention ? 0.28 : 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: 10),
          // Flexible, not fixed: these strings are translations and the panel is
          // reachable on a phone-width admin screen.
          Flexible(
            child: Text(
              context.t(state.labelKey),
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                fontWeight: FontWeight.w600,
                color: AppColors.inkSoft,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
