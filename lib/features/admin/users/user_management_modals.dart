import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/admin_user_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../sprint/modals/glass_modal.dart';
import 'user_management_widgets.dart';

// ════════════════════════════════════════════════════════════════════════
//  Liquid-Glass modals for the User-management board. Each collects input /
//  confirmation and returns its result; the board performs the mutation, toast
//  and reload (so all repo wiring lives in one place).
// ════════════════════════════════════════════════════════════════════════

const _emailRe =
    r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)+$";

typedef InviteResult = ({List<String> emails, AdminRole role, String? message});
typedef EditResult = ({String name, String title, String? email});

/// Header for a glass modal with a configurable icon tint (amber default,
/// danger for destructive flows).
class _Header extends StatelessWidget {
  const _Header({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final bg = danger ? AppColors.dangerSoft : AppColors.accentSoft;
    final fg = danger ? AppColors.danger : AppColors.accentStrong;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: fg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontBrand,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(LucideIcons.x, size: 20, color: AppColors.inkSoft),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.confirmLabel,
    required this.onConfirm,
    this.confirmIcon = LucideIcons.check,
    this.danger = false,
  });

  final String confirmLabel;
  final VoidCallback? onConfirm;
  final IconData confirmIcon;
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
      child: Row(
        children: [
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: Text(context.t('common.cancel')),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: onConfirm,
            style: FilledButton.styleFrom(
              backgroundColor: danger ? AppColors.danger : AppColors.navy,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              ),
            ),
            icon: Icon(confirmIcon, size: 15),
            label: Text(confirmLabel),
          ),
        ],
      ),
    );
  }
}

Widget _scaffold({
  required Widget header,
  required Widget body,
  required Widget footer,
}) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      header,
      Flexible(child: SingleChildScrollView(child: body)),
      footer,
    ],
  );
}

/// Compact affected-users preview used by the confirm modals.
Widget _previewList(BuildContext context, List<AdminUser> users) {
  return Column(
    children: [
      for (final u in users.take(6))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              UserAvatar(name: u.name, imageUrl: u.avatarUrl, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      u.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      u.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      if (users.length > 6)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              context.t(
                'admin.um.andMore',
                variables: {'n': '${users.length - 6}'},
              ),
              style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
            ),
          ),
        ),
    ],
  );
}

// ─────────────────────────── Generic confirm ─────────────────────────────

Future<bool> _confirm(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String subtitle,
  required Widget body,
  required String confirmLabel,
  IconData confirmIcon = LucideIcons.check,
  bool danger = false,
}) async {
  final result = await showGlassModal<bool>(
    context,
    adaptive: false,
    width: 480,
    // Use the dialog's own context to pop — the screen context lives under
    // go_router's nested navigator, so popping with it would dismiss the page
    // instead of this dialog (which is on the root navigator).
    builder: (dialogContext) => _scaffold(
      header: _Header(
        icon: icon,
        title: title,
        subtitle: subtitle,
        danger: danger,
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 16),
        child: body,
      ),
      footer: _Footer(
        confirmLabel: confirmLabel,
        confirmIcon: confirmIcon,
        danger: danger,
        onConfirm: () => Navigator.of(dialogContext).pop(true),
      ),
    ),
  );
  return result ?? false;
}

Future<bool> showResendModal(BuildContext context, List<AdminUser> users) {
  final expired = users.where((u) => u.inviteExpired).length;
  return _confirm(
    context,
    icon: LucideIcons.send,
    title: context.t('admin.um.resendInvitation'),
    subtitle: users.length == 1
        ? context.t('admin.um.resendSubOne')
        : context.t(
            'admin.um.resendSubMany',
            variables: {'n': '${users.length}'},
          ),
    confirmLabel: context.t('admin.um.resend'),
    confirmIcon: LucideIcons.send,
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (expired > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              context.t(
                'admin.um.resendExpiredNote',
                variables: {'n': '$expired'},
              ),
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.danger,
                height: 1.4,
              ),
            ),
          ),
        _previewList(context, users),
      ],
    ),
  );
}

Future<bool> showDeactivateModal(BuildContext context, List<AdminUser> users) {
  final sessions = users.fold<int>(0, (a, u) => a + u.sessions);
  return _confirm(
    context,
    icon: LucideIcons.ban,
    danger: true,
    title: context.t('admin.um.deactivateAccount'),
    subtitle: context.t('admin.um.deactivateSub'),
    confirmLabel: context.t('admin.um.deactivate'),
    confirmIcon: LucideIcons.ban,
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.t('admin.um.deactivateWarn', variables: {'n': '$sessions'}),
          style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.ink),
        ),
        const SizedBox(height: 12),
        _previewList(context, users),
      ],
    ),
  );
}

Future<bool> showRevokeAdminModal(BuildContext context, List<AdminUser> users) {
  return _confirm(
    context,
    icon: LucideIcons.shieldMinus,
    title: context.t('admin.um.revokeAdmin'),
    subtitle: context.t('admin.um.revokeAdminSub'),
    confirmLabel: context.t('admin.um.revokeAdmin'),
    confirmIcon: LucideIcons.shieldMinus,
    body: _previewList(context, users),
  );
}

Future<bool> showResetModal(BuildContext context, List<AdminUser> users) {
  return _confirm(
    context,
    icon: LucideIcons.keyRound,
    title: context.t('admin.um.sendPasswordReset'),
    subtitle: users.length == 1
        ? context.t('admin.um.resetSubOne')
        : context.t(
            'admin.um.resetSubMany',
            variables: {'n': '${users.length}'},
          ),
    confirmLabel: context.t('admin.um.sendReset'),
    confirmIcon: LucideIcons.send,
    body: _previewList(context, users),
  );
}

// ─────────────────────────── Delete (type DELETE) ────────────────────────

Future<bool> showDeleteModal(
  BuildContext context,
  List<AdminUser> users,
) async {
  final requireTyping =
      users.length > 1 || users.any((u) => u.role == AdminRole.admin);
  final result = await showGlassModal<bool>(
    context,
    width: 480,
    builder: (_) => _DeleteModal(users: users, requireTyping: requireTyping),
  );
  return result ?? false;
}

class _DeleteModal extends StatefulWidget {
  const _DeleteModal({required this.users, required this.requireTyping});
  final List<AdminUser> users;
  final bool requireTyping;

  @override
  State<_DeleteModal> createState() => _DeleteModalState();
}

class _DeleteModalState extends State<_DeleteModal> {
  final _controller = TextEditingController();
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    _ok = !widget.requireTyping;
    _controller.addListener(() {
      final match = _controller.text.trim() == 'DELETE';
      if (match != _ok) setState(() => _ok = match);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.users.length;
    return _scaffold(
      header: _Header(
        icon: LucideIcons.trash2,
        danger: true,
        title: n == 1
            ? context.t('admin.um.deleteUser')
            : context.t('admin.um.deleteUsers', variables: {'n': '$n'}),
        subtitle: context.t('admin.um.deleteSub'),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.t('admin.um.deleteWarn'),
              style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.ink),
            ),
            const SizedBox(height: 12),
            _previewList(context, widget.users),
            if (widget.requireTyping) ...[
              const SizedBox(height: 14),
              Text(
                context.t('admin.um.deleteTypeHint'),
                style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _controller,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: glassInputDecoration(hint: 'DELETE'),
              ),
            ],
          ],
        ),
      ),
      footer: _Footer(
        confirmLabel: context.t('admin.um.delete'),
        confirmIcon: LucideIcons.trash2,
        danger: true,
        onConfirm: _ok ? () => Navigator.of(context).pop(true) : null,
      ),
    );
  }
}

// ─────────────────────────── Invite ──────────────────────────────────────

Future<InviteResult?> showInviteModal(BuildContext context) {
  return showGlassModal<InviteResult>(
    context,
    width: 520,
    builder: (_) => const _InviteModal(),
  );
}

class _InviteModal extends StatefulWidget {
  const _InviteModal();

  @override
  State<_InviteModal> createState() => _InviteModalState();
}

class _InviteModalState extends State<_InviteModal> {
  final _controller = TextEditingController();
  final _message = TextEditingController();
  final _focus = FocusNode();
  final List<String> _emails = [];
  AdminRole _role = AdminRole.user;

  static final _re = RegExp(_emailRe);

  @override
  void dispose() {
    _controller.dispose();
    _message.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit(String raw) {
    final parts = raw.split(RegExp(r'[\s,;]+'));
    var added = false;
    for (final p in parts) {
      final e = p.trim().toLowerCase();
      if (e.isEmpty) continue;
      if (!_emails.contains(e)) {
        _emails.add(e);
        added = true;
      }
    }
    if (added) setState(() {});
  }

  void _onChanged(String value) {
    if (value.isNotEmpty && RegExp(r'[\s,;]$').hasMatch(value)) {
      _commit(value);
      _controller.clear();
    }
    // Rebuild so the footer's enabled-state tracks what's typed live (even
    // before the address is committed to a chip).
    setState(() {});
  }

  /// The committed chips plus any still-typed address in the field, so a valid
  /// email that the user simply hasn't separated yet still counts.
  List<String> get _effectiveEmails {
    final pending = _controller.text.trim().toLowerCase();
    if (pending.isEmpty || _emails.contains(pending)) return _emails;
    return [..._emails, pending];
  }

  bool get _valid =>
      _effectiveEmails.isNotEmpty &&
      _effectiveEmails.every((e) => _re.hasMatch(e));

  /// Commits whatever is still in the field, then returns the final list.
  List<String> _finalize() {
    _commit(_controller.text);
    _controller.clear();
    return List<String>.from(_emails);
  }

  @override
  Widget build(BuildContext context) {
    return _scaffold(
      header: _Header(
        icon: LucideIcons.userPlus,
        title: context.t('admin.um.inviteUsers'),
        subtitle: context.t('admin.um.inviteSub'),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GlassField(
              label: context.t('admin.um.inviteEmails'),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final e in _emails) _chip(e),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 160),
                      child: IntrinsicWidth(
                        child: TextField(
                          controller: _controller,
                          focusNode: _focus,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          onChanged: _onChanged,
                          onSubmitted: (v) {
                            _commit(v);
                            _controller.clear();
                            _focus.requestFocus();
                          },
                          decoration: InputDecoration(
                            isDense: true,
                            errorBorder: InputBorder.none,
                            focusedErrorBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            border: InputBorder.none,
                            filled: false,
                            hintText: context.t('admin.um.inviteEmailsHint'),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            GlassField(
              label: context.t('admin.um.role'),
              child: GlassSegmented(
                labels: [
                  context.t('admin.um.roleUser'),
                  context.t('admin.um.roleAdmin'),
                ],
                selected: _role == AdminRole.admin ? 1 : 0,
                onChanged: (i) => setState(
                  () => _role = i == 1 ? AdminRole.admin : AdminRole.user,
                ),
              ),
            ),
            const SizedBox(height: 16),
            GlassField(
              label: context.t('admin.um.inviteMessage'),
              child: TextField(
                controller: _message,
                maxLines: 3,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.newline,
                decoration: glassInputDecoration(
                  hint: context.t('admin.um.inviteMessageHint'),
                ),
              ),
            ),
          ],
        ),
      ),
      footer: _Footer(
        confirmLabel: context.t('admin.um.sendInvites'),
        confirmIcon: LucideIcons.send,
        onConfirm: _valid
            ? () => Navigator.of(context).pop((
                emails: _finalize(),
                role: _role,
                message: _message.text.trim().isEmpty
                    ? null
                    : _message.text.trim(),
              ))
            : null,
      ),
    );
  }

  Widget _chip(String email) {
    final invalid = !_re.hasMatch(email);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
      decoration: BoxDecoration(
        color: invalid ? AppColors.dangerSoft : AppColors.canvas2,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(
          color: invalid
              ? AppColors.danger.withValues(alpha: 0.4)
              : AppColors.hairline,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (invalid) ...[
            const Icon(
              LucideIcons.mailWarning,
              size: 13,
              color: AppColors.danger,
            ),
            const SizedBox(width: 4),
          ],
          Text(
            email,
            style: TextStyle(
              fontSize: 12.5,
              color: invalid ? AppColors.danger : AppColors.ink,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => setState(() => _emails.remove(email)),
            child: Icon(LucideIcons.x, size: 13, color: AppColors.inkFaint),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Edit details ────────────────────────────────

Future<EditResult?> showEditModal(BuildContext context, AdminUser user) {
  return showGlassModal<EditResult>(
    context,
    width: 480,
    builder: (_) => _EditModal(user: user),
  );
}

class _EditModal extends StatefulWidget {
  const _EditModal({required this.user});
  final AdminUser user;

  @override
  State<_EditModal> createState() => _EditModalState();
}

class _EditModalState extends State<_EditModal> {
  late final TextEditingController _name = TextEditingController(
    text: widget.user.name,
  );
  late final TextEditingController _title = TextEditingController(
    text: widget.user.title,
  );
  late final TextEditingController _email = TextEditingController(
    text: widget.user.email,
  );

  @override
  void dispose() {
    _name.dispose();
    _title.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sso = widget.user.sso;
    return _scaffold(
      header: _Header(
        icon: LucideIcons.pencil,
        title: context.t('admin.um.editDetails'),
        subtitle: widget.user.name,
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 16),
        child: Column(
          children: [
            GlassField(
              label: context.t('admin.um.fieldName'),
              child: TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: glassInputDecoration(),
              ),
            ),
            const SizedBox(height: 14),
            GlassField(
              label: context.t('admin.um.fieldTitle'),
              child: TextField(
                controller: _title,
                textInputAction: TextInputAction.next,
                decoration: glassInputDecoration(),
              ),
            ),
            const SizedBox(height: 14),
            GlassField(
              label: context.t('admin.um.fieldEmail'),
              trailing: sso
                  ? Icon(LucideIcons.lock, size: 12, color: AppColors.inkFaint)
                  : null,
              child: TextField(
                controller: _email,
                enabled: !sso,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                textInputAction: TextInputAction.done,
                decoration: glassInputDecoration(
                  hint: sso ? context.t('admin.um.emailLockedHint') : null,
                ),
              ),
            ),
          ],
        ),
      ),
      footer: _Footer(
        confirmLabel: context.t('common.save'),
        onConfirm: () => Navigator.of(context).pop((
          name: _name.text.trim(),
          title: _title.text.trim(),
          email: sso ? null : _email.text.trim(),
        )),
      ),
    );
  }
}
