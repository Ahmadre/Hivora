part of 'admin_audit_section.dart';

class _AuditDetailSheet extends StatelessWidget {
  const _AuditDetailSheet({required this.entry});
  final AuditEntry entry;

  static const double _radius = 24;

  @override
  Widget build(BuildContext context) {
    final tokens = SearchTokens.of(Theme.of(context).brightness);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final locale = Localizations.localeOf(context).toString();
    final failed = entry.outcome == AuditOutcome.failure;
    final tint = failed ? AppColors.danger : _severityColor(entry.severity);

    final when = DateFormat.yMMMMEEEEd(
      locale,
    ).add_Hms().format(entry.timestamp);

    final rows = <Widget>[
      _DetailRow(
        icon: LucideIcons.user,
        label: context.t('audit.detail.actor'),
        value: entry.actorLabel?.isNotEmpty == true
            ? entry.actorLabel!
            : context.t('audit.actor.system'),
        sub: entry.actorId,
        tokens: tokens,
      ),
      if (entry.targetLabel?.isNotEmpty == true || entry.targetId != null)
        _DetailRow(
          icon: LucideIcons.target,
          label: context.t('audit.detail.target'),
          value: entry.targetLabel?.isNotEmpty == true
              ? entry.targetLabel!
              : (entry.targetId ?? '—'),
          sub: entry.targetLabel?.isNotEmpty == true ? entry.targetId : null,
          tokens: tokens,
        ),
      _DetailRow(
        icon: LucideIcons.clock,
        label: context.t('audit.detail.when'),
        value: when,
        tokens: tokens,
      ),
      _DetailRow(
        icon: LucideIcons.layers,
        label: context.t('audit.detail.category'),
        value: context.t('audit.category.${entry.category.name}'),
        tokens: tokens,
      ),
      _DetailRow(
        icon: LucideIcons.signal,
        label: context.t('audit.detail.severity'),
        value: context.t('audit.severity.${entry.severity.name}'),
        valueColor: _severityColor(entry.severity),
        tokens: tokens,
      ),
      _DetailRow(
        icon: failed ? LucideIcons.circleX : LucideIcons.circleCheck,
        label: context.t('audit.detail.outcome'),
        value: context.t('audit.outcome.${entry.outcome.name}'),
        valueColor: failed ? AppColors.danger : AppColors.success,
        tokens: tokens,
      ),
      if (entry.ip != null && entry.ip!.isNotEmpty)
        _DetailRow(
          icon: LucideIcons.mapPin,
          label: context.t('audit.detail.ip'),
          value: entry.ip!,
          mono: true,
          tokens: tokens,
        ),
      if (entry.userAgent != null && entry.userAgent!.isNotEmpty)
        _DetailRow(
          icon: LucideIcons.monitorSmartphone,
          label: context.t('audit.detail.device'),
          value: entry.userAgent!,
          tokens: tokens,
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
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.82,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: tokens.hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
                  child: Row(
                    children: [
                      _GlyphBadge(icon: _actionIcon(entry.action), tint: tint),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              context.t('audit.action.${entry.action}'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: tokens.ink,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              context.t('audit.detail.title'),
                              style: TextStyle(
                                fontSize: 12,
                                color: tokens.inkFaint,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: Icon(
                          LucideIcons.x,
                          size: 18,
                          color: tokens.inkSoft,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(18, 6, 18, 4),
                    children: [
                      ...rows,
                      if (entry.metadata.isNotEmpty)
                        _MetadataBlock(
                          metadata: entry.metadata,
                          tokens: tokens,
                        ),
                    ],
                  ),
                ),
                _EventIdFooter(id: entry.id, tokens: tokens),
                // Bottom safe-area inset is added by the wrapping SafeArea.
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: panel,
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.tokens,
    this.sub,
    this.valueColor,
    this.mono = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? sub;
  final Color? valueColor;
  final bool mono;
  final SearchTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 26,
            child: Icon(icon, size: 16, color: tokens.inkFaint),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: tokens.inkFaint,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  value,
                  style: TextStyle(
                    fontFamily: mono ? AppTheme.fontMono : null,
                    fontSize: mono ? 13 : 13.5,
                    fontWeight: FontWeight.w600,
                    color: valueColor ?? tokens.ink,
                    height: 1.3,
                  ),
                ),
                if (sub != null && sub!.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    sub!,
                    style: TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontSize: 11,
                      color: tokens.inkFaint,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetadataBlock extends StatelessWidget {
  const _MetadataBlock({required this.metadata, required this.tokens});
  final Map<String, String> metadata;
  final SearchTokens tokens;

  String _label(BuildContext context, String key) {
    final translated = context.t('audit.meta.$key');
    if (translated != 'audit.meta.$key') return translated;
    // Humanise an unknown camelCase / snake_case key.
    final spaced = key
        .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
        .replaceAll('_', ' ');
    return spaced.isEmpty
        ? key
        : '${spaced[0].toUpperCase()}${spaced.substring(1)}';
  }

  @override
  Widget build(BuildContext context) {
    final entries = metadata.entries.toList();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t('audit.detail.metadata').toUpperCase(),
            style: TextStyle(
              fontFamily: AppTheme.fontMono,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: tokens.inkFaint,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: tokens.field,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: tokens.hairline),
            ),
            child: Column(
              children: [
                for (int i = 0; i < entries.length; i++) ...[
                  if (i > 0)
                    Divider(height: 1, color: tokens.hairline, thickness: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 4,
                          child: Text(
                            _label(context, entries[i].key),
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: tokens.inkSoft,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 5,
                          child: SelectableText(
                            entries[i].value,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: tokens.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EventIdFooter extends StatelessWidget {
  const _EventIdFooter({required this.id, required this.tokens});
  final String id;
  final SearchTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 10, 0),
      child: Row(
        children: [
          Icon(LucideIcons.hash, size: 13, color: tokens.inkFaint),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              id,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppTheme.fontMono,
                fontSize: 11,
                color: tokens.inkFaint,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: id));
              if (!context.mounted) return;
              showGlassToast(
                context,
                context.t('audit.detail.copied'),
                kind: GlassToastKind.success,
                duration: const Duration(seconds: 2),
              );
            },
            icon: Icon(LucideIcons.copy, size: 14, color: tokens.inkSoft),
            label: Text(
              context.t('audit.detail.copyId'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: tokens.inkSoft,
              ),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Visual mappings ─────────────────────────────

Color _severityColor(AuditSeverity s) => switch (s) {
  AuditSeverity.info => AppColors.stTodo,
  AuditSeverity.notice => AppColors.accent,
  AuditSeverity.warning => AppColors.danger,
  AuditSeverity.unknown => AppColors.inkSoft,
};

IconData _categoryIcon(AuditCategory c) => switch (c) {
  AuditCategory.authentication => LucideIcons.logIn,
  AuditCategory.account => LucideIcons.circleUser,
  AuditCategory.administration => LucideIcons.shieldCheck,
  AuditCategory.configuration => LucideIcons.settings,
  AuditCategory.data => LucideIcons.database,
  AuditCategory.integration => LucideIcons.plug,
  AuditCategory.unknown => LucideIcons.activity,
};

/// Per-action glyph. Falls back to the action's category glyph for any future
/// action not listed here (keeps the UI forward-compatible with new events).
IconData _actionIcon(String action) => switch (action) {
  'LOGIN_SUCCESS' => LucideIcons.logIn,
  'LOGIN_FAILURE' => LucideIcons.circleX,
  'LOGIN_BLOCKED' => LucideIcons.ban,
  'MFA_FAILURE' => LucideIcons.shieldX,
  'SSO_LOGIN' => LucideIcons.fingerprint,
  'SESSION_REVOKED' => LucideIcons.monitorX,
  'PASSWORD_CHANGED' => LucideIcons.keyRound,
  'PASSWORD_RESET_REQUESTED' => LucideIcons.mailQuestion,
  'PASSWORD_RESET_COMPLETED' => LucideIcons.keyRound,
  'EMAIL_CHANGE_REQUESTED' => LucideIcons.mail,
  'EMAIL_CHANGED' => LucideIcons.mailCheck,
  'TWO_FACTOR_ENABLED' => LucideIcons.shieldCheck,
  'TWO_FACTOR_DISABLED' => LucideIcons.shieldOff,
  'RECOVERY_CODES_REGENERATED' => LucideIcons.refreshCw,
  'ACCOUNT_DELETED' => LucideIcons.userX,
  'USER_INVITED' => LucideIcons.userPlus,
  'USER_CREATED' => LucideIcons.userPlus,
  'USER_ROLE_CHANGED' => LucideIcons.userCog,
  'USER_ACTIVATED' => LucideIcons.userCheck,
  'USER_DEACTIVATED' => LucideIcons.userMinus,
  'USER_DELETED' => LucideIcons.userX,
  'USER_PASSWORD_RESET_SENT' => LucideIcons.keyRound,
  'USER_SESSIONS_REVOKED' => LucideIcons.monitorX,
  'SETTINGS_CHANGED' => LucideIcons.sliders,
  'DATA_EXPORT_REQUESTED' => LucideIcons.download,
  _ => LucideIcons.history,
};

/// Human "actor → target" line for the card subtitle. Returns null when there
/// is nothing meaningful to show beyond the action title itself.
String? _actorTargetLine(BuildContext context, AuditEntry entry) {
  final actor = entry.actorLabel?.isNotEmpty == true
      ? entry.actorLabel!
      : context.t('audit.actor.system');
  final target = entry.targetLabel?.isNotEmpty == true
      ? entry.targetLabel!
      : null;
  if (target != null && target != actor) return '$actor → $target';
  return actor;
}
