part of 'user_management_widgets.dart';

// ─────────────────────────── Detail drawer ───────────────────────────────

/// Presents the per-user detail panel: a right-edge slide on wide layouts,
/// a draggable bottom sheet on phones. Returns when dismissed.
Future<void> showUserDrawer(
  BuildContext context, {
  required AdminUser user,
  required UserActions actions,
  required bool phone,
}) {
  if (phone) {
    // The glass bottom-sheet helper pushes onto the root navigator so the sheet
    // floats *above* the shell's liquid-glass bottom nav. On the nested
    // go_router navigator it would render inside the content layer, beneath the
    // floating nav — which then paints over the sheet's lower actions (the
    // Danger-zone delete button).
    return showGlassBottomSheet<void>(
      context,
      builder: (ctx) => SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.92,
        child: UserDrawerBody(user: user, actions: actions),
      ),
    );
  }
  return showGeneralDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.32),
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (_, _, _) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, _, _) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      final tokens = SearchTokens.of(Theme.of(ctx).brightness);
      final dark = Theme.of(ctx).brightness == Brightness.dark;
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(onTap: () => Navigator.of(ctx).pop()),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(curved),
              // A floating liquid-glass panel inset from the screen edges.
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SafeArea(
                  left: false,
                  child: SizedBox(
                    width: 440,
                    child: GlassPanelShadow(
                      radius: BorderRadius.circular(26),
                      shadows: tokens.panelShadow,
                      child: GlassContainer(
                        useOwnLayer: true,
                        quality: GlassQuality.premium,
                        clipBehavior: Clip.antiAlias,
                        shape: const LiquidRoundedSuperellipse(
                          borderRadius: 26,
                        ),
                        settings: liquidGlassPanelSettings(
                          glassFill: tokens.glassFill,
                          dark: dark,
                        ),
                        child: Material(
                          type: MaterialType.transparency,
                          child: UserDrawerBody(user: user, actions: actions),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class UserDrawerBody extends StatelessWidget {
  const UserDrawerBody({super.key, required this.user, required this.actions});

  final AdminUser user;
  final UserActions actions;

  @override
  Widget build(BuildContext context) {
    final u = user;
    final lastAdmin = actions.isLastActiveAdmin(u);
    // Clearance so the last action (delete) scrolls clear of the device's home
    // indicator on the phone bottom sheet. On the desktop drawer this is 0 — its
    // SafeArea wrapper has already consumed the inset.
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.hairline)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  UserAvatar(name: u.name, imageUrl: u.avatarUrl, size: 52),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 2),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Flexible(
                              child: Text(
                                u.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: AppTheme.fontBrand,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.ink,
                                ),
                              ),
                            ),
                            PronounsLabel(
                              pronouns: u.pronouns,
                              fontSize: 12.5,
                              leadingGap: 7,
                            ),
                          ],
                        ),
                        Text(
                          u.email,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(
                      LucideIcons.x,
                      size: 20,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  RoleBadge(u.role),
                  StatusBadge(u),
                  OriginTag(u.origin),
                ],
              ),
            ],
          ),
        ),
        // Body
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 28 + bottomInset),
            children: [
              _factsGrid(context, u),
              if (u.inviteExpired) ...[
                const SizedBox(height: 18),
                _expiredBanner(context, u),
              ],
              const SizedBox(height: 22),
              _sectionLabel(context, context.t('admin.um.manage')),
              const SizedBox(height: 12),
              ..._manageActions(context, u, lastAdmin),
              const SizedBox(height: 22),
              _sectionLabel(context, context.t('admin.um.activity')),
              const SizedBox(height: 12),
              ..._timeline(context, u),
              const SizedBox(height: 22),
              _sectionLabel(context, context.t('admin.um.dangerZone')),
              const SizedBox(height: 12),
              _ActRow(
                icon: LucideIcons.trash2,
                title: context.t('admin.um.deleteThisUser'),
                subtitle: context.t('admin.um.deleteThisUserSub'),
                danger: true,
                enabled: !lastAdmin,
                disabledReason: context.t('admin.um.reasonLastAdmin'),
                onTap: () {
                  Navigator.of(context).pop();
                  actions.openDelete([u.id]);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(BuildContext context, String text) => Row(
    children: [
      Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
          color: AppColors.inkSoft,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(child: Container(height: 1, color: AppColors.hairline)),
    ],
  );

  Widget _factsGrid(BuildContext context, AdminUser u) {
    final twoFa = u.sso
        ? context.t('admin.um.viaIdp')
        : (u.twoFA ? context.t('admin.um.enabled') : context.t('admin.um.off'));
    Widget fact(IconData ic, String k, String v) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(ic, size: 13, color: AppColors.inkFaint),
                const SizedBox(width: 5),
                Text(
                  k,
                  style: TextStyle(fontSize: 11, color: AppColors.inkFaint),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              v,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
    return Column(
      children: [
        Row(
          children: [
            fact(
              LucideIcons.briefcase,
              context.t('admin.um.fieldTitle'),
              u.title.isEmpty ? '—' : u.title,
            ),
            const SizedBox(width: 10),
            fact(
              LucideIcons.activity,
              context.t('admin.um.lastActive'),
              umRelTime(context, u.lastActive),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            fact(LucideIcons.shield, context.t('admin.um.twoFa'), twoFa),
            const SizedBox(width: 10),
            fact(
              LucideIcons.monitor,
              context.t('admin.um.sessions'),
              '${u.sessions}',
            ),
          ],
        ),
      ],
    );
  }

  Widget _expiredBanner(BuildContext context, AdminUser u) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.dangerSoft,
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(LucideIcons.mailWarning, size: 16, color: AppColors.danger),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            context.t(
              'admin.um.expiredBanner',
              variables: {
                'date': umPrettyDate(context, u.invitedAt),
                'name': u.name.split(' ').first,
              },
            ),
            style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.ink),
          ),
        ),
      ],
    ),
  );

  List<Widget> _manageActions(
    BuildContext context,
    AdminUser u,
    bool lastAdmin,
  ) {
    final rows = <Widget>[];
    void close() => Navigator.of(context).pop();

    if (u.status == UserStatus.invited) {
      rows.add(
        _ActRow(
          icon: LucideIcons.send,
          accent: true,
          title: context.t('admin.um.resendInvitation'),
          subtitle: context.t('admin.um.resendInvitationSub'),
          onTap: () {
            close();
            actions.openResend([u.id]);
          },
        ),
      );
    } else if (u.status == UserStatus.active) {
      rows.add(
        _ActRow(
          icon: LucideIcons.ban,
          title: context.t('admin.um.deactivateAccount'),
          subtitle: context.t('admin.um.deactivateAccountSub'),
          onTap: () {
            close();
            actions.openDeactivate([u.id]);
          },
        ),
      );
    } else if (u.status == UserStatus.pendingApproval) {
      rows.add(
        _ActRow(
          icon: LucideIcons.userCheck,
          success: true,
          title: context.t('admin.um.approve'),
          subtitle: context.t('admin.approvalHint'),
          onTap: () {
            close();
            actions.approve([u.id]);
          },
        ),
      );
    } else {
      rows.add(
        _ActRow(
          icon: LucideIcons.circleCheck,
          success: true,
          title: context.t('admin.um.reactivateAccount'),
          subtitle: context.t('admin.um.reactivateAccountSub'),
          onTap: () {
            close();
            actions.activate([u.id]);
          },
        ),
      );
    }

    final isAdmin = u.role == AdminRole.admin;
    rows.add(
      _ActRow(
        icon: isAdmin ? LucideIcons.shieldMinus : LucideIcons.shieldCheck,
        title: context.t(
          isAdmin ? 'admin.um.revokeAdminRights' : 'admin.um.promoteToAdmin',
        ),
        subtitle: context.t(
          isAdmin
              ? 'admin.um.revokeAdminRightsSub'
              : 'admin.um.promoteToAdminSub',
        ),
        enabled: isAdmin ? !lastAdmin : u.status != UserStatus.invited,
        disabledReason: context.t(
          isAdmin ? 'admin.um.reasonLastAdmin' : 'admin.um.reasonPendingInvite',
        ),
        onTap: () {
          close();
          actions.setRole([u.id], isAdmin ? AdminRole.user : AdminRole.admin);
        },
      ),
    );

    if (u.status != UserStatus.invited) {
      rows.add(
        _ActRow(
          icon: LucideIcons.keyRound,
          title: context.t(
            u.sso
                ? 'admin.um.passwordManagedByIdp'
                : 'admin.um.sendPasswordReset',
          ),
          subtitle: u.sso
              ? context.t('admin.um.passwordManagedByIdpSub')
              : context.t(
                  'admin.um.sendPasswordResetSub',
                  variables: {'email': u.email},
                ),
          enabled: !u.sso,
          disabledReason: context.t('admin.um.reasonSsoManaged'),
          onTap: () {
            close();
            actions.openReset([u.id]);
          },
        ),
      );
      rows.add(
        _ActRow(
          icon: LucideIcons.logOut,
          title: context.t('admin.um.revokeAllSessions'),
          subtitle: context.t(
            'admin.um.revokeAllSessionsSub',
            variables: {'n': '${u.sessions}'},
          ),
          enabled: u.sessions > 0,
          disabledReason: context.t('admin.um.reasonNoSessions'),
          onTap: () {
            close();
            actions.revokeSessions([u.id]);
          },
        ),
      );
    }

    return _withGaps(rows);
  }

  List<Widget> _timeline(BuildContext context, AdminUser u) {
    final entries = <(String, String)>[];
    if (u.lastActive != null) {
      entries.add((
        context.t('admin.um.tlLastActive'),
        umRelTime(context, u.lastActive),
      ));
    }
    if (u.status == UserStatus.invited) {
      final inviter = actions.nameById(u.invitedBy);
      entries.add((
        u.inviteExpired
            ? context.t('admin.um.tlInviteExpired')
            : (inviter != null
                  ? context.t(
                      'admin.um.tlInvitedBy',
                      variables: {'name': inviter.split(' ').first},
                    )
                  : context.t('admin.um.tlInvited')),
        umPrettyDate(context, u.invitedAt),
      ));
    } else if (u.joinedAt != null) {
      entries.add((
        context.t('admin.um.tlJoined'),
        umPrettyDate(context, u.joinedAt),
      ));
    }
    entries.add((
      context.t(
        'admin.um.tlCreatedVia',
        variables: {'origin': originLabel(context, u.origin)},
      ),
      umPrettyDate(context, u.joinedAt ?? u.invitedAt),
    ));

    return [
      for (var i = 0; i < entries.length; i++)
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    margin: const EdgeInsets.only(top: 3),
                    decoration: const BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  if (i != entries.length - 1)
                    Expanded(
                      child: Container(width: 1.5, color: AppColors.hairline),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entries[i].$1,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                      Text(
                        entries[i].$2,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.inkFaint,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
    ];
  }

  List<Widget> _withGaps(List<Widget> rows) {
    final out = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) out.add(const SizedBox(height: 8));
      out.add(rows[i]);
    }
    return out;
  }
}

/// A large tappable action button in the drawer's Manage / Danger sections.
class _ActRow extends StatelessWidget {
  const _ActRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
    this.disabledReason,
    this.danger = false,
    this.accent = false,
    this.success = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool enabled;
  final String? disabledReason;
  final bool danger;
  final bool accent;
  final bool success;

  @override
  Widget build(BuildContext context) {
    final Color tint = danger
        ? AppColors.danger
        : accent
        ? AppColors.accentStrong
        : success
        ? AppColors.success
        : AppColors.ink;
    final iconBg = danger
        ? AppColors.dangerSoft
        : accent
        ? AppColors.accentSoft
        : success
        ? AppColors.success.withValues(alpha: 0.12)
        : AppColors.surfaceMuted;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 17, color: tint),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: danger ? AppColors.danger : AppColors.ink,
                      ),
                    ),
                    Text(
                      enabled ? subtitle : (disabledReason ?? subtitle),
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.3,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                LucideIcons.chevronRight,
                size: 16,
                color: AppColors.inkFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fixed width of the desktop detail drawer.
const double kUmDrawerWidth = 440;
