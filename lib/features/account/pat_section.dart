import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/repositories/account_repository.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/personal_access_token.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import '../git/widgets/copy_field.dart';
import '../sprint/modals/glass_modal.dart'
    show
        showGlassModal,
        GlassField,
        GlassModalHeader,
        GlassModalFooter,
        GlassSegmented,
        glassInputDecoration,
        showGlassToast,
        GlassToastKind;
import 'account_modals.dart' show showConfirm;
import 'account_widgets.dart';

/// The account "Access tokens" section — lists the caller's Personal Access
/// Tokens (used to authenticate against the embedded MCP server), and mints new
/// ones through a glass sheet with a one-time plaintext reveal.
///
/// Gated behind the `mcp` feature flag by [AccountScreen]; this widget assumes
/// it is only shown when the flag is on.
class PatSection extends StatefulWidget {
  const PatSection({super.key});

  @override
  State<PatSection> createState() => _PatSectionState();
}

class _PatSectionState extends State<PatSection> {
  AccountRepository get _repo => context.read<AccountRepository>();

  List<PersonalAccessToken>? _tokens;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final tokens = await _repo.listPats();
      if (mounted) {
        setState(() {
          _tokens = tokens;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _tokens = const [];
          _loading = false;
        });
      }
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    showGlassToast(context, context.t(message), kind: GlassToastKind.success);
  }

  Future<void> _create() async {
    final created = await showCreatePat(context, _repo);
    if (created == null || !mounted) return;
    await showPatReveal(context, created);
    if (mounted) _load();
  }

  Future<void> _revoke(PersonalAccessToken token) async {
    final toast = context.t('pat.revokedToast');
    final ok = await showConfirm(
      context,
      icon: LucideIcons.trash2,
      title: context.t('pat.revoke.title'),
      message: context.t('pat.revoke.message', variables: {'name': token.name}),
      confirmLabel: context.t('pat.revoke.confirm'),
      danger: true,
      onConfirm: () => _repo.revokePat(token.id),
    );
    if (ok == true) {
      _toast(toast);
      _load();
    }
  }

  Future<void> _delete(PersonalAccessToken token) async {
    final toast = context.t('pat.deletedToast');
    final ok = await showConfirm(
      context,
      icon: LucideIcons.trash2,
      title: context.t('pat.delete.title'),
      message: context.t('pat.delete.message', variables: {'name': token.name}),
      confirmLabel: context.t('pat.delete.confirm'),
      danger: true,
      onConfirm: () => _repo.deletePat(token.id),
    );
    if (ok == true) {
      _toast(toast);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = _tokens;
    return AccountSection(
      icon: LucideIcons.keyRound,
      title: context.t('account.tokens.title'),
      subtitle: context.t('account.tokens.subtitle'),
      trailing: AccountActionButton(
        label: context.t('pat.createButton'),
        icon: LucideIcons.plus,
        onPressed: _create,
      ),
      children: [
        if (_loading && tokens == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(child: HiveLoader()),
          )
        else if (tokens == null || tokens.isEmpty)
          HiveEmptyState(
            card: false,
            title: context.t('pat.empty.title'),
            message: context.t('pat.empty.message'),
          )
        else
          for (var i = 0; i < tokens.length; i++) ...[
            if (i > 0) Divider(height: 1, color: AppColors.hairline2),
            _PatRow(
              token: tokens[i],
              onRevoke: () => _revoke(tokens[i]),
              onDelete: () => _delete(tokens[i]),
            ),
          ],
      ],
    );
  }
}

/// One token row: name + status pill, mono prefix, scope chips and a meta line
/// (created / last used / expiry), with a revoke action.
class _PatRow extends StatelessWidget {
  const _PatRow({
    required this.token,
    required this.onRevoke,
    required this.onDelete,
  });

  final PersonalAccessToken token;
  final VoidCallback onRevoke;
  final VoidCallback onDelete;

  String _date(BuildContext context, DateTime date) =>
      MaterialLocalizations.of(context).formatShortDate(date);

  @override
  Widget build(BuildContext context) {
    final inactive = token.revoked || token.isExpired;
    final meta = <String>[
      if (token.createdAt != null)
        context.t(
          'pat.createdOn',
          variables: {'date': _date(context, token.createdAt!)},
        ),
      token.lastUsedAt != null
          ? context.t(
              'pat.lastUsedOn',
              variables: {'date': _date(context, token.lastUsedAt!)},
            )
          : context.t('pat.neverUsed'),
      token.expiresAt != null
          ? context.t(
              'pat.expiresOn',
              variables: {'date': _date(context, token.expiresAt!)},
            )
          : context.t('pat.noExpiry'),
    ].join('  ·  ');

    return Opacity(
      opacity: inactive ? 0.6 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          token.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (token.revoked)
                        AccountPill(
                          label: context.t('pat.statusRevoked'),
                          color: AppColors.danger,
                        )
                      else if (token.isExpired)
                        AccountPill(
                          label: context.t('pat.statusExpired'),
                          color: AppColors.warning,
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    token.prefix,
                    style: TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontSize: 12,
                      color: AppColors.inkSoft,
                    ),
                  ),
                  if (token.scopes.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final scope in token.scopes)
                          _ScopeChip(scope: scope),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    meta,
                    style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
                    softWrap: true,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (token.revoked)
              IconButton(
                tooltip: context.t('pat.delete.confirm'),
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  LucideIcons.trash2,
                  size: 17,
                  color: AppColors.danger,
                ),
                onPressed: onDelete,
              )
            else
              IconButton(
                tooltip: context.t('pat.revoke.confirm'),
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  LucideIcons.trash2,
                  size: 17,
                  color: AppColors.danger,
                ),
                onPressed: onRevoke,
              ),
          ],
        ),
      ),
    );
  }
}

/// A read-only mono scope chip (friendly label from i18n, falling back to the
/// raw scope id when unmapped).
class _ScopeChip extends StatelessWidget {
  const _ScopeChip({required this.scope});

  final String scope;

  @override
  Widget build(BuildContext context) {
    final key = patScopeKey(scope);
    final label = context.t(key);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.hairline2),
      ),
      child: Text(
        label == key ? scope : label,
        style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
      ),
    );
  }
}

// ─────────────────────────── Create sheet ────────────────────────────────

/// Opens the "Create token" glass sheet. Resolves to the freshly-minted
/// [CreatedPat] (with its one-time plaintext) or null if dismissed.
Future<CreatedPat?> showCreatePat(
  BuildContext context,
  AccountRepository repo,
) {
  return showGlassModal<CreatedPat>(
    context,
    width: 480,
    builder: (_) => _CreatePatModal(repo: repo),
  );
}

/// Expiry presets (in days); `0` means "never expires" (server treats ttlDays
/// ≤ 0 as no expiry).
const List<int> _kExpiryDays = [30, 90, 365, 0];

class _CreatePatModal extends StatefulWidget {
  const _CreatePatModal({required this.repo});

  final AccountRepository repo;

  @override
  State<_CreatePatModal> createState() => _CreatePatModalState();
}

class _CreatePatModalState extends State<_CreatePatModal> {
  final _name = TextEditingController();
  final _scopes = <String>{};
  int _expiryIndex = 1; // 90 days
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _canSubmit => _name.text.trim().isNotEmpty && _scopes.isNotEmpty;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final created = await widget.repo.createPat(
        name: _name.text.trim(),
        scopes: _scopes.toList(),
        ttlDays: _kExpiryDays[_expiryIndex],
      );
      if (mounted) Navigator.of(context).maybePop(created);
    } on ApiFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: LucideIcons.keyRound,
          title: context.t('pat.create.title'),
          subtitle: context.t('pat.create.subtitle'),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GlassField(
                  label: context.t('pat.create.nameLabel'),
                  child: TextField(
                    controller: _name,
                    autofocus: true,
                    decoration: glassInputDecoration(
                      hint: context.t('pat.create.nameHint'),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(height: 16),
                GlassField(
                  label: context.t('pat.create.scopesLabel'),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final scope in kPatScopes)
                        _SelectableScope(
                          scope: scope,
                          selected: _scopes.contains(scope),
                          onTap: () => setState(() {
                            if (!_scopes.add(scope)) _scopes.remove(scope);
                          }),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                GlassField(
                  label: context.t('pat.create.expiryLabel'),
                  child: GlassSegmented(
                    labels: [
                      context.t('pat.expiry.days', variables: {'count': '30'}),
                      context.t('pat.expiry.days', variables: {'count': '90'}),
                      context.t('pat.expiry.days', variables: {'count': '365'}),
                      context.t('pat.expiry.never'),
                    ],
                    selected: _expiryIndex,
                    onChanged: (i) => setState(() => _expiryIndex = i),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  AccountNote(
                    text: _error!,
                    icon: LucideIcons.circleAlert,
                    tone: AccountNoteTone.danger,
                  ),
                ],
              ],
            ),
          ),
        ),
        GlassModalFooter(
          confirmLabel: context.t('pat.create.submit'),
          confirmIcon: LucideIcons.keyRound,
          busy: _busy,
          onConfirm: _canSubmit ? _submit : null,
        ),
      ],
    );
  }
}

/// A tappable scope pill (checkbox-style) used in the create sheet.
class _SelectableScope extends StatelessWidget {
  const _SelectableScope({
    required this.scope,
    required this.selected,
    required this.onTap,
  });

  final String scope;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final key = patScopeKey(scope);
    final label = context.t(key);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentSoft : AppColors.surface,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected ? AppColors.accentStrong : AppColors.hairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? LucideIcons.check : LucideIcons.plus,
              size: 14,
              color: selected ? AppColors.accentStrong : AppColors.inkFaint,
            ),
            const SizedBox(width: 7),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label == key ? scope : label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: selected ? AppColors.accentStrong : AppColors.ink,
                  ),
                ),
                Text(
                  scope,
                  style: TextStyle(
                    fontFamily: AppTheme.fontMono,
                    fontSize: 10.5,
                    color: AppColors.inkFaint,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── One-time reveal ─────────────────────────────

/// Shows the freshly-minted token's plaintext exactly once, with a copy control
/// and a "you won't see this again" warning.
Future<void> showPatReveal(BuildContext context, CreatedPat created) {
  return showGlassModal<void>(
    context,
    width: 480,
    builder: (modalContext) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: LucideIcons.circleCheck,
          title: context.t('pat.created.title'),
          subtitle: context.t('pat.created.subtitle'),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AccountNote(
                  text: context.t('pat.created.warning'),
                  icon: LucideIcons.triangleAlert,
                ),
                const SizedBox(height: 14),
                Text(
                  context.t('pat.created.tokenLabel'),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkSoft,
                  ),
                ),
                const SizedBox(height: 7),
                CopyField(
                  text: created.token,
                  onCopied: () {
                    showGlassToast(
                      context,
                      context.t('pat.copiedToast'),
                      kind: GlassToastKind.success,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: AppColors.hairline.withValues(alpha: 0.6)),
            ),
          ),
          child: Row(
            children: [
              const Spacer(),
              FilledButton.icon(
                onPressed: () => Navigator.of(modalContext).maybePop(),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                  ),
                ),
                icon: const Icon(LucideIcons.check, size: 15),
                label: Text(context.t('pat.created.done')),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
