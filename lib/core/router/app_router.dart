import 'dart:async';

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/account/account_screen.dart';
import '../../features/admin/admin_screen.dart';
import '../../features/admin/users/user_management_screen.dart';
import '../../features/auth/accept_invite_screen.dart';
import '../../features/auth/forgot_password_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/auth/reset_password_screen.dart';
import '../../features/auth/sso_callback_screen.dart';
import '../../features/auth/verify_email_screen.dart';
import '../../features/board/board_screen.dart';
import '../../features/board/project_boards_screen.dart';
import '../../features/connect/connect_screen.dart';
import '../../features/connect/connecting_screen.dart';
import '../../features/connect/update_required_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/gantt/gantt_screen.dart';
import '../../features/issues/email_reply/email_reply_sheet.dart'
    show EmailReplyRouteArgs, EmailReplyScreen;
import '../../features/issues/issue_detail_screen.dart';
import '../../features/issues/issue_detail_sheet.dart' show IssueRouteArgs;
import '../../features/issues/issue_filter.dart' show IssuesInitialView;
import '../../features/issues/issues_screen.dart';
import '../../features/issues/watched_issues_screen.dart';
import '../../features/knowledge/knowledge_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/oauth/oauth_consent_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/projects/projects_screen.dart';
import '../../features/projects/settings/project_settings_screen.dart';
import '../../features/reports/reports_screen.dart';
import '../../features/setup/setup_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../features/teams/team_detail_screen.dart';
import '../../features/teams/teams_screen.dart';
import '../../features/timesheet/timesheet_screen.dart';
import '../../features/weekly_summary/weekly_summary_screen.dart';
import '../blocs/app_config_bloc.dart';
import '../blocs/auth_bloc.dart';
import '../storage/app_storage.dart';

/// The root navigator, exposed so code that has no [BuildContext] can still
/// push a route — currently the desktop camera delegate, which image_picker
/// calls from a plain `Future` with no widget tree in reach.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Re-evaluates router redirects whenever one of the given streams emits.
class _MergedRefresh extends ChangeNotifier {
  _MergedRefresh(List<Stream<dynamic>> streams) {
    for (final stream in streams) {
      _subscriptions.add(stream.listen((_) => notifyListeners()));
    }
  }

  final List<StreamSubscription<dynamic>> _subscriptions = [];

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }
}

/// Where the router sends the user while the app is still booting, and the one
/// parking slot that carries a deep-linked destination across that boot.
///
/// A deep link (an e-mail link, a tapped push notification, an SSO callback)
/// almost always lands *before* the app is in any state to show it: the server
/// is still being verified, the session still being re-checked. The router
/// bounces such a request onto a gate screen — and unless the destination is
/// remembered here, it is simply gone, which from the outside looks exactly
/// like "I opened the link and the app did nothing".
///
/// Extracted from [buildRouter] with no widget tree attached, because the boot
/// orderings this has to survive are the whole point and a screen-less unit test
/// is the only way to walk through all of them.
@visibleForTesting
class BootGate {
  /// Screens the user is bounced through while the app boots (connects,
  /// onboards, authenticates) — never a deep-link destination in their own
  /// right, so they are never parked and never restored.
  static const gates = {
    '/connect',
    '/connecting',
    '/setup',
    '/onboarding',
    '/login',
    '/update',
    '/auth-callback',
    '/register',
    '/forgot-password',
    '/verify-email',
  };

  /// The destination waiting for the app to become able to show it.
  String? pendingDeepLink;

  /// The location to redirect to, or null to let [location] render.
  String? redirect({
    required String location,
    required String uri,
    required AppConfigStatus config,
    required AuthStatus auth,
    required bool hasServerUrl,
    required bool onboardingDone,
  }) {
    // Remember a real (non-gate) destination that we're about to bounce off a
    // gate, so we can return to it once the app is ready + authenticated.
    void parkIfDeepLink() {
      if (!gates.contains(location) && location != '/dashboard') {
        pendingDeepLink = uri;
      }
    }

    // The SSO callback carries a one-time token pair in its query string.
    // On a web login the whole app reloads at this URL, so AppConfig is still
    // (re)connecting — without this guard the config switch below would bounce
    // us to /connect and discard the tokens before SsoCallbackScreen reads
    // them. Hold the route until the tokens have signed the user in.
    if (location == '/auth-callback' && auth != AuthStatus.authenticated) {
      return null;
    }

    // The invite + password-reset deep links are self-contained public flows
    // (validate token → set password → auto-sign-in). Let them render
    // regardless of config/auth state; they set the server URL from the link
    // and navigate on themselves.
    if (location == '/invite' ||
        location == '/reset-password' ||
        location == '/verify-email') {
      return null;
    }

    switch (config) {
      case AppConfigStatus.initial:
      case AppConfigStatus.connecting:
        // No server chosen yet → URL-entry screen. Otherwise (boot with a
        // saved server, or a deliberate server switch) show a brief branded
        // splash rather than flashing the connect form.
        if (!hasServerUrl) {
          if (location == '/connect') return null;
          parkIfDeepLink();
          return '/connect';
        }
        if (location == '/connecting') return null;
        parkIfDeepLink();
        return '/connecting';
      case AppConfigStatus.needsServerUrl:
        if (location == '/connect') return null;
        parkIfDeepLink();
        return '/connect';
      case AppConfigStatus.updateRequired:
        if (location == '/update') return null;
        parkIfDeepLink();
        return '/update';
      case AppConfigStatus.needsSetup:
        if (location == '/setup') return null;
        parkIfDeepLink();
        return '/setup';
      case AppConfigStatus.ready:
        break;
    }
    if (!onboardingDone) {
      if (location == '/onboarding') return null;
      parkIfDeepLink();
      return '/onboarding';
    }
    if (auth != AuthStatus.authenticated) {
      // /auth-callback carries the SSO token pair and signs the user in;
      // /register + /forgot-password are the public logged-out auth flows.
      const allowed = {
        '/login',
        '/auth-callback',
        '/register',
        '/forgot-password',
      };
      if (allowed.contains(location)) return null;
      parkIfDeepLink();
      return '/login';
    }
    // Authenticated and ready: hand back the parked deep link, wherever the
    // user is standing right now. Deliberately not limited to the gates: the
    // gates are where a link gets parked, but they are not the only place the
    // app can be when it finally settles. A link that arrives a beat after the
    // app is already home parks nothing and needs nothing; one that arrives
    // while a *later* boot step is still running (a server switch dropping
    // AppConfig back to `connecting`, a re-`AuthChecked` after it) is parked
    // from a location that is by then no longer a gate — and used to sit there
    // forever, which is exactly what "the app opens and does nothing" looked
    // like.
    final parked = pendingDeepLink;
    pendingDeepLink = null;
    if (parked != null && parked != uri) return parked;
    // Nothing parked: just keep the user off the gate screens.
    if (gates.contains(location)) return '/dashboard';
    return null;
  }
}

GoRouter buildRouter({
  required AppConfigBloc appConfig,
  required AuthBloc auth,
  required AppStorage storage,
}) {
  final bootGate = BootGate();

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: storage.screenshotRoute ?? '/dashboard',
    refreshListenable: _MergedRefresh([appConfig.stream, auth.stream]),
    redirect: (context, routerState) => bootGate.redirect(
      location: routerState.matchedLocation,
      uri: routerState.uri.toString(),
      config: appConfig.state.status,
      auth: auth.state.status,
      hasServerUrl: storage.serverUrl != null,
      onboardingDone: storage.onboardingDone,
    ),
    routes: [
      GoRoute(path: '/connect', builder: (_, _) => const ConnectScreen()),
      GoRoute(path: '/connecting', builder: (_, _) => const ConnectingScreen()),
      GoRoute(path: '/setup', builder: (_, _) => const SetupScreen()),
      GoRoute(
        path: '/update',
        builder: (context, _) => UpdateRequiredScreen(
          appVersion: appConfig.state.appVersion,
          minVersion: appConfig.state.meta?.minAppVersion ?? '',
          storeUrl: storeUrlForPlatform(appConfig.state.meta),
        ),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, _) => OnboardingScreen(
          storage: storage,
          onDone: () => GoRouter.of(context).go(
            auth.state.status == AuthStatus.authenticated
                ? '/dashboard'
                : '/login',
          ),
        ),
      ),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(
        path: '/forgot-password',
        builder: (_, _) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/verify-email',
        builder: (_, state) => VerifyEmailScreen(
          token: state.uri.queryParameters['token'] ?? '',
          server: state.uri.queryParameters['server'],
        ),
      ),
      GoRoute(
        path: '/invite',
        builder: (_, state) => AcceptInviteScreen(
          token: state.uri.queryParameters['token'] ?? '',
          server: state.uri.queryParameters['server'],
        ),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (_, state) => ResetPasswordScreen(
          token: state.uri.queryParameters['token'] ?? '',
          server: state.uri.queryParameters['server'],
        ),
      ),
      GoRoute(
        path: '/oauth-consent',
        builder: (_, state) => OAuthConsentScreen(
          requestId: state.uri.queryParameters['request_id'] ?? '',
        ),
      ),
      GoRoute(
        path: '/auth-callback',
        builder: (_, state) => SsoCallbackScreen(
          // A single-use handoff code, redeemed for tokens via a POST — the
          // bearer tokens are never carried in the URL. `access_token`/
          // `refresh_token` are still read as a fallback for older redirects.
          code: state.uri.queryParameters['code'],
          accessToken: state.uri.queryParameters['access_token'],
          refreshToken: state.uri.queryParameters['refresh_token'],
        ),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            pageBuilder: (_, state) =>
                _transition(state, const DashboardScreen()),
          ),
          GoRoute(
            path: '/projects',
            pageBuilder: (_, state) =>
                _transition(state, const ProjectsScreen()),
          ),
          GoRoute(
            path: '/projects/:id/settings',
            pageBuilder: (_, state) => _transition(
              state,
              ProjectSettingsScreen(projectId: state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: '/teams',
            pageBuilder: (_, state) => _transition(state, const TeamsScreen()),
          ),
          GoRoute(
            path: '/teams/:id',
            pageBuilder: (_, state) => _transition(
              state,
              TeamDetailScreen(teamId: state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: '/issues',
            pageBuilder: (_, state) {
              final projectId = state.uri.queryParameters['projectId'];
              final view = _issuesView(state.uri.queryParameters['view']);
              // Dashboard KPI deep-links carry the active project scope so the
              // Issues page shows exactly the set the card counted.
              final projectsCsv = state.uri.queryParameters['projects'] ?? '';
              final scope = projectsCsv.isEmpty
                  ? const <String>[]
                  : projectsCsv.split(',').where((s) => s.isNotEmpty).toList();
              // Key by the preset + scope so switching KPI deep-links always
              // yields a fresh screen (clean filter) instead of reusing the prior
              // state — go_router's pageKey ignores the query on its own.
              return _transition(
                state,
                IssuesScreen(
                  key: ValueKey(
                    'issues-${view?.name ?? 'all'}-${projectId ?? ''}-${scope.join(',')}',
                  ),
                  projectId: projectId,
                  initialView: view,
                  scopeProjectIds: scope,
                ),
              );
            },
          ),
          // Jira-familiar alias: /browse/ASTA-42 → the canonical issue detail
          // route. Everything (deep links, App Links / Universal Links) targets
          // /issues/*, so we redirect here rather than duplicating the screen.
          GoRoute(
            path: '/browse/:key',
            redirect: (_, state) => '/issues/${state.pathParameters['key']!}',
          ),
          GoRoute(
            path: '/issues/:id',
            pageBuilder: (_, state) {
              final args = state.extra is IssueRouteArgs
                  ? state.extra as IssueRouteArgs
                  : null;
              final id = state.pathParameters['id']!;
              return _transition(
                state,
                IssueDetailScreen(
                  // Key by the issue id so navigating issue→issue (e.g. global
                  // search while a fullscreen issue is open) always yields a
                  // fresh screen instead of reusing the prior State —
                  // go_router's pageKey is per-pattern and ignores :id.
                  key: ValueKey('issue-$id'),
                  issueId: id,
                  fromModal: args?.fromModal ?? false,
                  onChanged: args?.onChanged,
                  // Deep link `…/issues/ID?comment=<id>` scrolls to that comment.
                  targetCommentId: state.uri.queryParameters['comment'],
                ),
              );
            },
          ),
          // Maximized "Reply by email" composer — rendered inside the shell like
          // a maximized issue. Only reachable by promoting the reply sheet
          // (which carries the issue + draft via `extra`); a cold navigation
          // with no `extra` (e.g. a browser refresh) can't compose, so it
          // redirects to the issue itself.
          GoRoute(
            path: '/issues/:id/reply-email',
            redirect: (_, state) => state.extra is EmailReplyRouteArgs
                ? null
                : '/issues/${state.pathParameters['id']!}',
            pageBuilder: (_, state) {
              final args = state.extra as EmailReplyRouteArgs;
              return _transition(
                state,
                EmailReplyScreen(
                  key: ValueKey('reply-email-${state.pathParameters['id']}'),
                  issue: args.issue,
                  initialDraft: args.draft,
                  canMinimize: args.fromModal,
                ),
              );
            },
          ),
          GoRoute(
            path: '/board',
            pageBuilder: (_, state) => _transition(state, const BoardScreen()),
          ),
          GoRoute(
            path: '/boards/:id',
            pageBuilder: (_, state) => _transition(
              state,
              KanbanBoardScreen(boardId: state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: '/projects/:id/boards',
            pageBuilder: (_, state) => _transition(
              state,
              ProjectBoardsScreen(
                projectId: state.pathParameters['id']!,
                projectName: (state.extra as String?) ?? '',
              ),
            ),
          ),
          GoRoute(
            path: '/gantt',
            pageBuilder: (_, state) => _transition(state, const GanttScreen()),
          ),
          GoRoute(
            path: '/timesheet',
            pageBuilder: (_, state) =>
                _transition(state, const TimesheetScreen()),
          ),
          GoRoute(
            path: '/watched',
            pageBuilder: (_, state) =>
                _transition(state, const WatchedIssuesScreen()),
          ),
          GoRoute(
            path: '/reports',
            pageBuilder: (_, state) =>
                _transition(state, const ReportsScreen()),
          ),
          GoRoute(
            path: '/knowledge',
            pageBuilder: (_, state) =>
                _transition(state, const KnowledgeScreen()),
          ),
          GoRoute(
            path: '/knowledge/:id',
            pageBuilder: (_, state) => _transition(
              state,
              KnowledgeScreen(initialArticleId: state.pathParameters['id']),
            ),
          ),
          GoRoute(
            path: '/notifications',
            pageBuilder: (_, state) =>
                _transition(state, const NotificationsScreen()),
          ),
          GoRoute(
            path: '/weekly-summary',
            pageBuilder: (_, state) =>
                _transition(state, const WeeklySummaryScreen()),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (_, state) => _transition(
              state,
              AccountScreen(section: state.uri.queryParameters['section']),
            ),
          ),
          GoRoute(
            path: '/admin',
            pageBuilder: (_, state) => _transition(
              state,
              AdminScreen(initialSection: state.uri.queryParameters['section']),
            ),
          ),
          GoRoute(
            path: '/admin/users',
            pageBuilder: (_, state) => _transition(
              state,
              UserManagementScreen(
                // In-app links carry the focus user as `user`; the Connect relay
                // (native email deep-link) delivers it as the relay `token`.
                focusUserId:
                    state.uri.queryParameters['user'] ??
                    state.uri.queryParameters['token'],
              ),
            ),
          ),
        ],
      ),
    ],
  );
}

/// v2 page transition: a soft vertical "fade through" — content rises from
/// just below and fades in, with no overlap of the old and new pages.
///
/// Replaces the platform default (a horizontal Cupertino slide on macOS/desktop
/// where the new page flies in from the right and the old one slides out left,
/// briefly overlapping).
///
/// The earlier hand-rolled crossfade only faded the *incoming* page, so the
/// outgoing page sat fully opaque underneath and the two visibly overlapped
/// mid-transition. [SharedAxisTransition] (vertical) instead coordinates both
/// pages on a shared timeline: the outgoing page fades + drifts up and out
/// first, then the incoming page fades + rises in — they are never both visible
/// at once. `fillColor` is transparent so the canvas (not an opaque box) shows
/// through during the brief hand-off.
/// Maps the `/issues?view=…` query value to a preset filter (dashboard KPIs).
IssuesInitialView? _issuesView(String? value) => switch (value) {
  'today' => IssuesInitialView.today,
  'inprogress' => IssuesInitialView.inProgress,
  'backlog' => IssuesInitialView.backlog,
  'done' => IssuesInitialView.done,
  _ => null,
};

CustomTransitionPage<void> _transition(GoRouterState state, Widget child) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      child: child,
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          SharedAxisTransition(
            animation: animation,
            secondaryAnimation: secondaryAnimation,
            transitionType: SharedAxisTransitionType.vertical,
            fillColor: Colors.transparent,
            child: child,
          ),
    );
