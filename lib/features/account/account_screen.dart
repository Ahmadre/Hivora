import 'dart:async';

import 'package:dio/dio.dart' show MultipartFile;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/repositories/account_repository.dart';
import '../../core/blocs/app_config_bloc.dart';
import '../../core/blocs/auth_bloc.dart';
import '../../core/blocs/locale_cubit.dart';
import '../../core/blocs/theme_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/account_models.dart';
import '../../core/models/core_models.dart' show PlatformFlags;
import '../../core/notifications/fcm_service.dart'
    show pushSupportedOnThisPlatform;
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/file_pick.dart';
import '../../core/widgets/glass_popup_menu.dart';
import '../../core/widgets/app_avatar.dart';
import '../../core/widgets/hex_mark.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/hive_widgets.dart' show HiveSwitch;
import '../../core/widgets/honeycomb_background.dart';
import '../connect/server_switcher.dart';
import '../legal/legal_links.dart';
import '../sprint/modals/glass_modal.dart' show showGlassToast, GlassToastKind;
import '../shell/page_chrome.dart';
import 'account_modals.dart';
import 'account_widgets.dart';
import 'pat_section.dart';
import 'twofa_modals.dart';

part 'account_screen.widgets.dart';

/// The settings categories. On compact (phone) layouts each is its own
/// in-page sub-screen reached from the index list; on medium/expanded layouts
/// they all stack/column together on a single scroll.
enum _SettingsSection {
  security,
  sessions,
  notifications,
  access,
  tokens,
  appearance,
  data,
  danger,
}

/// Icon + section for each row of the compact settings index. Titles/subtitles
/// are looked up per-section so the index row, the sub-page app bar and the
/// section card header all stay in sync.
const _settingsMenu = <({_SettingsSection section, IconData icon})>[
  (section: _SettingsSection.security, icon: LucideIcons.shieldCheck),
  (section: _SettingsSection.sessions, icon: LucideIcons.monitorSmartphone),
  (section: _SettingsSection.notifications, icon: LucideIcons.bell),
  (section: _SettingsSection.access, icon: LucideIcons.layers),
  (section: _SettingsSection.appearance, icon: LucideIcons.sunMoon),
  (section: _SettingsSection.tokens, icon: LucideIcons.keyRound),
  (section: _SettingsSection.data, icon: LucideIcons.fileText),
  (section: _SettingsSection.danger, icon: LucideIcons.triangleAlert),
];

/// The self-service `/me` account surface — profile, email & security, 2FA,
/// device sessions, notification preferences, access overview, appearance and
/// the GDPR data/danger zone. Replaces the former lightweight settings screen.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, this.section});

  /// The open compact sub-page, carried in the URL (`/settings?section=…`) so
  /// the shell's settings button (`go('/settings')`) returns to the index.
  final String? section;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

/// The stable notification taxonomy — ids mirror the server's NOTIF_EVENTS.
/// Labels/descriptions are looked up from i18n (`account.notifications.event.*`).
const _notifEvents = <({String id, IconData icon, bool locked})>[
  (id: 'mentions', icon: LucideIcons.atSign, locked: false),
  (id: 'assigned', icon: LucideIcons.userCheck, locked: false),
  (id: 'comments', icon: LucideIcons.messageSquare, locked: false),
  (id: 'status', icon: LucideIcons.refreshCw, locked: false),
  (id: 'watching', icon: LucideIcons.eye, locked: false),
  (id: 'ingest', icon: LucideIcons.inbox, locked: false),
  (id: 'sprint', icon: LucideIcons.goal, locked: false),
  (id: 'invites', icon: LucideIcons.usersRound, locked: false),
  (id: 'digest', icon: LucideIcons.newspaper, locked: false),
  (id: 'security', icon: LucideIcons.shieldCheck, locked: true),
];

class _AccountScreenState extends State<AccountScreen> {
  AccountRepository get _repo => context.read<AccountRepository>();

  /// Whether the embedded MCP server surface (Personal Access Tokens) is exposed
  /// — driven by the server's `mcp` feature flag.
  bool get _mcpEnabled =>
      context.read<AppConfigBloc>().state.meta?.isFlagEnabled(
        PlatformFlags.mcp,
      ) ??
      false;

  Me? _me;
  List<DeviceSession> _sessions = const [];

  /// How many sessions the account has in total, which is more than the page
  /// held whenever the reader has not expanded the list.
  int _sessionsTotal = 0;

  /// Whether the full list is showing rather than the first few rows.
  bool _sessionsExpanded = false;

  /// Set while the rest of the list is being fetched after an expand.
  bool _sessionsLoadingMore = false;
  List<AccessTeam> _teams = const [];
  List<AccessProject> _projects = const [];
  NotifPrefs? _prefs;
  bool _loading = true;

  Timer? _prefsDebounce;
  bool _accessTeams = true;
  bool _avatarBusy = false;

  /// The open sub-page on compact layouts; `null` shows the index list. Always
  /// `null` on medium/expanded, where every section renders on one scroll.
  /// Derived from the route's `section` query parameter so the shell's
  /// settings button (`go('/settings')`) always returns to the index.
  _SettingsSection? get _section =>
      _SettingsSection.values.asNameMap()[widget.section];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _prefsDebounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _repo.meAccount(),
        _repo.sessionsPage(
          size: _sessionsExpanded ? _sessionsPageSize : _sessionsPreview,
        ),
        _repo.myTeams(),
        _repo.myProjects(),
      ]);
      if (!mounted) return;
      final page =
          results[1] as ({List<DeviceSession> items, int total});
      setState(() {
        _me = results[0] as Me;
        _sessions = page.items;
        _sessionsTotal = page.total;
        _teams = results[2] as List<AccessTeam>;
        _projects = results[3] as List<AccessProject>;
        _prefs = (results[0] as Me).notificationPreferences;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String message, {GlassToastKind kind = GlassToastKind.success}) {
    if (!mounted) return;
    showGlassToast(context, context.t(message), kind: kind);
  }

  // --- mutations ------------------------------------------------------------

  Future<void> _editProfile() async {
    final authBloc = context.read<AuthBloc>();
    final toast = context.t('account.profileUpdated');
    final saved = await showEditProfile(context, _repo, _me!);
    if (saved != null && mounted) {
      setState(() => _me = saved);
      // Keep the app shell (avatar / name) in sync with the edited profile.
      authBloc.add(const AuthChecked());
      _toast(toast);
    }
  }

  /// Applies a language choice instantly (local cubit) and persists it to the
  /// account so the backend localizes emails to the same language. Best-effort:
  /// a failed sync leaves the UI language applied and the `Accept-Language`
  /// header still carries it on every request.
  void _setLanguage(String code) {
    context.read<LocaleCubit>().setLocale(code);
    if (_me?.locale == code) return;
    _repo
        .updateMyProfile(locale: code)
        .then((saved) {
          if (mounted) setState(() => _me = saved);
        })
        .catchError((_) {});
  }

  Future<void> _changeAvatar() async {
    // Capture context-derived values up front so nothing reads `context` across
    // the upload's async gap.
    final authBloc = context.read<AuthBloc>();
    final updated = context.t('account.avatar.updated');
    final failed = context.t('account.avatar.failed');

    final List<ChosenFile> picked;
    try {
      picked = await pickFilesToUpload(
        context,
        kind: FilePickKind.image,
        withData: kIsWeb,
      );
    } catch (_) {
      // A dialog that cannot open used to throw straight past this screen.
      if (mounted) _toast(failed, kind: GlassToastKind.error);
      return;
    }
    // An empty list means cancelled — nothing to report.
    if (picked.isEmpty) return;
    final file = picked.first;
    final multipart = kIsWeb
        ? (file.bytes == null
              ? null
              : MultipartFile.fromBytes(file.bytes!, filename: file.name))
        : (file.path == null
              ? null
              : await MultipartFile.fromFile(file.path!, filename: file.name));
    if (multipart == null) return;

    setState(() => _avatarBusy = true);
    try {
      // The returned URL carries a fresh `?v=` token, so AppAvatar fetches the
      // new picture under a new cache key. Refresh AuthUser so the shell avatar
      // (which reads AuthUser.avatarUrl) updates too.
      final url = await _repo.uploadAvatar(multipart);
      if (!mounted) return;
      setState(() => _me = _me!.copyWith(avatarUrl: url));
      authBloc.add(const AuthChecked());
      _toast(updated);
    } catch (_) {
      if (mounted) _toast(failed, kind: GlassToastKind.error);
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Future<void> _removeAvatar() async {
    final authBloc = context.read<AuthBloc>();
    final removed = context.t('account.avatar.removed');
    final failed = context.t('account.avatar.failed');
    setState(() => _avatarBusy = true);
    try {
      await _repo.deleteAvatar();
      if (!mounted) return;
      setState(() => _me = _me!.copyWith(clearAvatar: true));
      authBloc.add(const AuthChecked());
      _toast(removed);
    } catch (_) {
      if (mounted) _toast(failed, kind: GlassToastKind.error);
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Future<void> _editAvatar() async {
    if (_avatarBusy) return;
    final hasAvatar = (_me!.avatarUrl ?? '').isNotEmpty;
    if (!hasAvatar) {
      _changeAvatar();
      return;
    }
    final action = await showAvatarActions(context);
    if (action == AvatarAction.change) {
      _changeAvatar();
    } else if (action == AvatarAction.remove) {
      _removeAvatar();
    }
  }

  Future<void> _changeEmail() async {
    final toast = context.t('account.emailModal.sentToast');
    final sent = await showChangeEmail(context, _repo, _me!);
    if (sent == true && mounted) {
      _toast(toast);
      _load();
    }
  }

  Future<void> _resetPassword() async {
    final toast = context.t('account.passwordModal.sentToast');
    final ok = await showConfirm(
      context,
      icon: LucideIcons.keyRound,
      title: context.t('account.passwordModal.title'),
      message: context.t('account.passwordModal.message'),
      confirmLabel: context.t('account.passwordModal.confirm'),
      onConfirm: () => _repo.sendPasswordReset(),
    );
    if (ok == true) _toast(toast);
  }

  Future<void> _enable2fa() async {
    final toast = context.t('twofa.enabledToast');
    final enabled = await show2faWizard(context, _repo);
    if (enabled == true) {
      _toast(toast);
      _load();
    }
  }

  Future<void> _disable2fa() async {
    final toast = context.t('twofa.disabledToast');
    final disabled = await show2faDisable(context, _repo);
    if (disabled == true) {
      _toast(toast);
      _load();
    }
  }

  Future<void> _revokeSession(DeviceSession s) async {
    final toast = context.t('account.sessions.revokedToast');
    final ok = await showConfirm(
      context,
      icon: LucideIcons.logOut,
      title: context.t('account.sessions.revokeTitle'),
      message: context.t(
        'account.sessions.revokeMessage',
        variables: {
          'device':
              s.client ?? s.os ?? context.t('account.sessions.thisDevice'),
        },
      ),
      confirmLabel: context.t('account.sessions.signOut'),
      danger: true,
      onConfirm: () => _repo.revokeSession(s.id),
    );
    if (ok == true) {
      _toast(toast);
      _load();
    }
  }

  Future<void> _revokeOthers() async {
    final toast = context.t('account.sessions.revokeOthersToast');
    final ok = await showConfirm(
      context,
      icon: LucideIcons.logOut,
      title: context.t('account.sessions.revokeOthersTitle'),
      message: context.t('account.sessions.revokeOthersMessage'),
      confirmLabel: context.t('account.sessions.revokeOthersConfirm'),
      danger: true,
      onConfirm: () => _repo.revokeOtherSessions(),
    );
    if (ok == true) {
      _toast(toast);
      _load();
    }
  }

  Future<void> _dataReport() async {
    final toast = context.t('account.data.requestedToast');
    final ok = await showConfirm(
      context,
      icon: LucideIcons.download,
      title: context.t('account.data.request'),
      message: context.t('account.data.requestModalMessage'),
      confirmLabel: context.t('account.data.requestModalConfirm'),
      onConfirm: () => _repo.requestDataReport(),
    );
    if (ok == true) _toast(toast);
  }

  Future<void> _deleteAccount() async {
    final done = await showDeleteAccount(context, _repo);
    if (done == true && mounted) {
      context.read<AuthBloc>().add(const LogoutRequested());
    }
  }

  void _onTogglePrefs(NotifPrefs next) {
    final failed = context.t('account.notifications.saveFailed');
    setState(() => _prefs = next);
    _prefsDebounce?.cancel();
    _prefsDebounce = Timer(const Duration(milliseconds: 450), () async {
      try {
        final saved = await _repo.saveNotificationPrefs(next);
        if (mounted) setState(() => _prefs = saved);
      } catch (_) {
        if (mounted) _toast(failed, kind: GlassToastKind.error);
      }
    });
  }

  // --- build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_loading && _me == null) {
      return const Center(child: HiveLoader());
    }
    if (_me == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.t('account.retryError'),
                style: TextStyle(color: AppColors.inkSoft),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _load,
                child: Text(context.t('common.retry')),
              ),
            ],
          ),
        ),
      );
    }

    // Phone: an index list whose rows open one section at a time, so the
    // surface never overloads. Desktop / tablet keep the single rich scroll.
    if (context.isCompact) return _compactView();
    return _wideView(expanded: context.isExpanded);
  }

  /// Desktop (two-column) / tablet (single-column) layout — unchanged: every
  /// section renders together on one scroll behind the account hero.
  Widget _wideView({required bool expanded}) {
    final isAdmin = context.read<AuthBloc>().state.user?.isAdmin ?? false;
    final left = <Widget>[
      _securitySection(),
      const SizedBox(height: 16),
      _sessionsSection(),
      const SizedBox(height: 16),
      _notificationsSection(),
    ];
    final right = <Widget>[
      _accessSection(),
      const SizedBox(height: 16),
      _appearanceSection(),
      if (_mcpEnabled) ...[const SizedBox(height: 16), const PatSection()],
      // Admin area is its own top-level entry here, not buried in Appearance.
      if (isAdmin) ...[const SizedBox(height: 16), _adminSection()],
      const SizedBox(height: 16),
      _dataSection(),
      const SizedBox(height: 16),
      _dangerSection(),
    ];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: context.pagePadding,
        children: [
          // No in-page title: the shell's sub-page bar already shows back +
          // "settings" for this route.
          _profileHero(),
          const SizedBox(height: 16),
          if (expanded)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 1618, child: Column(children: left)),
                const SizedBox(width: 16),
                Expanded(flex: 1000, child: Column(children: right)),
              ],
            )
          else
            Column(children: [...left, const SizedBox(height: 16), ...right]),
        ],
      ),
    );
  }

  // --- compact (phone) master → detail --------------------------------------

  /// Phone layout: list ↔ detail in-page navigation. Both steps live on the
  /// same `/settings` route, so the shell's back button is wired through
  /// [PageChrome] — in a detail it returns to the index, on the index it pops
  /// back to where settings was opened from.
  Widget _compactView() {
    final section = _section;
    if (section != null) {
      return PageChrome(
        title: _sectionTitle(section),
        onBack: () => context.go('/settings'),
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            key: ValueKey(section),
            padding: context.pagePadding,
            children: [_sectionCard(section)],
          ),
        ),
      );
    }
    // Index: the hero (profile + sign-out) above a grouped list of categories.
    // The explicit title also resets any stale chrome a closed detail published.
    return PageChrome(
      title: context.t('nav.settings'),
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: context.pagePadding,
          children: [
            _profileHero(),
            const SizedBox(height: 16),
            _sectionMenu(),
          ],
        ),
      ),
    );
  }

  /// The grouped list of category rows on the compact index. The Admin area —
  /// when the user is an admin — sits here as its own top-level entry (it
  /// navigates to `/admin` rather than opening an in-page section).
  Widget _sectionMenu() {
    final isAdmin = context.read<AuthBloc>().state.user?.isAdmin ?? false;
    final mcpEnabled = _mcpEnabled;
    final tiles = <Widget>[];
    for (final item in _settingsMenu) {
      if (item.section == _SettingsSection.tokens && !mcpEnabled) continue;
      tiles.add(
        _navTile(
          icon: item.icon,
          title: _sectionTitle(item.section),
          subtitle: _sectionSubtitle(item.section),
          danger: item.section == _SettingsSection.danger,
          onTap: () => context.go('/settings?section=${item.section.name}'),
        ),
      );
      if (item.section == _SettingsSection.appearance && isAdmin) {
        tiles.add(
          _navTile(
            icon: LucideIcons.shieldUser,
            title: context.t('settings.adminArea'),
            subtitle: context.t('settings.adminAreaDesc'),
            onTap: () => context.go('/admin'),
          ),
        );
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0)
              Divider(height: 1, indent: 62, color: AppColors.hairline2),
            tiles[i],
          ],
        ],
      ),
    );
  }

  /// A tappable navigation row: amber (or red) icon tile, title, subtitle and a
  /// chevron. Shared by the compact index list and the desktop admin nav card.
  Widget _navTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final accent = danger ? AppColors.danger : AppColors.accentStrong;
    final accentBg = danger
        ? AppColors.danger.withValues(alpha: 0.12)
        : AppColors.accentSoft;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accentBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 18, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: AppTheme.fontBrand,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: danger ? AppColors.danger : AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                LucideIcons.chevronRight,
                size: 18,
                color: AppColors.inkFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _sectionTitle(_SettingsSection s) => context.t(switch (s) {
    _SettingsSection.security => 'account.security.title',
    _SettingsSection.sessions => 'account.sessions.title',
    _SettingsSection.notifications => 'account.notifications.title',
    _SettingsSection.access => 'account.access.title',
    _SettingsSection.tokens => 'account.tokens.title',
    _SettingsSection.appearance => 'account.appearance.title',
    _SettingsSection.data => 'account.data.title',
    _SettingsSection.danger => 'account.danger.title',
  });

  String _sectionSubtitle(_SettingsSection s) => context.t(switch (s) {
    _SettingsSection.security => 'account.security.subtitle',
    _SettingsSection.sessions => 'account.sessions.subtitle',
    _SettingsSection.notifications => 'account.notifications.subtitle',
    _SettingsSection.access => 'account.access.subtitle',
    _SettingsSection.tokens => 'account.tokens.subtitle',
    _SettingsSection.appearance => 'account.appearance.subtitle',
    _SettingsSection.data => 'account.data.subtitle',
    _SettingsSection.danger => 'account.danger.subtitle',
  });

  Widget _sectionCard(_SettingsSection s) => switch (s) {
    _SettingsSection.security => _securitySection(),
    _SettingsSection.sessions => _sessionsSection(),
    _SettingsSection.notifications => _notificationsSection(),
    _SettingsSection.access => _accessSection(),
    _SettingsSection.tokens => const PatSection(),
    _SettingsSection.appearance => _appearanceSection(),
    _SettingsSection.data => _dataSection(),
    _SettingsSection.danger => _dangerSection(),
  };

  // --- profile hero ---------------------------------------------------------

  Widget _profileHero() {
    final me = _me!;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      child: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.rail,
                    AppColors.navy,
                    AppColors.accentStrong,
                  ],
                  stops: [0, 0.55, 1.4],
                ),
              ),
            ),
          ),
          const Positioned.fill(
            child: HoneycombBackground(opacity: 0.06, color: Colors.white),
          ),
          const Positioned(
            right: -10,
            top: -10,
            child: Opacity(
              opacity: 0.10,
              child: HexMark(size: 120, color: Colors.white),
            ),
          ),
          ResponsiveBuilder(
            builder: (context, size) {
              final column = size == LayoutSize.compact;
              final identity = _heroIdentity(me, onDark: true, compact: column);
              final actions = _heroActions(compact: column);
              return Padding(
                padding: EdgeInsets.all(column ? 16 : 20),
                child: Flex(
                  direction: column ? Axis.vertical : Axis.horizontal,
                  crossAxisAlignment: column
                      ? CrossAxisAlignment.stretch
                      : CrossAxisAlignment.center,
                  children: [
                    Expanded(flex: column ? 0 : 1, child: identity),
                    SizedBox(width: column ? 0 : 16, height: column ? 14 : 0),
                    actions,
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _heroIdentity(Me me, {required bool onDark, bool compact = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EditableAvatar(
          name: me.displayName,
          imageUrl: me.avatarUrl,
          busy: _avatarBusy,
          onTap: _editAvatar,
          radius: compact ? 24 : 28,
        ),
        SizedBox(width: compact ? 12 : 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                me.displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppTheme.fontBrand,
                  fontSize: compact ? 18 : 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '@${me.username} · ${me.title ?? me.origin.label}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.78),
                ),
              ),
              SizedBox(height: compact ? 8 : 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final role in me.roles)
                    AccountPill(
                      label: _roleLabel(role),
                      color: Colors.white,
                      background: Colors.white.withValues(alpha: 0.18),
                    ),
                  if (me.createdAt != null)
                    AccountPill(
                      label: context.t(
                        'account.memberSince',
                        variables: {'date': _monthYear(me.createdAt!)},
                      ),
                      icon: LucideIcons.calendar,
                      color: Colors.white,
                      background: Colors.white.withValues(alpha: 0.12),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _heroActions({bool compact = false}) {
    final editProfile = FilledButton.icon(
      onPressed: _editProfile,
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.navy,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        ),
      ),
      icon: const Icon(LucideIcons.pencil, size: 15),
      label: Text(context.t('account.editProfile')),
    );
    final signOut = TextButton.icon(
      onPressed: () => context.read<AuthBloc>().add(const LogoutRequested()),
      style: TextButton.styleFrom(
        foregroundColor: Colors.white.withValues(alpha: 0.85),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 8,
          vertical: 11,
        ),
      ),
      icon: const Icon(LucideIcons.logOut, size: 15),
      label: Text(context.t('account.signOut')),
    );

    // Mobile: lay the two actions side by side (Edit primary, Sign out
    // secondary) instead of stacking them — saves a full button's height.
    if (compact) {
      return Row(
        children: [
          Expanded(child: editProfile),
          const SizedBox(width: 10),
          signOut,
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [editProfile, const SizedBox(height: 8), signOut],
    );
  }

  // --- email & security -----------------------------------------------------

  Widget _securitySection() {
    final me = _me!;
    final sso = me.origin.isSso;
    return AccountSection(
      icon: LucideIcons.shieldCheck,
      title: context.t('account.security.title'),
      subtitle: context.t('account.security.subtitle'),
      children: [
        SettingRow(
          label: context.t('account.security.email'),
          description: me.email,
          stack: context.isCompact,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AccountPill(
                label: me.emailVerified
                    ? context.t('account.security.verified')
                    : context.t('account.security.unverified'),
                icon: me.emailVerified
                    ? LucideIcons.circleCheck
                    : LucideIcons.info,
                color: me.emailVerified ? AppColors.success : AppColors.warning,
              ),
              if (!sso) ...[
                const SizedBox(width: 8),
                AccountActionButton(
                  label: context.t('account.security.change'),
                  icon: LucideIcons.pencil,
                  onPressed: _changeEmail,
                ),
              ],
            ],
          ),
        ),
        if (me.pendingEmail != null) ...[
          const SizedBox(height: 4),
          AccountNote(
            text: context.t(
              'account.security.pendingEmail',
              variables: {'email': me.pendingEmail!},
            ),
          ),
          const SizedBox(height: 4),
        ],
        if (sso)
          AccountNote(
            text: context.t(
              'account.security.ssoManaged',
              variables: {'provider': me.origin.label},
            ),
            icon: LucideIcons.lock,
            tone: AccountNoteTone.info,
          ),
        if (!sso) ...[
          Divider(height: 1, color: AppColors.hairline2),
          SettingRow(
            label: context.t('account.security.password'),
            description: me.passwordChangedAt != null
                ? context.t(
                    'account.security.passwordChanged',
                    variables: {'date': _monthYear(me.passwordChangedAt!)},
                  )
                : context.t('account.security.passwordResetHint'),
            stack: context.isCompact,
            trailing: AccountActionButton(
              label: context.t('account.security.reset'),
              icon: LucideIcons.keyRound,
              onPressed: _resetPassword,
            ),
          ),
        ],
        Divider(height: 1, color: AppColors.hairline2),
        SettingRow(
          label: context.t('account.security.twoFactor'),
          description: me.twoFactor.enabled
              ? context.t(
                  'account.security.twoFactorOn',
                  count: me.twoFactor.recoveryRemaining,
                )
              : context.t('account.security.twoFactorOff'),
          stack: context.isCompact,
          trailing: me.twoFactor.enabled
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AccountActionButton(
                      label: context.t('account.security.codes'),
                      icon: LucideIcons.keyRound,
                      onPressed: () =>
                          show2faManage(context, _repo).then((_) => _load()),
                    ),
                    const SizedBox(width: 8),
                    AccountActionButton(
                      label: context.t('account.security.disable'),
                      danger: true,
                      onPressed: _disable2fa,
                    ),
                  ],
                )
              : FilledButton.icon(
                  onPressed: _enable2fa,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 9,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppTheme.radiusControl,
                      ),
                    ),
                  ),
                  icon: const Icon(LucideIcons.shieldCheck, size: 15),
                  label: Text(context.t('account.security.enable')),
                ),
        ),
      ],
    );
  }

  // --- sessions -------------------------------------------------------------

  /// How many device rows the settings screen shows before the expander.
  ///
  /// Enough to answer "is anything signed in that should not be" at a glance —
  /// this device plus the three most recent — without the section becoming the
  /// longest thing on the page. Fifteen devices is an ordinary number for an
  /// account a couple of years old, and fifteen rows buried every setting
  /// underneath them.
  static const int _sessionsPreview = 4;

  /// The rows on screen: the whole list once expanded, the newest few until
  /// then. The current device is always among them — the server orders by last
  /// activity, and nothing is more recently active than the device asking.
  List<DeviceSession> get _visibleSessions => _sessionsExpanded
      ? _sessions
      : _sessions.take(_sessionsPreview).toList();

  /// The largest page the server will serve; it clamps anything above this.
  ///
  /// An account with more devices than one page holds keeps the expander
  /// around, so the next press fetches the next page rather than silently
  /// stopping at a hundred.
  static const int _sessionsPageSize = 100;

  /// Shows the rest of the list, fetching the next page when one is missing.
  Future<void> _expandSessions() async {
    setState(() => _sessionsExpanded = true);
    if (_sessions.length >= _sessionsTotal || _sessionsLoadingMore) return;
    setState(() => _sessionsLoadingMore = true);
    try {
      // Re-fetched from the first page rather than appended: revoking a device
      // elsewhere shifts every later row, and an offset page would then repeat
      // one session and skip another. One page is also all of them in practice
      // — the server caps a page at this size, and an account with more live
      // sessions than that has a problem no expander is going to solve.
      final page = await _repo.sessionsPage(size: _sessionsPageSize);
      if (!mounted) return;
      setState(() {
        _sessions = page.items;
        _sessionsTotal = page.total;
        _sessionsLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sessionsLoadingMore = false;
        // Back to the preview: an expander that opened onto the same four rows
        // it already showed looks like the button is broken.
        _sessionsExpanded = false;
      });
      _toast('errors.unexpected', kind: GlassToastKind.error);
    }
  }

  Widget _sessionsSection() {
    final others = _sessions.where((s) => !s.current).toList();
    final visible = _visibleSessions;
    final hidden = _sessionsTotal - visible.length;
    return AccountSection(
      icon: LucideIcons.monitorSmartphone,
      title: context.t('account.sessions.title'),
      subtitle: context.t('account.sessions.devices', count: _sessionsTotal),
      trailing: others.isEmpty
          ? null
          : AccountActionButton(
              label: context.t('account.sessions.signOutOthers'),
              icon: LucideIcons.logOut,
              danger: true,
              onPressed: _revokeOthers,
            ),
      children: [
        for (var i = 0; i < visible.length; i++) ...[
          if (i > 0) Divider(height: 1, color: AppColors.hairline2),
          _sessionRow(visible[i]),
        ],
        if (hidden > 0 || _sessionsExpanded && _sessionsTotal > _sessionsPreview)
          Divider(height: 1, color: AppColors.hairline2),
        if (hidden > 0)
          _SessionsExpander(
            label: context.t('account.sessions.showAll', count: hidden),
            busy: _sessionsLoadingMore,
            expanded: false,
            onPressed: _expandSessions,
          )
        else if (_sessionsExpanded && _sessionsTotal > _sessionsPreview)
          _SessionsExpander(
            label: context.t('account.sessions.showFewer'),
            busy: false,
            expanded: true,
            onPressed: () => setState(() => _sessionsExpanded = false),
          ),
      ],
    );
  }

  Widget _sessionRow(DeviceSession s) {
    final icon = switch (s.kind) {
      'phone' => LucideIcons.smartphone,
      'tablet' => LucideIcons.tablet,
      _ => LucideIcons.monitor,
    };
    final meta = [
      if (s.location != null) s.location!,
      if (s.ipMasked != null) s.ipMasked!,
      if (s.lastActive != null) _relative(s.lastActive!),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.hairline),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 17, color: AppColors.inkSoft),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '${s.os ?? '—'} · ${s.client ?? s.app ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    if (s.current) ...[
                      const SizedBox(width: 8),
                      AccountPill(
                        label: context.t('account.sessions.thisDevice'),
                      ),
                    ],
                  ],
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
                    softWrap: true,
                  ),
                ],
              ],
            ),
          ),
          if (!s.current) ...[
            const SizedBox(width: 8),
            IconButton(
              tooltip: context.t('account.sessions.signOut'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                LucideIcons.logOut,
                size: 17,
                color: AppColors.danger,
              ),
              onPressed: () => _revokeSession(s),
            ),
          ],
        ],
      ),
    );
  }

  // --- notifications --------------------------------------------------------

  Widget _notificationsSection() {
    final prefs = _prefs!;
    return AccountSection(
      icon: LucideIcons.bell,
      title: context.t('account.notifications.title'),
      subtitle: context.t('account.notifications.subtitle'),
      children: [
        _channelMaster(
          context.t('account.notifications.emailChannel'),
          LucideIcons.mail,
          prefs.emailEnabled,
          (v) => _onTogglePrefs(prefs.copyWith(emailEnabled: v)),
        ),
        Divider(height: 1, color: AppColors.hairline2),
        _channelMaster(
          context.t('account.notifications.pushChannel'),
          LucideIcons.smartphone,
          prefs.pushEnabled,
          (v) => _onTogglePrefs(prefs.copyWith(pushEnabled: v)),
          undeliverableHere: !pushSupportedOnThisPlatform,
        ),
        const SizedBox(height: 8),
        if (context.isCompact)
          ..._notifEvents.map(_notifCard)
        else ...[
          _matrixHeader(),
          for (final e in _notifEvents) _matrixRow(e),
        ],
      ],
    );
  }

  /// One channel's master switch.
  ///
  /// [undeliverableHere] says the *device* cannot receive this channel — Linux
  /// and the web build have no push service — and changes only the sentence
  /// under the label. The switch stays live and the stored value is untouched
  /// on purpose: these preferences belong to the account, not to this device,
  /// and the phone in the user's pocket is the thing they actually govern.
  /// Disabling the controls here would have let a desktop session quietly turn
  /// push off everywhere.
  Widget _channelMaster(
    String label,
    IconData icon,
    bool value,
    ValueChanged<bool> onChanged, {
    bool undeliverableHere = false,
  }) {
    return SettingRow(
      label: label,
      description: undeliverableHere
          ? context.t('account.notifications.pushUnsupported')
          : value
          ? context.t('account.notifications.channelOn')
          : context.t('account.notifications.channelOff'),
      icon: icon,
      trailing: HiveSwitch(value: value, onChanged: onChanged),
    );
  }

  Widget _matrixHeader() {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6, left: 2, right: 2),
      child: Row(
        children: [
          const Spacer(),
          _colLabel(context.t('account.notifications.colEmail')),
          const SizedBox(width: 16),
          _colLabel(context.t('account.notifications.colPush')),
        ],
      ),
    );
  }

  String _eventLabel(String id) =>
      context.t('account.notifications.event.$id.label');
  String _eventDesc(String id) =>
      context.t('account.notifications.event.$id.desc');

  Widget _colLabel(String label) => SizedBox(
    width: 40,
    child: Text(
      label,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
        color: AppColors.inkFaint,
      ),
    ),
  );

  ChannelPair _channelOf(String id) =>
      _prefs!.events[id] ?? const ChannelPair(email: false, push: false);

  void _setChannel(String id, {bool? email, bool? push}) {
    final events = Map<String, ChannelPair>.from(_prefs!.events);
    events[id] = _channelOf(id).copyWith(email: email, push: push);
    _onTogglePrefs(_prefs!.copyWith(events: events));
  }

  Widget _matrixRow(({String id, IconData icon, bool locked}) e) {
    final pair = _channelOf(e.id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Icon(e.icon, size: 16, color: AppColors.inkSoft),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _eventLabel(e.id),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                Text(
                  _eventDesc(e.id),
                  style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
                  softWrap: true,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _matrixCell(
            locked: e.locked,
            value: pair.email,
            enabled: _prefs!.emailEnabled,
            onChanged: (v) => _setChannel(e.id, email: v),
          ),
          const SizedBox(width: 16),
          _matrixCell(
            locked: e.locked,
            value: pair.push,
            enabled: _prefs!.pushEnabled,
            onChanged: (v) => _setChannel(e.id, push: v),
          ),
        ],
      ),
    );
  }

  Widget _matrixCell({
    required bool locked,
    required bool value,
    required bool enabled,
    required ValueChanged<bool> onChanged,
  }) {
    return SizedBox(
      width: 40,
      child: Center(
        child: locked
            ? Tooltip(
                message: context.t('account.notifications.alwaysOn'),
                child: Icon(
                  LucideIcons.lock,
                  size: 15,
                  color: AppColors.inkFaint,
                ),
              )
            : HiveSwitch(
                value: enabled && value,
                onChanged: enabled ? onChanged : null,
              ),
      ),
    );
  }

  /// Phone layout: one card per event with stacked Email / Push rows.
  Widget _notifCard(({String id, IconData icon, bool locked}) e) {
    final pair = _channelOf(e.id);
    Widget channel(
      String label,
      bool value,
      bool enabled,
      ValueChanged<bool>? onChanged,
    ) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
              ),
            ),
            if (e.locked)
              AccountPill(label: context.t('account.notifications.alwaysOn'))
            else
              HiveSwitch(
                value: enabled && value,
                onChanged: enabled ? onChanged : null,
              ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
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
              Icon(e.icon, size: 16, color: AppColors.inkSoft),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  _eventLabel(e.id),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            _eventDesc(e.id),
            style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
            softWrap: true,
          ),
          channel(
            context.t('account.notifications.colEmail'),
            pair.email,
            _prefs!.emailEnabled,
            (v) => _setChannel(e.id, email: v),
          ),
          channel(
            context.t('account.notifications.colPush'),
            pair.push,
            _prefs!.pushEnabled,
            (v) => _setChannel(e.id, push: v),
          ),
        ],
      ),
    );
  }

  // --- access ---------------------------------------------------------------

  Widget _accessSection() {
    return AccountSection(
      icon: LucideIcons.layers,
      title: context.t('account.access.title'),
      subtitle: context.t('account.access.subtitle'),
      trailing: _AccessToggle(
        teams: _accessTeams,
        teamsLabel: context.t('account.access.teams'),
        projectsLabel: context.t('account.access.projects'),
        onChanged: (v) => setState(() => _accessTeams = v),
      ),
      children: [
        if (_accessTeams)
          if (_teams.isEmpty)
            _emptyRow(context.t('account.access.noTeams'))
          else
            for (var i = 0; i < _teams.length; i++) ...[
              if (i > 0) Divider(height: 1, color: AppColors.hairline2),
              _accessRow(
                glyph: _teams[i].key,
                color: HSLColor.fromAHSL(
                  1,
                  _teams[i].hue.toDouble(),
                  0.5,
                  0.55,
                ).toColor(),
                name: _teams[i].name,
                meta: context.t(
                  'account.access.members',
                  count: _teams[i].members,
                ),
                role: _roleLabel(_teams[i].role),
                onTap: () => context.go('/teams/${_teams[i].id}'),
              ),
            ]
        else if (_projects.isEmpty)
          _emptyRow(context.t('account.access.noProjects'))
        else
          for (var i = 0; i < _projects.length; i++) ...[
            if (i > 0) Divider(height: 1, color: AppColors.hairline2),
            _accessRow(
              glyph: _projects[i].key,
              color: _parseHex(_projects[i].color),
              name: _projects[i].name,
              meta: _projects[i].key,
              role: _roleLabel(_projects[i].role),
              onTap: () => context.go('/issues?projectId=${_projects[i].id}'),
            ),
          ],
      ],
    );
  }

  /// Localizes a server role label (e.g. "Member" → "Mitglied"); unknown roles
  /// pass through unchanged.
  String _roleLabel(String role) {
    final key = 'account.roles.${role.toLowerCase()}';
    final translated = context.t(key);
    return translated == key ? role : translated;
  }

  Widget _accessRow({
    required String glyph,
    required Color color,
    required String name,
    required String meta,
    required String role,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withValues(alpha: 0.4)),
              ),
              alignment: Alignment.center,
              child: Text(
                glyph.isEmpty
                    ? '?'
                    : glyph.substring(0, glyph.length >= 3 ? 3 : glyph.length),
                style: TextStyle(
                  fontFamily: AppTheme.fontMono,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  Text(
                    meta,
                    style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AccountPill(label: role),
            const SizedBox(width: 4),
            Icon(LucideIcons.chevronRight, size: 16, color: AppColors.inkFaint),
          ],
        ),
      ),
    );
  }

  // --- appearance (folded-in settings) --------------------------------------

  Widget _appearanceSection() {
    final config = context.watch<AppConfigBloc>().state;
    final locale = context.watch<LocaleCubit>().state;
    final themeMode = context.watch<ThemeCubit>().state;
    return AccountSection(
      icon: LucideIcons.sunMoon,
      title: context.t('account.appearance.title'),
      subtitle: context.t('account.appearance.subtitle'),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: ServerCard(),
        ),
        Divider(height: 1, color: AppColors.hairline2),
        SettingRow(
          label: context.t('settings.language'),
          icon: LucideIcons.globe,
          stack: context.isCompact,
          trailing: GlassPopupMenu<String>(
            value: locale.languageCode,
            width: 220,
            onSelected: _setLanguage,
            items: [
              for (final entry in I18n.localeNames.entries)
                GlassMenuItem(value: entry.key, label: entry.value),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                border: Border.all(color: AppColors.hairline),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    I18n.localeNames[locale.languageCode] ??
                        locale.languageCode,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    LucideIcons.chevronDown,
                    size: 16,
                    color: AppColors.inkSoft,
                  ),
                ],
              ),
            ),
          ),
        ),
        Divider(height: 1, color: AppColors.hairline2),
        SettingRow(
          label: context.t('settings.theme'),
          icon: LucideIcons.sunMoon,
          stack: context.isCompact,
          trailing: _ThemeSelector(
            mode: themeMode,
            onChanged: (m) => context.read<ThemeCubit>().setMode(m),
          ),
        ),
        Divider(height: 1, color: AppColors.hairline2),
        SettingRow(
          label: context.t('legal.privacyPolicy'),
          icon: LucideIcons.shieldAlert,
          trailing: IconButton(
            icon: const Icon(LucideIcons.externalLink, size: 18),
            onPressed: () => openPrivacyPolicy(context),
          ),
        ),
        Divider(height: 1, color: AppColors.hairline2),
        SettingRow(
          label: context.t('legal.termsOfService'),
          icon: LucideIcons.scrollText,
          trailing: IconButton(
            icon: const Icon(LucideIcons.externalLink, size: 18),
            onPressed: () => openTermsOfService(context),
          ),
        ),
        // Operator-configured external privacy notice (optional supplement to
        // the app's own policy above).
        if ((config.meta?.privacyPolicyUrl ?? '').isNotEmpty) ...[
          Divider(height: 1, color: AppColors.hairline2),
          SettingRow(
            label: context.t('settings.privacyPolicyExternal'),
            icon: LucideIcons.externalLink,
            trailing: IconButton(
              icon: const Icon(LucideIcons.externalLink, size: 17),
              onPressed: () => launchUrl(
                Uri.parse(config.meta!.privacyPolicyUrl),
                mode: LaunchMode.externalApplication,
              ),
            ),
          ),
        ],
        Divider(height: 1, color: AppColors.hairline2),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            children: [
              _aboutRow(context.t('settings.appVersion'), config.appVersion),
              _aboutRow(
                context.t('settings.serverVersion'),
                config.meta?.serverVersion ?? '–',
              ),
              _aboutRow(
                context.t('settings.organization'),
                config.meta?.organizationName ?? '–',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _aboutRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: AppColors.inkSoft, fontSize: 13),
          ),
        ),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ],
    ),
  );

  // --- admin (top-level nav, admins only) -----------------------------------

  /// A standalone nav card on the wide layout that opens the Admin area —
  /// promoted out of the Appearance section to its own top-level entry.
  Widget _adminSection() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: _navTile(
        icon: LucideIcons.shieldUser,
        title: context.t('settings.adminArea'),
        subtitle: context.t('settings.adminAreaDesc'),
        onTap: () => context.go('/admin'),
      ),
    );
  }

  // --- data & privacy -------------------------------------------------------

  Widget _dataSection() {
    return AccountSection(
      icon: LucideIcons.fileText,
      title: context.t('account.data.title'),
      subtitle: context.t('account.data.subtitle'),
      children: [
        SettingRow(
          label: context.t('account.data.request'),
          description: context.t('account.data.requestDesc'),
          stack: context.isCompact,
          trailing: AccountActionButton(
            label: context.t('account.data.requestButton'),
            icon: LucideIcons.download,
            onPressed: _dataReport,
          ),
        ),
      ],
    );
  }

  // --- danger zone ----------------------------------------------------------

  Widget _dangerSection() {
    return AccountSection(
      icon: LucideIcons.triangleAlert,
      title: context.t('account.danger.title'),
      subtitle: context.t('account.danger.subtitle'),
      danger: true,
      children: [
        SettingRow(
          label: context.t('account.danger.delete'),
          description: context.t('account.danger.deleteDesc'),
          stack: context.isCompact,
          trailing: AccountActionButton(
            label: context.t('account.danger.deleteButton'),
            icon: LucideIcons.trash2,
            danger: true,
            onPressed: _deleteAccount,
          ),
        ),
      ],
    );
  }

  Widget _emptyRow(String message) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Text(
      message,
      style: TextStyle(fontSize: 12.5, color: AppColors.inkFaint),
    ),
  );

  // --- helpers --------------------------------------------------------------

  /// Locale-aware "Month Year" via the active Material localizations.
  String _monthYear(DateTime d) =>
      MaterialLocalizations.of(context).formatMonthYear(d);

  String _relative(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 2) return context.t('account.time.now');
    if (diff.inHours < 1) {
      return context.t('account.time.minutesAgo', count: diff.inMinutes);
    }
    if (diff.inDays < 1) {
      return context.t('account.time.hoursAgo', count: diff.inHours);
    }
    if (diff.inDays < 7) {
      return context.t('account.time.daysAgo', count: diff.inDays);
    }
    return context.t('account.time.weeksAgo', count: (diff.inDays / 7).floor());
  }

  Color _parseHex(String hex) {
    final clean = hex.replaceAll('#', '');
    final value = int.tryParse(
      clean.length == 6 ? 'FF$clean' : clean,
      radix: 16,
    );
    return value == null ? AppColors.stTodo : Color(value);
  }
}

/// The row that opens the rest of the device list, and closes it again.
///
/// A row rather than a button floating beside the section header: it is the
/// continuation of the list it belongs to, and reads as the next item — which
/// is exactly what pressing it produces.
class _SessionsExpander extends StatelessWidget {
  const _SessionsExpander({
    required this.label,
    required this.busy,
    required this.expanded,
    required this.onPressed,
  });

  final String label;

  /// Whether the rest of the list is still on its way.
  final bool busy;

  /// Which way the chevron points: down to reveal, up to collapse.
  final bool expanded;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: busy ? null : onPressed,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (busy)
            const HiveLoader(size: 16, strokeWidth: 2)
          else
            Icon(
              expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
              size: 16,
              color: AppColors.accentStrong,
            ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.accentStrong,
            ),
          ),
        ],
      ),
    ),
  );
}
