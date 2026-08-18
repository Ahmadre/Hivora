import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:hinata/features/issues/issue_form.dart' show showIssueForm;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/blocs/auth_bloc.dart';
import '../../core/blocs/fetch_cubit.dart';
import '../../core/blocs/theme_cubit.dart';
import '../../core/events/issue_events.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/content_models.dart';
import '../../core/models/core_models.dart';
import '../../core/notifications/notification_swipe.dart';
import '../../core/notifications/notification_visuals.dart';
import '../../core/repositories/notification_repository.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ambient_background.dart';
import '../../core/widgets/hex_mark.dart';
import '../../core/widgets/honeycomb_background.dart';
import '../../core/widgets/app_avatar.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show
        ProgressiveBlur,
        ProgressiveBlurDirection,
        GlassAppBar,
        GlassTabBar,
        GlassTab,
        GlassButton,
        GlassContainer,
        GlassPopover,
        GlassQuality,
        LiquidGlassSettings,
        LiquidRoundedSuperellipse;
import '../../core/api/api_client.dart' show ApiFailure;
import '../../core/models/account_models.dart' show Me;
import '../../core/repositories/account_repository.dart';
import '../../core/widgets/frosted_surface.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/hive_loader.dart';
import '../account/account_modals.dart' show showEditProfile;
import '../search/global_search_dialog.dart';
import '../search/search_tokens.dart';
import '../sprint/modals/glass_modal.dart'
    show showGlassOptions, showGlassToast, GlassToastKind;
import 'page_chrome.dart';
import 'swipe_back.dart';

part 'app_shell.wide.dart';
part 'app_shell.notifications.dart';
part 'app_shell.compact.dart';

class _Destination {
  const _Destination(this.route, this.labelKey, this.icon);

  final String route;
  final String labelKey;
  final IconData icon;
}

const _primary = [
  _Destination('/dashboard', 'nav.dashboard', LucideIcons.layoutDashboard),
  _Destination('/teams', 'nav.teams', LucideIcons.usersRound),
  _Destination('/projects', 'nav.projects', LucideIcons.folder),
  _Destination('/issues', 'nav.issues', LucideIcons.circleCheckBig),
  _Destination('/board', 'nav.board', LucideIcons.squareKanban),
];

const _secondary = [
  _Destination('/watched', 'nav.watched', LucideIcons.eye),
  _Destination('/gantt', 'nav.gantt', LucideIcons.chartColumnStacked),
  _Destination('/timesheet', 'nav.timesheet', LucideIcons.table),
  _Destination('/reports', 'nav.reports', LucideIcons.chartLine),
  _Destination('/knowledge', 'nav.knowledge', LucideIcons.bookOpen),
];

const _bottomTabs = [
  _Destination('/dashboard', 'nav.dashboard', LucideIcons.layoutDashboard),
  _Destination('/issues', 'nav.issues', LucideIcons.circleCheckBig),
  _Destination('/board', 'nav.board', LucideIcons.squareKanban),
  _Destination('/more', 'nav.more', LucideIcons.layoutGrid),
];

// ── Floating bottom-nav glass presets ───────────────────────────────────────
// The mobile nav is two *separate* floating glass elements (the tab pill and a
// detached search button, iOS-26 style). Both must refract identically, so they
// share one preset. Values mirror the package's kBottomBarGlassDefaults; the
// glass is tinted translucent-black in dark mode (so it doesn't turn milky) and
// translucent-white in light mode (clean frost).
const kNavGlassDark = LiquidGlassSettings(
  thickness: 30,
  blur: 3,
  chromaticAberration: 0.3,
  lightIntensity: 0.6,
  refractiveIndex: 1.59,
  saturation: 0.7,
  ambientStrength: 1,
  lightAngle: 2.356194490192345, // 0.75π — Apple key light
  glassColor: Color(0x4D0A0A0A),
);
const kNavGlassLight = LiquidGlassSettings(
  thickness: 30,
  blur: 3,
  chromaticAberration: 0.3,
  lightIntensity: 0.6,
  refractiveIndex: 1.59,
  saturation: 0.7,
  ambientStrength: 1,
  lightAngle: 2.356194490192345, // 0.75π — Apple key light
  glassColor: Color(0x3DFFFFFF),
);

bool get isNativeApp =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.macOS);

/// How the search-palette shortcut is spelled on this platform. [_onGlobalKey]
/// accepts ⌘ and Ctrl everywhere, but the hint has to name the key the user
/// actually has — a Windows or Linux keyboard has no ⌘.
String get searchShortcutLabel => switch (defaultTargetPlatform) {
  TargetPlatform.macOS || TargetPlatform.iOS => '⌘K',
  _ => 'Ctrl K',
};

/// Responsive scaffold:
/// • phone/compact (<987): Liquid-Glass floating bottom nav
/// • desktop/wide (≥987): persistent dark Navy rail on the left
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  // One controller per shell: sub-pages publish their title / back behaviour to
  // it (via [PageChrome]) and the top bars listen so they can render a back
  // button + the real page title instead of the brand mark.
  final _chrome = PageChromeController();

  @override
  void initState() {
    super.initState();
    // App-level ⌘K / Ctrl+K opens the global search palette (§4.5). A hardware
    // key handler is genuinely global and never disturbs widget focus.
    HardwareKeyboard.instance.addHandler(_onGlobalKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onGlobalKey);
    _chrome.dispose();
    super.dispose();
  }

  bool _onGlobalKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.keyK) return false;
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final meta =
        keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight);
    final ctrl =
        keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight);
    if (!meta && !ctrl) return false;
    // Don't stack a second palette (or open one over another modal).
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return false;
    openGlobalSearch(context);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // The shell is persistent (it outlives route changes) and paints
    // theme-aware surfaces by reading AppColors' static getters — which don't
    // trigger rebuilds on their own. Subscribe to the inputs that resolve the
    // active brightness so the whole shell subtree re-runs build (and re-reads
    // AppColors) the moment the theme flips: the chosen ThemeMode, plus the OS
    // brightness for ThemeMode.system.
    context.watch<ThemeCubit>();
    MediaQuery.platformBrightnessOf(context);
    // `widget.location` (from the ShellRoute builder's state) goes STALE after
    // an imperative `push` of a nested route — it keeps reporting the underlying
    // page (e.g. `/board`) while a pushed `/issues/:id` is on screen, so the top
    // bar shows the wrong title/brand mark and never treats it as a sub-page.
    // Read the live location straight from the router instead, rebuilding when
    // it changes.
    final router = GoRouter.of(context);
    return PageChromeScope(
      controller: _chrome,
      child: BackButtonListener(
        onBackButtonPressed: _onSystemBack,
        child: ListenableBuilder(
          listenable: router.routerDelegate,
          builder: (context, _) {
            final location = router.state.matchedLocation;
            // In-app swipe-back: an edge drag on the content area unwinds
            // navigation through the same chain as the system back gesture.
            final content = SwipeBackGesture(
              enabled: _canSwipeBack,
              onBack: () => _onSystemBack(),
              child: widget.child,
            );
            return ResponsiveBuilder(
              builder: (context, size) {
                // The full-screen single-issue view is immersive on compact: its
                // own top bar (back/minimize/delete) + docked composer replace the
                // shell's app bar and floating nav.
                final immersive =
                    size == LayoutSize.compact && _isImmersive(location);
                return size == LayoutSize.compact
                    ? _CompactShell(
                        location: location,
                        immersive: immersive,
                        child: content,
                      )
                    : _WideShell(location: location, child: content);
              },
            );
          },
        ),
      ),
    );
  }

  /// Routes the system back (Android back button / edge-swipe gesture) through
  /// the same fallback chain as the shell's on-screen back button instead of
  /// letting it close the app: pop whatever sits on a navigator stack (pushed
  /// pages, dialogs), then a page-published in-page back override (e.g. the
  /// settings/admin section → index step), then the sub-page's parent route,
  /// then home. Only on /dashboard with nothing left to unwind does the system
  /// take over and background the app.
  /// Whether the swipe-back gesture has anywhere to go right now: something
  /// on a navigator stack, an in-page back override, or a sub-page's parent
  /// route. Primary tabs (dashboard, issues, board, …) don't swipe — the
  /// gesture is for unwinding, not for jumping between tabs.
  bool _canSwipeBack() {
    final router = GoRouter.of(context);
    if (router.canPop()) return true;
    final location = router.state.matchedLocation;
    return _chrome.onBackFor(location) != null ||
        _subPageTitleKey(location) != null;
  }

  Future<bool> _onSystemBack() async {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
      return true;
    }
    final location = router.state.matchedLocation;
    final override = _chrome.onBackFor(location);
    if (override != null) {
      override();
      return true;
    }
    if (_subPageTitleKey(location) != null) {
      router.go(_subPageBackRoute(location));
      return true;
    }
    if (location != '/dashboard') {
      router.go('/dashboard');
      return true;
    }
    return false;
  }
}

/// Whether [location] is a route that takes over the whole compact screen — no
/// shell app bar, no floating nav — because it renders its own full-screen
/// chrome. The full-page issue view (`/issues/:id`) is the case today.
bool _isImmersive(String location) => location.startsWith('/issues/');

// ─────────────────────────── Sub-page chrome ──────────────────────────────
// A "sub-page" is any route that isn't a primary nav destination — its top bar
// shows a back button + the page's own title instead of the brand mark + the
// nav-derived breadcrumb. The i18n key here is only a fallback; pages with a
// dynamic title (an issue, an article, a board…) override it through
// [PageChrome].

/// Fallback title key for a sub-page route, or null if [location] is a primary
/// nav destination (dashboard, projects, issues, board, …).
String? _subPageTitleKey(String location) {
  if (location == '/admin') return 'admin.title';
  if (location.startsWith('/admin/users')) return 'admin.users';
  if (location == '/notifications') return 'nav.notifications';
  if (location == '/weekly-summary') return 'weeklySummary.title';
  if (location == '/settings') return 'nav.settings';
  if (location.startsWith('/issues/')) return 'nav.issues';
  if (location.startsWith('/knowledge/')) return 'nav.knowledge';
  if (location.startsWith('/boards/')) return 'nav.board';
  if (location.startsWith('/projects/')) return 'board.boards';
  if (location.startsWith('/teams/')) return 'nav.teams';
  return null;
}

/// Parent route to fall back to when a sub-page can't simply pop (e.g. opened
/// via a deep link with nothing on the navigation stack).
String _subPageBackRoute(String location) {
  if (location.startsWith('/admin/users')) return '/admin';
  if (location == '/admin') return '/settings';
  if (location.startsWith('/issues/')) return '/issues';
  if (location.startsWith('/knowledge/')) return '/knowledge';
  if (location.startsWith('/boards/')) return '/board';
  if (location.startsWith('/projects/')) return '/projects';
  if (location.startsWith('/teams/')) return '/teams';
  return '/dashboard';
}

/// Resolves the back action for a sub-page: a page-supplied [override] wins,
/// otherwise pop the stack, otherwise jump to the parent route.
void _handleBack(
  BuildContext context,
  String location,
  VoidCallback? override,
) {
  if (override != null) {
    override();
  } else if (context.canPop()) {
    context.pop();
  } else {
    context.go(_subPageBackRoute(location));
  }
}

// Maps the current location to the nav route that should appear active.
// /boards/:id      → /board (Board nav item)
// /projects/:id/*  → /projects (Projects nav item)
bool _isActive(String location, String navRoute) {
  if (navRoute == '/board') {
    return location.startsWith('/board') || location.startsWith('/boards/');
  }
  if (navRoute == '/projects') {
    return location.startsWith('/projects');
  }
  if (navRoute == '/teams') {
    return location.startsWith('/teams');
  }
  return location.startsWith(navRoute);
}
