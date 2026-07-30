part of 'admin_audit_section.dart';

// ─────────────────────────── Day header ──────────────────────────────────

class _DayHeader {
  const _DayHeader(this.day);
  final DateTime day;
}

class _DayHeaderRow extends StatelessWidget {
  const _DayHeaderRow({required this.day});
  final DateTime day;

  String _label(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final diff = today.difference(day).inDays;
    if (diff == 0) return context.t('audit.today');
    if (diff == 1) return context.t('audit.yesterday');
    final locale = Localizations.localeOf(context).toString();
    return DateFormat('EEEE, d MMM y', locale).format(day);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
      child: Row(
        children: [
          Text(
            _label(context).toUpperCase(),
            style: TextStyle(
              fontFamily: AppTheme.fontMono,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AppColors.inkFaint,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Container(height: 1, color: AppColors.hairline)),
        ],
      ),
    );
  }
}

// ─────────────────────────── Timeline tile ───────────────────────────────

class _AuditTimelineTile extends StatelessWidget {
  const _AuditTimelineTile({
    required this.entry,
    required this.isLastInGroup,
    required this.onTap,
  });

  final AuditEntry entry;
  final bool isLastInGroup;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tint = _severityColor(entry.severity);
    final failed = entry.outcome == AuditOutcome.failure;
    final glyphTint = failed ? AppColors.danger : tint;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Timeline rail: glyph + connecting line ──
          SizedBox(
            width: 44,
            child: Column(
              children: [
                _GlyphBadge(icon: _actionIcon(entry.action), tint: glyphTint),
                if (!isLastInGroup)
                  Expanded(
                    child: Center(
                      child: Container(width: 2, color: AppColors.hairline),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          // ── Content card ──
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _card(context, glyphTint, failed),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, Color tint, bool failed) {
    final locale = Localizations.localeOf(context).toString();
    final time = DateFormat.Hm(locale).format(entry.timestamp);
    final subtitle = _actorTargetLine(context, entry);

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(color: AppColors.hairline),
          ),
          padding: const EdgeInsets.fromLTRB(13, 11, 11, 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      context.t('audit.action.${entry.action}'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                        height: 1.25,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      time,
                      style: TextStyle(
                        fontFamily: AppTheme.fontMono,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.inkFaint,
                      ),
                    ),
                  ),
                ],
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.inkSoft,
                    height: 1.3,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _MiniChip(
                    icon: _categoryIcon(entry.category),
                    label: context.t('audit.category.${entry.category.name}'),
                  ),
                  if (failed)
                    _MiniChip(
                      icon: LucideIcons.circleX,
                      label: context.t('audit.outcome.failure'),
                      color: AppColors.danger,
                    )
                  else if (entry.severity == AuditSeverity.warning)
                    _MiniChip(
                      icon: LucideIcons.triangleAlert,
                      label: context.t('audit.severity.warning'),
                      color: AppColors.warning,
                    ),
                  if (entry.ip != null && entry.ip!.isNotEmpty)
                    _MiniChip(
                      icon: LucideIcons.mapPin,
                      label: entry.ip!,
                      mono: true,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlyphBadge extends StatelessWidget {
  const _GlyphBadge({required this.icon, required this.tint});
  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: tint.withValues(alpha: 0.28)),
      ),
      child: Icon(icon, size: 17, color: tint),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({
    required this.icon,
    required this.label,
    this.color,
    this.mono = false,
  });

  final IconData icon;
  final String label;
  final Color? color;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.inkSoft;
    final bg = color == null
        ? AppColors.surfaceMuted
        : color!.withValues(alpha: 0.12);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: color == null ? Border.all(color: AppColors.hairline2) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: c),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: mono ? AppTheme.fontMono : null,
              fontSize: mono ? 10.5 : 11,
              fontWeight: FontWeight.w600,
              color: c,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Error view ──────────────────────────────────

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.cloudOff, size: 40, color: AppColors.inkFaint),
            const SizedBox(height: 14),
            Text(
              context.t('audit.error'),
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.inkSoft, fontSize: 14),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(LucideIcons.refreshCw, size: 15),
              label: Text(context.t('audit.retry')),
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

// ─────────────────────────── Detail sheet ────────────────────────────────

/// Opens a liquid-glass bottom sheet with the full record for [entry].
Future<void> showAuditDetailSheet(BuildContext context, AuditEntry entry) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.32),
    builder: (_) => _AuditDetailSheet(entry: entry),
  );
}
