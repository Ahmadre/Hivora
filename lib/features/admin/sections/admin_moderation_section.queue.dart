part of 'admin_moderation_section.dart';

// ─────────────────────────── Queue header ────────────────────────────────

/// Title, the two queue tabs, and the filter bar.
///
/// Below [kGlassPopoverBreakpoint] the chips wrap onto as many rows as they
/// need instead of scrolling sideways: a moderator working a backlog on a phone
/// reaches for a filter constantly, and a horizontal strip hides the one they
/// want behind a swipe.
class _QueueHeader extends StatelessWidget {
  const _QueueHeader({
    required this.tab,
    required this.wide,
    required this.total,
    required this.loading,
    required this.hasFilters,
    required this.recordState,
    required this.reportState,
    required this.surface,
    required this.category,
    required this.onTab,
    required this.onRecordState,
    required this.onReportState,
    required this.onSurface,
    required this.onCategory,
    required this.onClear,
  });

  final _QueueTab tab;
  final bool wide;
  final int total;
  final bool loading;
  final bool hasFilters;
  final ModerationReviewState? recordState;
  final ContentReportState? reportState;
  final ModerationSurfaceKind? surface;
  final ModerationCategoryKind? category;
  final ValueChanged<_QueueTab> onTab;
  final ValueChanged<ModerationReviewState?> onRecordState;
  final ValueChanged<ContentReportState?> onReportState;
  final ValueChanged<ModerationSurfaceKind?> onSurface;
  final ValueChanged<ModerationCategoryKind?> onCategory;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final flagged = tab == _QueueTab.flagged;

    final chips = <Widget>[
      AdminCountPill(
        icon: flagged ? LucideIcons.flag : LucideIcons.inbox,
        label: loading
            ? '…'
            : context.t('moderation.queue.count', variables: {'count': total}),
      ),
      if (flagged)
        AdminFilterChip<ModerationReviewState?>(
          icon: LucideIcons.listChecks,
          label: context.t('moderation.queue.filter.state'),
          value: recordState,
          onChanged: onRecordState,
          options: [
            (null, context.t('moderation.queue.filter.allStates')),
            for (final state in ModerationReviewState.values)
              (state, context.t(state.labelKey)),
          ],
        )
      else
        AdminFilterChip<ContentReportState?>(
          icon: LucideIcons.listChecks,
          label: context.t('moderation.queue.filter.state'),
          value: reportState,
          onChanged: onReportState,
          options: [
            (null, context.t('moderation.queue.filter.allStates')),
            for (final state in ContentReportState.values)
              (state, context.t(state.labelKey)),
          ],
        ),
      if (flagged) ...[
        AdminFilterChip<ModerationSurfaceKind?>(
          icon: LucideIcons.layers,
          label: context.t('moderation.queue.filter.surface'),
          value: surface,
          menuWidth: 260,
          onChanged: onSurface,
          options: [
            (null, context.t('moderation.queue.filter.allSurfaces')),
            for (final value in ModerationSurfaceKind.values)
              if (value != ModerationSurfaceKind.unknown)
                (value, context.t(value.labelKey)),
          ],
        ),
        AdminFilterChip<ModerationCategoryKind?>(
          icon: LucideIcons.shieldAlert,
          label: context.t('moderation.queue.filter.category'),
          value: category,
          menuWidth: 260,
          onChanged: onCategory,
          options: [
            (null, context.t('moderation.queue.filter.allCategories')),
            for (final value in ModerationCategoryKind.all)
              (value, context.t(value.labelKey)),
          ],
        ),
      ],
      if (hasFilters)
        AdminGlassPill(
          onTap: onClear,
          child: SizedBox(
            width: kAdminPillHeight,
            child: Icon(
              LucideIcons.filterX,
              size: 17,
              color: AppColors.inkSoft,
            ),
          ),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.t('moderation.queue.title'),
          style: TextStyle(
            fontFamily: AppTheme.fontBrand,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          context.t('moderation.queue.hint'),
          style: TextStyle(
            fontSize: 12.5,
            height: 1.4,
            color: AppColors.inkSoft,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            _TabPill(
              icon: LucideIcons.flag,
              label: context.t('moderation.queue.tab.flagged'),
              active: flagged,
              onTap: () => onTab(_QueueTab.flagged),
            ),
            const SizedBox(width: 8),
            _TabPill(
              icon: LucideIcons.megaphone,
              label: context.t('moderation.queue.tab.reports'),
              active: !flagged,
              onTap: () => onTab(_QueueTab.reports),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (wide)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < chips.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  chips[i],
                ],
              ],
            ),
          )
        else
          Wrap(spacing: 8, runSpacing: 8, children: chips),
        const SizedBox(height: 14),
      ],
    );
  }
}

/// One of the two queue tabs, drawn on the same glass pill as the filter chips
/// so the whole bar reads as one control strip.
class _TabPill extends StatelessWidget {
  const _TabPill({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.accentStrong : AppColors.inkSoft;
    return AdminGlassPill(
      active: active,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                color: active ? AppColors.accentStrong : AppColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── Rows ────────────────────────────────────────

/// A flagged verdict.
class _RecordRow extends StatelessWidget {
  const _RecordRow({
    required this.record,
    required this.wide,
    required this.busy,
    required this.selected,
    required this.onToggleSelected,
    required this.onOpen,
    required this.onConfirm,
    required this.onDismiss,
  });

  final ModerationRecord record;
  final bool wide;
  final bool busy;
  final bool selected;
  final VoidCallback onToggleSelected;
  final VoidCallback? onOpen;
  final VoidCallback onConfirm;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final tint = _decisionTint(record.decision);
    return _QueueRow(
      icon: _surfaceIcon(record.surface),
      tint: tint,
      title: context.t(record.surface.labelKey),
      label: record.label,
      trailing: _ScoreBadge(score: record.score, tint: tint),
      chips: [
        _MetaChip(
          icon: LucideIcons.shieldAlert,
          label: context.t(record.category.labelKey),
          color: tint,
        ),
        // A degraded verdict means a tier could not run. Recording it is only
        // worth anything if the queue says so out loud — otherwise the bypass
        // looks exactly like a clean judgement.
        if (record.degraded)
          _MetaChip(
            icon: LucideIcons.cloudOff,
            label: context.t('moderation.queue.row.degraded'),
            color: AppColors.warning,
            tooltip: context.t('moderation.queue.row.degradedHint'),
          ),
        _MetaChip(
          icon: LucideIcons.scanEye,
          label: context.t(record.tier.labelKey),
          mono: true,
        ),
        _MetaChip(
          icon: LucideIcons.user,
          label:
              record.authorName ??
              context.t('moderation.queue.row.unknownAuthor'),
        ),
        _MetaChip(
          icon: LucideIcons.folder,
          label:
              record.projectName ??
              context.t('moderation.queue.row.noProject'),
        ),
        _MetaChip(icon: LucideIcons.clock, label: _when(context, record.createdAt)),
      ],
      wide: wide,
      busy: busy,
      selected: selected,
      onToggleSelected: onToggleSelected,
      onOpen: onOpen,
      onConfirm: onConfirm,
      onDismiss: onDismiss,
      confirmIcon: LucideIcons.gavel,
      confirmLabel: context.t('moderation.queue.action.confirm'),
    );
  }
}

/// A report a user filed.
class _ReportRow extends StatelessWidget {
  const _ReportRow({
    required this.report,
    required this.wide,
    required this.busy,
    required this.selected,
    required this.onToggleSelected,
    required this.onOpen,
    required this.onConfirm,
    required this.onDismiss,
  });

  final ContentReport report;
  final bool wide;
  final bool busy;
  final bool selected;
  final VoidCallback onToggleSelected;
  final VoidCallback? onOpen;
  final VoidCallback onConfirm;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return _QueueRow(
      icon: _surfaceIcon(report.surface),
      tint: AppColors.accentStrong,
      title: context.t(report.surface.labelKey),
      label: report.label,
      subtitle: report.reason,
      chips: [
        _MetaChip(
          icon: LucideIcons.shieldAlert,
          label: context.t(report.category.labelKey),
          color: AppColors.accentStrong,
        ),
        _MetaChip(
          icon: LucideIcons.megaphone,
          label: context.t(
            'moderation.queue.row.reportedBy',
            variables: {
              'name':
                  report.reporterName ??
                  context.t('moderation.queue.row.anonymous'),
            },
          ),
        ),
        _MetaChip(
          icon: LucideIcons.user,
          label:
              report.authorName ??
              context.t('moderation.queue.row.unknownAuthor'),
        ),
        _MetaChip(
          icon: LucideIcons.folder,
          label:
              report.projectName ??
              context.t('moderation.queue.row.noProject'),
        ),
        _MetaChip(icon: LucideIcons.clock, label: _when(context, report.createdAt)),
      ],
      wide: wide,
      busy: busy,
      selected: selected,
      onToggleSelected: onToggleSelected,
      onOpen: onOpen,
      onConfirm: onConfirm,
      onDismiss: onDismiss,
      confirmIcon: LucideIcons.gavel,
      confirmLabel: context.t('moderation.queue.action.uphold'),
    );
  }
}

/// The frame both queues share: selection box, surface glyph, what it is, who
/// it belongs to, and the three things a moderator can do about it.
class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.icon,
    required this.tint,
    required this.title,
    required this.chips,
    required this.wide,
    required this.busy,
    required this.selected,
    required this.onToggleSelected,
    required this.onOpen,
    required this.onConfirm,
    required this.onDismiss,
    required this.confirmIcon,
    required this.confirmLabel,
    this.label,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final Color tint;
  final String title;

  /// The short handle the server put on the record — an issue key, a file name.
  final String? label;

  /// Free text that belongs to the row itself (a reporter's words), never the
  /// moderated content.
  final String? subtitle;

  final List<Widget> chips;
  final Widget? trailing;
  final bool wide;
  final bool busy;
  final bool selected;
  final VoidCallback onToggleSelected;
  final VoidCallback? onOpen;
  final VoidCallback onConfirm;
  final VoidCallback onDismiss;
  final IconData confirmIcon;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 11, 8, 11),
      decoration: BoxDecoration(
        color: selected ? AppColors.accentSoft : AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(
          color: selected ? AppColors.accentLine : AppColors.hairline,
        ),
      ),
      // Transparent Material so the action buttons' ink lands in FRONT of this
      // opaque row instead of on whatever Material sits behind it, where it
      // would be invisible.
      child: Material(
        type: MaterialType.transparency,
        child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 9),
            child: _SelectBox(checked: selected, onTap: onToggleSelected),
          ),
          const SizedBox(width: 12),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: tint.withValues(alpha: 0.28)),
            ),
            child: Icon(icon, size: 17, color: tint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: 8),
                      trailing!,
                    ],
                  ],
                ),
                if (label != null && label!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      label!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTheme.fontMono,
                        fontSize: 11.5,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: chips),
              ],
            ),
          ),
          const SizedBox(width: 6),
          _RowActions(
            wide: wide,
            busy: busy,
            onOpen: onOpen,
            onConfirm: onConfirm,
            onDismiss: onDismiss,
            confirmIcon: confirmIcon,
            confirmLabel: confirmLabel,
          ),
        ],
        ),
      ),
    );
  }
}

/// Open / confirm / dismiss — three icon buttons where there is room, and a
/// single glass menu where there is not.
class _RowActions extends StatelessWidget {
  const _RowActions({
    required this.wide,
    required this.busy,
    required this.onOpen,
    required this.onConfirm,
    required this.onDismiss,
    required this.confirmIcon,
    required this.confirmLabel,
  });

  final bool wide;
  final bool busy;
  final VoidCallback? onOpen;
  final VoidCallback onConfirm;
  final VoidCallback onDismiss;
  final IconData confirmIcon;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    final openLabel = context.t('moderation.queue.action.open');
    final dismissLabel = context.t('moderation.queue.action.dismiss');

    if (wide) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _IconAction(
            icon: LucideIcons.externalLink,
            tooltip: onOpen == null
                ? context.t('moderation.queue.action.openUnavailable')
                : openLabel,
            color: AppColors.inkSoft,
            onTap: busy ? null : onOpen,
          ),
          _IconAction(
            icon: confirmIcon,
            tooltip: confirmLabel,
            color: AppColors.danger,
            onTap: busy ? null : onConfirm,
          ),
          _IconAction(
            icon: LucideIcons.circleCheck,
            tooltip: dismissLabel,
            color: AppColors.success,
            onTap: busy ? null : onDismiss,
          ),
        ],
      );
    }

    return GlassPopupMenu<_RowAction>(
      value: _RowAction.none,
      width: 220,
      onSelected: (action) {
        if (busy) return;
        switch (action) {
          case _RowAction.open:
            onOpen?.call();
          case _RowAction.confirm:
            onConfirm();
          case _RowAction.dismiss:
            onDismiss();
          case _RowAction.none:
            break;
        }
      },
      items: [
        GlassMenuItem(
          value: _RowAction.open,
          label: openLabel,
          enabled: onOpen != null,
          disabledReason: context.t('moderation.queue.action.openUnavailable'),
          leading: Icon(
            LucideIcons.externalLink,
            size: 16,
            color: AppColors.inkSoft,
          ),
        ),
        GlassMenuItem(
          value: _RowAction.confirm,
          label: confirmLabel,
          color: AppColors.danger,
          leading: Icon(confirmIcon, size: 16, color: AppColors.danger),
        ),
        GlassMenuItem(
          value: _RowAction.dismiss,
          label: dismissLabel,
          leading: const Icon(
            LucideIcons.circleCheck,
            size: 16,
            color: AppColors.success,
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(
          LucideIcons.ellipsisVertical,
          size: 18,
          color: AppColors.inkSoft,
        ),
      ),
    );
  }
}

/// Menu values for the compact row menu. [none] is the "nothing selected"
/// sentinel [GlassPopupMenu] needs for its check mark.
enum _RowAction { none, open, confirm, dismiss }

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, size: 17, color: onTap == null ? AppColors.inkFaint : color),
    );
  }
}

/// The confidence the machine had, 0–100.
class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.score, required this.tint});

  final int score;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: context.t('moderation.queue.row.score'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: tint.withValues(alpha: 0.3)),
        ),
        child: Text(
          '$score',
          style: TextStyle(
            fontFamily: AppTheme.fontMono,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: tint,
          ),
        ),
      ),
    );
  }
}

/// A small icon+label fact on a row.
class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    this.color,
    this.mono = false,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final Color? color;
  final bool mono;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final ink = color ?? AppColors.inkSoft;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      constraints: const BoxConstraints(maxWidth: 260),
      decoration: BoxDecoration(
        color: color == null
            ? AppColors.surfaceMuted
            : color!.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: color == null ? Border.all(color: AppColors.hairline2) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: ink),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: mono ? AppTheme.fontMono : null,
                fontSize: mono ? 10.5 : 11,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
          ),
        ],
      ),
    );
    return tooltip == null ? chip : Tooltip(message: tooltip!, child: chip);
  }
}

/// The row-selection box, matched to the user-management board's.
class _SelectBox extends StatelessWidget {
  const _SelectBox({required this.checked, required this.onTap});

  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 18,
        height: 18,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: checked ? AppColors.navy : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: checked ? AppColors.navy : AppColors.hairline,
            width: 1.5,
          ),
        ),
        child: checked
            ? const Icon(LucideIcons.check, size: 13, color: Colors.white)
            : null,
      ),
    );
  }
}

// ─────────────────────────── Error view ──────────────────────────────────

class _QueueError extends StatelessWidget {
  const _QueueError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.cloudOff, size: 40, color: AppColors.inkFaint),
            const SizedBox(height: 14),
            Text(
              context.t(message),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.inkSoft),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(LucideIcons.refreshCw, size: 15),
              label: Text(context.t('common.retry')),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.ink,
                side: BorderSide(color: AppColors.hairline),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── Row vocabulary ──────────────────────────────

/// Absolute date + time. Deliberately not "3 hours ago": a moderation decision
/// is a legal record, and a queue that only says "recently" is useless the
/// moment someone asks when the content was actually judged.
String _when(BuildContext context, DateTime at) {
  final locale = Localizations.localeOf(context).toString();
  return DateFormat.MMMd(locale).add_Hm().format(at);
}

/// Blocked reads as a refusal that already happened, flagged as a suspicion
/// still open — so the glyph tint carries the outcome before the score does.
Color _decisionTint(ModerationDecisionKind decision) => switch (decision) {
  ModerationDecisionKind.block => AppColors.danger,
  ModerationDecisionKind.flag => AppColors.warning,
  ModerationDecisionKind.allow || ModerationDecisionKind.unknown =>
    AppColors.accentStrong,
};

IconData _surfaceIcon(ModerationSurfaceKind surface) => switch (surface) {
  ModerationSurfaceKind.issueTitle ||
  ModerationSurfaceKind.issueDescription => LucideIcons.fileText,
  ModerationSurfaceKind.comment => LucideIcons.messageSquare,
  ModerationSurfaceKind.articleTitle ||
  ModerationSurfaceKind.articleContent => LucideIcons.bookOpen,
  ModerationSurfaceKind.worklog => LucideIcons.clock,
  ModerationSurfaceKind.entityName ||
  ModerationSurfaceKind.entityDescription => LucideIcons.folder,
  ModerationSurfaceKind.profile || ModerationSurfaceKind.avatar =>
    LucideIcons.userRound,
  ModerationSurfaceKind.inviteMessage ||
  ModerationSurfaceKind.emailIngest ||
  ModerationSurfaceKind.emailAttachment ||
  ModerationSurfaceKind.emailReply => LucideIcons.mail,
  ModerationSurfaceKind.attachment => LucideIcons.paperclip,
  ModerationSurfaceKind.inlineImage ||
  ModerationSurfaceKind.externalImage => LucideIcons.image,
  ModerationSurfaceKind.organisationLogo => LucideIcons.building2,
  ModerationSurfaceKind.voice => LucideIcons.mic,
  ModerationSurfaceKind.gitCommit => LucideIcons.gitCommitHorizontal,
  ModerationSurfaceKind.mcp => LucideIcons.bot,
  ModerationSurfaceKind.unknown => LucideIcons.shieldQuestion,
};
