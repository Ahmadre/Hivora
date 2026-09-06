import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassContainer, GlassQuality, LiquidRoundedSuperellipse;
import '../../core/widgets/hive_loader.dart';
import '../../core/branding/org_logo.dart';
import '../../core/widgets/hex_mark.dart';
import '../../core/widgets/glass_panel.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/repositories/admin_repository.dart';
import '../../core/i18n/i18n.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../search/search_tokens.dart';
import '../shell/page_chrome.dart';
import '../sprint/modals/glass_modal.dart'
    show showGlassToast, showGlassErrorToast, GlassToastKind;
import 'admin_sso_section.dart';
import 'sections/admin_app_section.dart';
import 'sections/admin_audit_section.dart';
import 'sections/admin_connect_section.dart';
import 'sections/admin_email_section.dart';
import 'sections/admin_general_section.dart';
import 'sections/admin_git_section.dart';
import 'sections/admin_mcp_section.dart';
import 'sections/admin_security_section.dart';
import '../../core/widgets/hive_widgets.dart' show forwardChevron;

// ─────────────────────────── Section enum ────────────────────────────────

enum _AdminSection {
  general,
  app,
  authentication,
  connect,
  email,
  git,
  mcp,
  security,
  auditLog,
  users,
}

// Metadata for a nav entry.
typedef _SectionMeta = ({
  _AdminSection section,
  IconData icon,
  String labelKey,
  String group,
});

const _navItems = <_SectionMeta>[
  (
    section: _AdminSection.general,
    icon: LucideIcons.building2,
    labelKey: 'admin.general',
    group: 'navGeneral',
  ),
  (
    section: _AdminSection.app,
    icon: LucideIcons.smartphone,
    labelKey: 'admin.app',
    group: 'navGeneral',
  ),
  (
    section: _AdminSection.security,
    icon: LucideIcons.shield,
    labelKey: 'admin.security',
    group: 'navGeneral',
  ),
  (
    section: _AdminSection.authentication,
    icon: LucideIcons.lock,
    labelKey: 'admin.authentication',
    group: 'navIntegrations',
  ),
  (
    section: _AdminSection.connect,
    icon: LucideIcons.radioTower,
    labelKey: 'admin.connect',
    group: 'navIntegrations',
  ),
  (
    section: _AdminSection.email,
    icon: LucideIcons.mail,
    labelKey: 'admin.email',
    group: 'navIntegrations',
  ),
  (
    section: _AdminSection.git,
    icon: LucideIcons.gitBranch,
    labelKey: 'admin.gitIntegration',
    group: 'navIntegrations',
  ),
  (
    section: _AdminSection.mcp,
    icon: LucideIcons.plug,
    labelKey: 'admin.mcp',
    group: 'navIntegrations',
  ),
  (
    section: _AdminSection.auditLog,
    icon: LucideIcons.history,
    labelKey: 'admin.auditLog',
    group: 'navSystem',
  ),
  (
    section: _AdminSection.users,
    icon: LucideIcons.users,
    labelKey: 'admin.users',
    group: 'navSystem',
  ),
];

// ─────────────────────────── Root screen ─────────────────────────────────

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key, this.initialSection});

  /// Optional section to open on entry (e.g. a deep link `/admin?section=connect`).
  /// Matched against the [_AdminSection] enum names.
  final String? initialSection;

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  Map<String, dynamic>? _settings;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  // Desktop: which section is shown in the right pane.
  _AdminSection _desktopSection = _AdminSection.general;

  // Mobile: when non-null, the detail view is shown instead of the list.
  _AdminSection? _mobileSection;

  @override
  void initState() {
    super.initState();
    _applyInitialSection();
    _load();
  }

  /// Preselects the section named by [AdminScreen.initialSection] (deep link).
  /// Sets both the desktop and mobile targets so the right one is honoured once
  /// the layout resolves at build time. `users` opens its own screen, so it is
  /// left to the normal tap flow.
  void _applyInitialSection() {
    final name = widget.initialSection;
    if (name == null || name.isEmpty) return;
    for (final s in _AdminSection.values) {
      if (s != _AdminSection.users && s.name == name) {
        _desktopSection = s;
        _mobileSection = s;
        return;
      }
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _settings = await context.read<AdminRepository>().adminSettings();
      if (!mounted) return;
      setState(() => _loading = false);
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = failure.message;
      });
    } catch (_) {
      // A malformed 200 payload (e.g. a cast error, an HTML proxy page) throws
      // outside ApiFailure — surface the generic error + Retry instead of
      // getting stuck on the loader forever.
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'errors.unexpected';
      });
    }
  }

  Future<void> _save() async {
    if (_settings == null) return;
    setState(() => _saving = true);
    try {
      _settings = await context.read<AdminRepository>().updateAdminSettings(
        _settings!,
      );
      if (mounted) {
        showGlassToast(
          context,
          context.t('admin.saved'),
          kind: GlassToastKind.success,
        );
      }
    } on ApiFailure catch (failure) {
      if (mounted) {
        showGlassErrorToast(context, context.t(failure.message));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _selectSection(_AdminSection sec, {required bool mobile}) {
    if (sec == _AdminSection.users) {
      context.push('/admin/users');
      return;
    }
    if (mobile) {
      setState(() => _mobileSection = sec);
    } else {
      setState(() => _desktopSection = sec);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: HiveLoader());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.cloudOff, size: 48, color: AppColors.inkFaint),
            const SizedBox(height: 12),
            Text(
              context.t(_error!),
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _load,
              child: Text(context.t('common.retry')),
            ),
          ],
        ),
      );
    }

    final settings = _settings!;

    return ResponsiveBuilder(
      builder: (context, size) {
        if (size == LayoutSize.compact) {
          // Mobile: list ↔ detail in-app navigation. Both steps live on the
          // same /admin route, so the shell's back button is wired through
          // PageChrome: in the detail it returns to the list, in the list it
          // pops back to where admin was opened from.
          final current = _mobileSection;
          if (current != null) {
            // The audit log docks its filter bar into the app bar, so it owns
            // its own PageChrome (title + back); everything else uses the shared
            // wrapper here.
            if (current == _AdminSection.auditLog) {
              return AdminAuditSection(
                onBack: () => setState(() => _mobileSection = null),
              );
            }
            return PageChrome(
              title: context.t(_sectionTitleKey(current)),
              onBack: () => setState(() => _mobileSection = null),
              actions: _saveActions(context, current),
              child: _MobileDetailView(section: current, settings: settings),
            );
          }
          return PageChrome(
            title: context.t('admin.title'),
            child: _MobileListView(
              onSelect: (sec) => _selectSection(sec, mobile: true),
            ),
          );
        }

        // Desktop / tablet: split panel. The section title + Save action ride
        // in the shell's glass app bar (via PageChrome) — the pane draws no
        // header chrome of its own.
        return PageChrome(
          title: context.t(_sectionTitleKey(_desktopSection)),
          actions: _saveActions(context, _desktopSection),
          child: _WideAdminShell(
            section: _desktopSection,
            settings: settings,
            onSectionChanged: (s) => _selectSection(s, mobile: false),
          ),
        );
      },
    );
  }

  /// The Save action published into the glass app bar — omitted for sections
  /// that manage their own persistence (audit log, connect).
  List<PageAction> _saveActions(BuildContext context, _AdminSection section) {
    if (!_sectionHasSave(section)) return const [];
    return [
      PageAction(
        icon: LucideIcons.save,
        label: context.t('common.save'),
        onTap: _save,
        primary: true,
        busy: _saving,
      ),
    ];
  }
}

/// Connect + audit log manage themselves (no shared settings draft to save), so
/// they surface no Save action.
bool _sectionHasSave(_AdminSection section) =>
    section != _AdminSection.auditLog && section != _AdminSection.connect;

/// i18n key for an admin section's title (shared by the shell app bar and the
/// in-pane section header).
String _sectionTitleKey(_AdminSection section) => switch (section) {
  _AdminSection.general => 'admin.general',
  _AdminSection.app => 'admin.app',
  _AdminSection.authentication => 'admin.authentication',
  _AdminSection.connect => 'admin.connect',
  _AdminSection.email => 'admin.email',
  _AdminSection.git => 'admin.gitIntegration',
  _AdminSection.mcp => 'admin.mcp',
  _AdminSection.security => 'admin.security',
  _AdminSection.auditLog => 'admin.auditLog',
  _AdminSection.users => 'admin.users',
};

// ─────────────────────────── Mobile: list view ───────────────────────────

class _MobileListView extends StatelessWidget {
  const _MobileListView({required this.onSelect});

  final ValueChanged<_AdminSection> onSelect;

  @override
  Widget build(BuildContext context) {
    // Group nav items
    final groups = <String, List<_SectionMeta>>{};
    for (final item in _navItems) {
      groups.putIfAbsent(item.group, () => []).add(item);
    }

    return CustomScrollView(
      slivers: [
        // The app bar already names "Adminbereich"; open with a short intro line
        // instead of a duplicate title, cleared of the glass bar by topGutter.
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 16 + context.topGutter, 20, 0),
            child: Text(
              context.t('admin.subtitle'),
              style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
            ),
          ),
        ),
        for (final entry in groups.entries) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
              child: Text(
                context.t('admin.${entry.key}').toUpperCase(),
                style: TextStyle(
                  fontFamily: AppTheme.fontMono,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkFaint,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                border: Border.all(color: AppColors.hairline),
              ),
              child: Column(
                children: [
                  for (int i = 0; i < entry.value.length; i++) ...[
                    if (i > 0)
                      Divider(height: 1, indent: 56, color: AppColors.hairline),
                    _MobileNavTile(
                      meta: entry.value[i],
                      onTap: () => onSelect(entry.value[i].section),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
        SliverToBoxAdapter(child: SizedBox(height: 32 + context.bottomGutter)),
      ],
    );
  }
}

class _MobileNavTile extends StatelessWidget {
  const _MobileNavTile({required this.meta, required this.onTap});

  final _SectionMeta meta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isUsers = meta.section == _AdminSection.users;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(meta.icon, size: 17, color: AppColors.accentStrong),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  context.t(meta.labelKey),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.ink,
                  ),
                ),
              ),
              Icon(
                isUsers ? LucideIcons.externalLink : forwardChevron(context),
                size: 18,
                color: AppColors.inkFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── Mobile: detail view ─────────────────────────

class _MobileDetailView extends StatelessWidget {
  const _MobileDetailView({required this.section, required this.settings});

  final _AdminSection section;
  final Map<String, dynamic> settings;

  @override
  Widget build(BuildContext context) {
    // Back + title + Save all ride in the shell's glass app bar (via
    // PageChrome). This view is just the scrolling body, cleared of the glass
    // bar by topGutter. The audit log owns its own scroll + pagination, so it
    // renders directly; every other section uses the shared scroll wrapper.
    if (section == _AdminSection.auditLog) return const AdminAuditSection();
    // The iOS numeric keypad has no Done key, so give the admin forms two ways
    // out of it: tap anywhere outside a field, or drag-scroll the body.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          16,
          16 + context.topGutter,
          16,
          16 + context.bottomGutter,
        ),
        child: _sectionBody(section),
      ),
    );
  }

  Widget _sectionBody(_AdminSection sec) => switch (sec) {
    _AdminSection.general => AdminGeneralSection(settings: settings),
    _AdminSection.app => AdminAppSection(settings: settings),
    _AdminSection.authentication => AdminSsoSection(settings: settings),
    _AdminSection.connect => const AdminConnectSection(),
    _AdminSection.email => AdminEmailSection(settings: settings),
    _AdminSection.git => AdminGitSection(settings: settings),
    _AdminSection.mcp => AdminMcpSection(settings: settings),
    _AdminSection.security => AdminSecuritySection(settings: settings),
    // Rendered directly by the shell (self-scrolling); never reached here.
    _AdminSection.auditLog => const SizedBox.shrink(),
    _AdminSection.users => const SizedBox.shrink(),
  };
}

// ─────────────────────────── Wide layout (≥ medium) ──────────────────────

/// Widest the settings forms are allowed to stretch — beyond this, fields read
/// as sparse. The audit log opts out and fills the full pane (dense timeline).
const double _kAdminContentMax = 1400;

class _WideAdminShell extends StatelessWidget {
  const _WideAdminShell({
    required this.section,
    required this.settings,
    required this.onSectionChanged,
  });

  final _AdminSection section;
  final Map<String, dynamic> settings;
  final ValueChanged<_AdminSection> onSectionChanged;

  @override
  Widget build(BuildContext context) {
    final gutter = context.pageGutter;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1618),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Floating glass nav rail ───────────────────────────
              Padding(
                padding: EdgeInsets.fromLTRB(
                  0,
                  context.topGutter + 14,
                  18,
                  context.bottomGutter + 14,
                ),
                child: SizedBox(
                  width: 250,
                  child: _AdminNavRail(
                    section: section,
                    onSelect: onSectionChanged,
                  ),
                ),
              ),
              // ── Content pane (no header chrome — that's in the app bar) ──
              Expanded(child: _content(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    // The audit log owns its own scroll + pagination and wants the full pane.
    if (section == _AdminSection.auditLog) {
      return Padding(
        padding: EdgeInsets.only(top: context.topGutter + 14),
        child: const AdminAuditSection(),
      );
    }
    // The iOS numeric keypad has no Done key, so — as on the compact path —
    // give the wide/iPad forms tap-outside-to-dismiss on top of drag-scroll.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          0,
          context.topGutter + 14,
          0,
          context.bottomGutter + 28,
        ),
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kAdminContentMax),
            child: _body(),
          ),
        ),
      ),
    );
  }

  Widget _body() => switch (section) {
    _AdminSection.general => AdminGeneralSection(settings: settings),
    _AdminSection.app => AdminAppSection(settings: settings),
    _AdminSection.authentication => AdminSsoSection(settings: settings),
    _AdminSection.connect => const AdminConnectSection(),
    _AdminSection.email => AdminEmailSection(settings: settings),
    _AdminSection.git => AdminGitSection(settings: settings),
    _AdminSection.mcp => AdminMcpSection(settings: settings),
    _AdminSection.security => AdminSecuritySection(settings: settings),
    // Rendered directly (self-scrolling); never reached here.
    _AdminSection.auditLog => const SizedBox.shrink(),
    _AdminSection.users => const SizedBox.shrink(),
  };
}

// ─────────────────────────── Glass nav rail ──────────────────────────────

/// Ambient shadow for the *docked* nav rail. Deliberately NOT the search
/// palette's `panelShadow` — that one is tuned for a modal floating mid-screen
/// (a ~60px side penumbra + heavy downward smear) and, on a rail docked one
/// [pageGutter] from the content-clip edge, its left half gets chopped into a
/// hard vertical line. These keep the horizontal bleed (≈ blur − spread ≤ 22px)
/// inside the gutter so the float reads cleanly at every width, light or dark.
const List<BoxShadow> _kRailShadowLight = [
  BoxShadow(
    color: Color.fromRGBO(20, 18, 45, 0.13),
    offset: Offset(0, 12),
    blurRadius: 30,
    spreadRadius: -10,
  ),
  BoxShadow(
    color: Color.fromRGBO(20, 18, 45, 0.07),
    offset: Offset(0, 2),
    blurRadius: 8,
    spreadRadius: -3,
  ),
];

const List<BoxShadow> _kRailShadowDark = [
  BoxShadow(
    color: Color.fromRGBO(0, 0, 0, 0.40),
    offset: Offset(0, 14),
    blurRadius: 34,
    spreadRadius: -14,
  ),
  BoxShadow(
    color: Color.fromRGBO(0, 0, 0, 0.28),
    offset: Offset(0, 2),
    blurRadius: 8,
    spreadRadius: -4,
  ),
];

/// The desktop nav rail: a floating liquid-glass panel (refracting the ambient
/// canvas behind it) with a brand header + grouped, amber-active section list.
class _AdminNavRail extends StatelessWidget {
  const _AdminNavRail({required this.section, required this.onSelect});

  final _AdminSection section;
  final ValueChanged<_AdminSection> onSelect;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tokens = SearchTokens.of(dark ? Brightness.dark : Brightness.light);

    final groups = <String, List<_SectionMeta>>{};
    for (final item in _navItems) {
      groups.putIfAbsent(item.group, () => []).add(item);
    }

    return GlassPanelShadow(
      radius: BorderRadius.circular(24),
      shadows: dark ? _kRailShadowDark : _kRailShadowLight,
      child: GlassContainer(
        useOwnLayer: true,
        quality: GlassQuality.premium,
        clipBehavior: Clip.antiAlias,
        shape: const LiquidRoundedSuperellipse(borderRadius: 24),
        settings: liquidGlassPanelSettings(
          glassFill: tokens.glassFill,
          dark: dark,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 16, 15),
                child: Row(
                  children: [
                    // The admin console is where the logo is configured, two
                    // clicks away — showing it here closes that loop. The rail
                    // is a fixed 250 px, so the mark is capped well short of
                    // the width the title beside it needs.
                    const OrgLogo(
                      height: 26,
                      maxWidth: 68,
                      fallback: HexMark(size: 26),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.t('admin.title'),
                            style: TextStyle(
                              fontFamily: AppTheme.fontBrand,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                              color: tokens.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            context.t('admin.subtitle'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.25,
                              color: tokens.inkSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: tokens.hairline),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 14),
                  children: [
                    for (final entry in groups.entries) ...[
                      _NavGroup(
                        label: context.t('admin.${entry.key}'),
                        color: tokens.inkFaint,
                      ),
                      for (final meta in entry.value)
                        _NavItem(
                          meta: meta,
                          current: section,
                          onTap: onSelect,
                          tokens: tokens,
                        ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── Nav widgets ─────────────────────────────────

class _NavGroup extends StatelessWidget {
  const _NavGroup({required this.label, this.color});
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontFamily: AppTheme.fontMono,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color ?? AppColors.inkFaint,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.meta,
    required this.current,
    required this.onTap,
    required this.tokens,
  });

  final _SectionMeta meta;
  final _AdminSection current;
  final ValueChanged<_AdminSection> onTap;
  final SearchTokens tokens;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final active = meta.section == current;
    final isUsers = meta.section == _AdminSection.users;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          onTap: () => onTap(meta.section),
          borderRadius: BorderRadius.circular(11),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.fromLTRB(9, 9, 12, 9),
            decoration: BoxDecoration(
              color: active
                  ? AppColors.accent.withValues(alpha: dark ? 0.22 : 0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Row(
              children: [
                // A short amber bar flags the active section.
                Container(
                  width: 3,
                  height: 18,
                  decoration: BoxDecoration(
                    color: active ? AppColors.accentStrong : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  meta.icon,
                  size: 17,
                  color: active ? AppColors.accentStrong : tokens.inkSoft,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    context.t(meta.labelKey),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                      color: active ? AppColors.accentStrong : tokens.ink,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isUsers)
                  Icon(
                    LucideIcons.externalLink,
                    size: 12,
                    color: tokens.inkFaint,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
