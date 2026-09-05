import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassContainer, GlassQuality, LiquidRoundedSuperellipse;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/admin_user_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_bulk_bar.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/glass_popup_menu.dart';
import '../../../core/widgets/hive_widgets.dart';
import '../../../core/widgets/user_pronouns.dart';
import '../../search/search_tokens.dart';
import '../../sprint/modals/glass_modal.dart' show showGlassBottomSheet;

part 'user_management_widgets.drawer.dart';

// ════════════════════════════════════════════════════════════════════════
//  Shared presentation for the admin User-management board: avatars, badges,
//  KPI cards, the row action menu, the bulk bar and the detail drawer. Colour
//  recipes mirror the design's oklch tokens (role hue 70/250, status 155/20/45,
//  origin 200/300/250/155), approximated with HSL.
// ════════════════════════════════════════════════════════════════════════

/// Deterministic saturated avatar colour from a name (stable per user).
Color userColor(String name) {
  var s = 0;
  for (final unit in name.codeUnits) {
    s = (s * 31 + unit) % 360;
  }
  const hues = <double>[248, 70, 250, 300, 155, 200, 20, 320];
  return HSLColor.fromAHSL(1, hues[s % hues.length], 0.45, 0.52).toColor();
}

Color _hue(double h, {double s = 0.5, double l = 0.5}) =>
    HSLColor.fromAHSL(1, h, s, l).toColor();

/// (background, ink) for a role badge.
(Color, Color) roleColors(AdminRole role) => role == AdminRole.admin
    ? (AppColors.accentSoft, AppColors.accentStrong)
    : (_hue(250, s: .4, l: .93), _hue(250, s: .45, l: .45));

/// (background, ink) for a status badge.
(Color, Color) statusColors(UserStatus status) => switch (status) {
  UserStatus.active => (_hue(155, s: .4, l: .92), _hue(155, s: .45, l: .38)),
  UserStatus.disabled => (_hue(20, s: .5, l: .93), _hue(20, s: .5, l: .47)),
  UserStatus.invited => (_hue(45, s: .6, l: .92), _hue(45, s: .55, l: .42)),
  UserStatus.pendingApproval => (
    _hue(265, s: .5, l: .93),
    _hue(265, s: .5, l: .5),
  ),
};

Color originColor(UserOrigin origin) => switch (origin) {
  UserOrigin.local => _hue(200, s: .45, l: .5),
  UserOrigin.oidc => _hue(300, s: .45, l: .55),
  UserOrigin.saml => _hue(250, s: .45, l: .55),
  UserOrigin.ldap => _hue(155, s: .45, l: .45),
};

IconData roleIcon(AdminRole role) =>
    role == AdminRole.admin ? LucideIcons.shieldCheck : LucideIcons.user;

IconData statusIcon(UserStatus status) => switch (status) {
  UserStatus.active => LucideIcons.circleCheck,
  UserStatus.disabled => LucideIcons.ban,
  UserStatus.invited => LucideIcons.mail,
  UserStatus.pendingApproval => LucideIcons.clock,
};

String roleLabel(BuildContext c, AdminRole r) =>
    c.t(r == AdminRole.admin ? 'admin.um.roleAdmin' : 'admin.um.roleUser');

String statusLabel(BuildContext c, UserStatus s) => c.t(switch (s) {
  UserStatus.active => 'admin.um.statusActive',
  UserStatus.disabled => 'admin.um.statusDisabled',
  UserStatus.invited => 'admin.um.statusInvited',
  UserStatus.pendingApproval => 'admin.um.statusPending',
});

String originLabel(BuildContext c, UserOrigin o) => switch (o) {
  // "Local" is an ordinary word (→ "Lokal"); the rest are protocol acronyms.
  UserOrigin.local => c.t('admin.um.originLocal'),
  UserOrigin.oidc => 'OIDC',
  UserOrigin.saml => 'SAML',
  UserOrigin.ldap => 'LDAP',
};

/// Relative "last active" text, localized.
String umRelTime(BuildContext c, DateTime? t) {
  if (t == null) return c.t('admin.um.never');
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return c.t('admin.um.justNow');
  if (d.inMinutes < 60) {
    return c.t('admin.um.minutesAgo', variables: {'n': '${d.inMinutes}'});
  }
  if (d.inHours < 24) {
    return c.t('admin.um.hoursAgo', variables: {'n': '${d.inHours}'});
  }
  if (d.inDays < 30) {
    return c.t('admin.um.daysAgo', variables: {'n': '${d.inDays}'});
  }
  return umPrettyDate(c, t);
}

/// Locale-aware medium date (e.g. "Jul 19, 2026" / "19. Juli 2026"), instead of
/// a hardcoded US-English pattern.
String umPrettyDate(BuildContext c, DateTime? t) => t == null
    ? '—'
    : DateFormat.yMMMd(Localizations.localeOf(c).languageCode).format(t);

/// A user is "idle" when last active over two weeks ago — greys the cell.
bool isIdle(DateTime? t) =>
    t != null && DateTime.now().difference(t).inDays > 14;

// ─────────────────────────── Avatar ──────────────────────────────────────

class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.size = 36,
    this.pronouns,
  });

  final String name;
  final String? imageUrl;
  final double size;
  final String? pronouns;

  @override
  Widget build(BuildContext context) {
    // Delegate to HiveAvatar so the profile picture (authenticated /avatar URL)
    // loads with a clean initials fallback; keep the admin board's user colour.
    return HiveAvatar(
      name: name,
      imageUrl: imageUrl,
      size: size,
      pronouns: pronouns,
      background: userColor(name),
    );
  }
}

// ─────────────────────────── Badges ──────────────────────────────────────

class _Badge extends StatelessWidget {
  const _Badge({
    required this.icon,
    required this.label,
    required this.bg,
    required this.fg,
  });

  final IconData icon;
  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
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

class RoleBadge extends StatelessWidget {
  const RoleBadge(this.role, {super.key});
  final AdminRole role;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = roleColors(role);
    return _Badge(
      icon: roleIcon(role),
      label: roleLabel(context, role),
      bg: bg,
      fg: fg,
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.user, {super.key});
  final AdminUser user;

  @override
  Widget build(BuildContext context) {
    if (user.inviteExpired) {
      return _Badge(
        icon: LucideIcons.mailWarning,
        label: context.t('admin.um.statusExpired'),
        bg: AppColors.dangerSoft,
        fg: AppColors.danger,
      );
    }
    final (bg, fg) = statusColors(user.status);
    return _Badge(
      icon: statusIcon(user.status),
      label: statusLabel(context, user.status),
      bg: bg,
      fg: fg,
    );
  }
}

class OriginTag extends StatelessWidget {
  const OriginTag(this.origin, {super.key});
  final UserOrigin origin;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: originColor(origin),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          originLabel(context, origin),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.inkSoft,
          ),
        ),
        if (origin.isSso) ...[
          const SizedBox(width: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.canvas2,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'SSO',
              style: TextStyle(
                fontFamily: AppTheme.fontMono,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: AppColors.inkFaint,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────── KPI card ────────────────────────────────────

class UmKpiCard extends StatelessWidget {
  const UmKpiCard({
    super.key,
    required this.icon,
    required this.iconBg,
    required this.iconFg,
    required this.value,
    required this.label,
    required this.active,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconFg;
  final String value;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: active ? AppColors.accentSoft : AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          border: Border.all(
            color: active ? AppColors.accentLine : AppColors.hairline,
            width: active ? 1.4 : 1,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.18),
                    blurRadius: 14,
                    spreadRadius: -4,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 20, color: iconFg),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontFamily: AppTheme.fontBrand,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: 1),
                  DefaultTextStyle(
                    style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
                    child: trailing == null
                        ? Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        : Row(
                            children: [
                              Flexible(
                                child: Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              trailing!,
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── Action bundle ───────────────────────────────

/// Callback bundle the board hands to the row menu / drawer. Direct actions
/// mutate immediately; `open*` actions raise a confirmation modal first.
class UserActions {
  const UserActions({
    required this.openDrawer,
    required this.openEdit,
    required this.activate,
    required this.approve,
    required this.openDeactivate,
    required this.setRole,
    required this.openDemote,
    required this.openResend,
    required this.openReset,
    required this.revokeSessions,
    required this.openDelete,
    required this.isLastActiveAdmin,
    required this.nameById,
    required this.currentUserId,
  });

  final void Function(AdminUser u) openDrawer;
  final void Function(AdminUser u) openEdit;
  final void Function(List<String> ids) activate;
  final void Function(List<String> ids) approve;
  final void Function(List<String> ids) openDeactivate;
  final void Function(List<String> ids, AdminRole role) setRole;
  final void Function(List<String> ids) openDemote;
  final void Function(List<String> ids) openResend;
  final void Function(List<String> ids) openReset;
  final void Function(List<String> ids) revokeSessions;
  final void Function(List<String> ids) openDelete;
  final bool Function(AdminUser u) isLastActiveAdmin;
  final String? Function(String? id) nameById;
  final String? currentUserId;
}

// ─────────────────────────── Row action menu ─────────────────────────────

class UserRowMenu extends StatelessWidget {
  const UserRowMenu({
    super.key,
    required this.user,
    required this.actions,
    required this.child,
  });

  final AdminUser user;
  final UserActions actions;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final u = user;
    final lastAdmin = actions.isLastActiveAdmin(u);
    final items = <GlassMenuItem<String>>[
      GlassMenuItem(
        value: 'view',
        label: context.t('admin.um.viewProfile'),
        leading: const Icon(LucideIcons.panelRightOpen, size: 16),
      ),
      GlassMenuItem(
        value: 'edit',
        label: context.t('admin.um.editDetails'),
        leading: const Icon(LucideIcons.pencil, size: 16),
      ),
      if (u.status == UserStatus.invited)
        GlassMenuItem(
          value: 'resend',
          label: context.t('admin.um.resendInvite'),
          color: u.inviteExpired ? AppColors.accentStrong : null,
          dividerAbove: true,
          leading: Icon(
            u.inviteExpired ? LucideIcons.send : LucideIcons.rotateCw,
            size: 16,
          ),
        )
      else if (u.status == UserStatus.active)
        GlassMenuItem(
          value: 'deactivate',
          label: context.t('admin.um.deactivate'),
          dividerAbove: true,
          leading: const Icon(LucideIcons.ban, size: 16),
        )
      else if (u.status == UserStatus.pendingApproval)
        GlassMenuItem(
          value: 'approve',
          label: context.t('admin.um.approve'),
          color: AppColors.success,
          dividerAbove: true,
          leading: const Icon(
            LucideIcons.userCheck,
            size: 16,
            color: AppColors.success,
          ),
        )
      else
        GlassMenuItem(
          value: 'activate',
          label: context.t('admin.um.activate'),
          color: AppColors.success,
          dividerAbove: true,
          leading: const Icon(
            LucideIcons.circleCheck,
            size: 16,
            color: AppColors.success,
          ),
        ),
      if (u.role == AdminRole.admin)
        GlassMenuItem(
          value: 'demote',
          label: context.t('admin.um.revokeAdmin'),
          enabled: !lastAdmin,
          disabledReason: context.t('admin.um.reasonLastAdmin'),
          leading: const Icon(LucideIcons.shieldMinus, size: 16),
        )
      else
        GlassMenuItem(
          value: 'promote',
          label: context.t('admin.um.makeAdmin'),
          enabled: u.status != UserStatus.invited,
          disabledReason: context.t('admin.um.reasonPendingInvite'),
          leading: const Icon(LucideIcons.shieldCheck, size: 16),
        ),
      if (u.status != UserStatus.invited) ...[
        GlassMenuItem(
          value: 'reset',
          label: context.t(
            u.sso ? 'admin.um.resetViaIdp' : 'admin.um.sendPasswordReset',
          ),
          enabled: !u.sso,
          disabledReason: context.t('admin.um.reasonSsoManaged'),
          dividerAbove: true,
          leading: const Icon(LucideIcons.keyRound, size: 16),
        ),
        GlassMenuItem(
          value: 'revoke',
          label: context.t('admin.um.revokeSessions'),
          enabled: u.sessions > 0,
          disabledReason: context.t('admin.um.reasonNoSessions'),
          leading: const Icon(LucideIcons.logOut, size: 16),
        ),
      ],
      GlassMenuItem(
        value: 'delete',
        label: context.t('admin.um.deleteUser'),
        color: AppColors.danger,
        enabled: !lastAdmin,
        disabledReason: context.t('admin.um.reasonLastAdmin'),
        dividerAbove: true,
        leading: const Icon(
          LucideIcons.trash2,
          size: 16,
          color: AppColors.danger,
        ),
      ),
    ];

    return GlassPopupMenu<String>(
      value: '',
      width: 240,
      onSelected: (action) => _dispatch(action),
      items: items,
      child: child,
    );
  }

  void _dispatch(String action) {
    final ids = [user.id];
    switch (action) {
      case 'view':
        actions.openDrawer(user);
      case 'edit':
        actions.openEdit(user);
      case 'resend':
        actions.openResend(ids);
      case 'deactivate':
        actions.openDeactivate(ids);
      case 'activate':
        actions.activate(ids);
      case 'approve':
        actions.approve(ids);
      case 'promote':
        actions.setRole(ids, AdminRole.admin);
      case 'demote':
        actions.setRole(ids, AdminRole.user);
      case 'reset':
        actions.openReset(ids);
      case 'revoke':
        actions.revokeSessions(ids);
      case 'delete':
        actions.openDelete(ids);
    }
  }
}

// ─────────────────────────── Bulk action bar ─────────────────────────────

class BulkActionBar extends StatelessWidget {
  const BulkActionBar({
    super.key,
    required this.selected,
    required this.actions,
    required this.onClear,
  });

  final List<AdminUser> selected;
  final UserActions actions;
  final VoidCallback onClear;

  List<String> _ids(bool Function(AdminUser) test) =>
      selected.where(test).map((u) => u.id).toList();

  @override
  Widget build(BuildContext context) {
    final invited = _ids((u) => u.status == UserStatus.invited);
    final disabled = _ids((u) => u.status == UserStatus.disabled);
    final active = _ids((u) => u.status == UserStatus.active);
    final pending = _ids((u) => u.status == UserStatus.pendingApproval);
    final nonAdmin = _ids(
      (u) => u.role != AdminRole.admin && u.status != UserStatus.invited,
    );
    final admins = _ids((u) => u.role == AdminRole.admin);

    return GlassBulkBar(
      countLabel: context.t(
        'admin.um.selectedCount',
        variables: {'n': '${selected.length}'},
      ),
      onClear: onClear,
      clearTooltip: context.t('admin.um.clearSelection'),
      actions: [
        if (invited.isNotEmpty)
          GlassBulkAction(
            icon: LucideIcons.send,
            label: context.t('admin.um.resend'),
            onTap: () => actions.openResend(invited),
          ),
        if (pending.isNotEmpty)
          GlassBulkAction(
            icon: LucideIcons.userCheck,
            label: context.t('admin.um.approve'),
            onTap: () => actions.approve(pending),
          ),
        if (disabled.isNotEmpty)
          GlassBulkAction(
            icon: LucideIcons.circleCheck,
            label: context.t('admin.um.activate'),
            onTap: () => actions.activate(disabled),
          ),
        if (active.isNotEmpty)
          GlassBulkAction(
            icon: LucideIcons.ban,
            label: context.t('admin.um.deactivate'),
            onTap: () => actions.openDeactivate(active),
          ),
        if (nonAdmin.isNotEmpty)
          GlassBulkAction(
            icon: LucideIcons.shieldCheck,
            label: context.t('admin.um.makeAdmin'),
            onTap: () => actions.setRole(nonAdmin, AdminRole.admin),
          ),
        if (admins.isNotEmpty)
          GlassBulkAction(
            icon: LucideIcons.shieldMinus,
            label: context.t('admin.um.revokeAdmin'),
            onTap: () => actions.openDemote(admins),
          ),
        GlassBulkAction(
          icon: LucideIcons.trash2,
          label: context.t('admin.um.delete'),
          danger: true,
          onTap: () => actions.openDelete(selected.map((u) => u.id).toList()),
        ),
      ],
    );
  }
}
