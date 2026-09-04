import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/repositories/account_repository.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/account_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../sprint/modals/glass_modal.dart'
    show showGlassModal, GlassModalHeader, GlassField, glassInputDecoration;
import 'account_widgets.dart';

/// Edit display name / job title / locale → PATCH /me. Returns the saved [Me].
Future<Me?> showEditProfile(
  BuildContext context,
  AccountRepository repo,
  Me me,
) {
  return showGlassModal<Me>(
    context,
    width: 480,
    builder: (_) => _EditProfileModal(repo: repo, me: me),
  );
}

class _EditProfileModal extends StatefulWidget {
  const _EditProfileModal({required this.repo, required this.me});
  final AccountRepository repo;
  final Me me;

  @override
  State<_EditProfileModal> createState() => _EditProfileModalState();
}

class _EditProfileModalState extends State<_EditProfileModal> {
  late final _name = TextEditingController(text: widget.me.displayName);
  late final _title = TextEditingController(text: widget.me.title ?? '');
  late final _pronouns = TextEditingController(text: widget.me.pronouns ?? '');
  // Read-only username field — a single State-owned controller, not one
  // reconstructed every build (which leaked an undisposed controller per rebuild).
  late final _username = TextEditingController(text: widget.me.username);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _title.dispose();
    _pronouns.dispose();
    _username.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // No locale here: the language lives in Settings → Sprache, which applies
      // it to the UI *and* persists it (and `GET /me` re-syncs the stored locale
      // from Accept-Language on every start-up anyway).
      final saved = await widget.repo.updateMyProfile(
        displayName: _name.text.trim(),
        title: _title.text.trim(),
        pronouns: _pronouns.text.trim(),
      );
      if (mounted) Navigator.of(context).maybePop(saved);
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
          icon: LucideIcons.userPen,
          title: context.t('account.editModal.title'),
          subtitle: context.t('account.editModal.subtitle'),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GlassField(
                  label: context.t('account.editModal.displayName'),
                  child: TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.name],
                    textInputAction: TextInputAction.next,
                    decoration: glassInputDecoration(
                      hint: context.t('account.editModal.nameHint'),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                GlassField(
                  label: context.t('account.editModal.username'),
                  child: TextField(
                    enabled: false,
                    controller: _username,
                    decoration: glassInputDecoration().copyWith(
                      prefixIcon: Icon(
                        LucideIcons.atSign,
                        size: 16,
                        color: AppColors.inkFaint,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                GlassField(
                  label: context.t('account.editModal.jobTitle'),
                  child: TextField(
                    controller: _title,
                    textInputAction: TextInputAction.next,
                    decoration: glassInputDecoration(
                      hint: context.t('account.editModal.jobTitleHint'),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                GlassField(
                  label: context.t('account.editModal.pronouns'),
                  child: TextField(
                    controller: _pronouns,
                    textInputAction: TextInputAction.done,
                    decoration: glassInputDecoration(
                      hint: context.t('account.editModal.pronounsHint'),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  AccountNote(
                    text: _error!,
                    icon: LucideIcons.triangleAlert,
                    tone: AccountNoteTone.danger,
                  ),
                ],
              ],
            ),
          ),
        ),
        _Footer(
          label: context.t('account.editModal.save'),
          icon: LucideIcons.check,
          busy: _busy,
          onConfirm: _save,
        ),
      ],
    );
  }
}

/// Change email → POST /me/email-change (double opt-in). Returns true if sent.
Future<bool?> showChangeEmail(
  BuildContext context,
  AccountRepository repo,
  Me me,
) {
  return showGlassModal<bool>(
    context,
    width: 460,
    builder: (_) => _ChangeEmailModal(repo: repo, me: me),
  );
}

class _ChangeEmailModal extends StatefulWidget {
  const _ChangeEmailModal({required this.repo, required this.me});
  final AccountRepository repo;
  final Me me;

  @override
  State<_ChangeEmailModal> createState() => _ChangeEmailModalState();
}

class _ChangeEmailModalState extends State<_ChangeEmailModal> {
  final _email = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final value = _email.text.trim();
    if (!value.contains('@') || value.length < 5) {
      setState(() => _error = context.t('account.emailModal.invalid'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repo.requestEmailChange(value);
      if (mounted) Navigator.of(context).maybePop(true);
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
          icon: LucideIcons.mail,
          title: context.t('account.emailModal.title'),
          subtitle: context.t('account.emailModal.subtitle'),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlassField(
                label: context.t('account.emailModal.current'),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                    border: Border.all(color: AppColors.hairline2),
                  ),
                  child: Text(
                    widget.me.email,
                    style: TextStyle(color: AppColors.inkSoft),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              GlassField(
                label: context.t('account.emailModal.new'),
                child: TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  autocorrect: false,
                  autofocus: true,
                  decoration: glassInputDecoration(hint: 'new@example.com'),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                AccountNote(
                  text: _error!,
                  icon: LucideIcons.triangleAlert,
                  tone: AccountNoteTone.danger,
                ),
              ],
            ],
          ),
        ),
        _Footer(
          label: context.t('account.emailModal.send'),
          icon: LucideIcons.sendHorizontal,
          busy: _busy,
          onConfirm: _send,
        ),
      ],
    );
  }
}

/// A generic danger / confirm dialog used for sign-out actions & data report.
Future<bool?> showConfirm(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String message,
  required String confirmLabel,
  bool danger = false,
  required Future<void> Function() onConfirm,
}) {
  return showGlassModal<bool>(
    context,
    width: 420,
    builder: (_) => _ConfirmModal(
      icon: icon,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      danger: danger,
      onConfirm: onConfirm,
    ),
  );
}

class _ConfirmModal extends StatefulWidget {
  const _ConfirmModal({
    required this.icon,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.danger,
    required this.onConfirm,
  });

  final IconData icon;
  final String title;
  final String message;
  final String confirmLabel;
  final bool danger;
  final Future<void> Function() onConfirm;

  @override
  State<_ConfirmModal> createState() => _ConfirmModalState();
}

class _ConfirmModalState extends State<_ConfirmModal> {
  bool _busy = false;
  String? _error;

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onConfirm();
      if (mounted) Navigator.of(context).maybePop(true);
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
          icon: widget.icon,
          title: widget.title,
          subtitle: widget.message,
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
            child: AccountNote(
              text: _error!,
              icon: LucideIcons.triangleAlert,
              tone: AccountNoteTone.danger,
            ),
          ),
        _Footer(
          label: widget.confirmLabel,
          icon: widget.danger ? LucideIcons.triangleAlert : LucideIcons.check,
          danger: widget.danger,
          busy: _busy,
          onConfirm: _run,
        ),
      ],
    );
  }
}

/// Result of the avatar action chooser.
enum AvatarAction { change, remove }

/// A small glass chooser for the avatar: change or remove the current photo.
///
/// Teams and projects have a picture too and use the very same affordance, so
/// the four labels are i18n *keys* the caller may override — the defaults are
/// the account's own wording.
Future<AvatarAction?> showAvatarActions(
  BuildContext context, {
  String titleKey = 'account.avatar.title',
  String subtitleKey = 'account.avatar.subtitle',
  String changeKey = 'account.avatar.change',
  String removeKey = 'account.avatar.remove',
}) {
  return showGlassModal<AvatarAction>(
    context,
    width: 380,
    // Use the modal's OWN context for pops: showGlassModal pushes on the root
    // navigator, but the outer `context` resolves to GoRouter's shell navigator
    // — popping that would tear down the whole page (white screen) instead of
    // just closing this dialog.
    builder: (modalContext) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: LucideIcons.image,
          title: context.t(titleKey),
          subtitle: context.t(subtitleKey),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AvatarActionTile(
                icon: LucideIcons.upload,
                label: context.t(changeKey),
                onTap: () =>
                    Navigator.of(modalContext).pop(AvatarAction.change),
              ),
              const SizedBox(height: 8),
              _AvatarActionTile(
                icon: LucideIcons.trash2,
                label: context.t(removeKey),
                danger: true,
                onTap: () =>
                    Navigator.of(modalContext).pop(AvatarAction.remove),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _AvatarActionTile extends StatelessWidget {
  const _AvatarActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final fg = danger ? AppColors.danger : AppColors.ink;
    return Material(
      color: AppColors.surface.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            border: Border.all(
              color: danger
                  ? AppColors.danger.withValues(alpha: 0.35)
                  : AppColors.hairline,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
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

/// Type-DELETE-to-confirm account erasure (Art. 17). Returns true on success.
Future<bool?> showDeleteAccount(BuildContext context, AccountRepository repo) {
  return showGlassModal<bool>(
    context,
    width: 460,
    builder: (_) => _DeleteAccountModal(repo: repo),
  );
}

class _DeleteAccountModal extends StatefulWidget {
  const _DeleteAccountModal({required this.repo});
  final AccountRepository repo;

  @override
  State<_DeleteAccountModal> createState() => _DeleteAccountModalState();
}

class _DeleteAccountModalState extends State<_DeleteAccountModal> {
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _confirm.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  bool get _armed => _confirm.text.trim() == 'DELETE';

  Future<void> _delete() async {
    if (!_armed) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repo.deleteMyAccount();
      if (mounted) Navigator.of(context).maybePop(true);
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
          icon: LucideIcons.trash2,
          title: context.t('account.deleteModal.title'),
          subtitle: context.t('account.deleteModal.subtitle'),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlassField(
                label: context.t('account.deleteModal.confirmLabel'),
                child: TextField(
                  controller: _confirm,
                  autofocus: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z]')),
                  ],
                  textCapitalization: TextCapitalization.characters,
                  decoration: glassInputDecoration(hint: 'DELETE'),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                AccountNote(
                  text: _error!,
                  icon: LucideIcons.triangleAlert,
                  tone: AccountNoteTone.danger,
                ),
              ],
            ],
          ),
        ),
        _Footer(
          label: context.t('account.deleteModal.button'),
          icon: LucideIcons.trash2,
          danger: true,
          busy: _busy,
          onConfirm: _armed ? _delete : null,
        ),
      ],
    );
  }
}

/// Shared modal footer (Cancel + a primary/danger confirm). A null [onConfirm]
/// renders the button disabled (used for the type-to-confirm gate).
class _Footer extends StatelessWidget {
  const _Footer({
    required this.label,
    required this.icon,
    required this.busy,
    required this.onConfirm,
    this.danger = false,
  });

  final String label;
  final IconData icon;
  final bool busy;
  final VoidCallback? onConfirm;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.hairline.withValues(alpha: 0.6)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            const Spacer(),
            TextButton(
              onPressed: busy ? null : () => Navigator.of(context).maybePop(),
              child: Text(context.t('common.cancel')),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: busy ? null : onConfirm,
              style: FilledButton.styleFrom(
                backgroundColor: danger ? AppColors.danger : AppColors.navy,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.hairline,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 13,
                ),
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
                  : Icon(icon, size: 15),
              label: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}
