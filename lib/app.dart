import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'core/api/account_event_stream.dart';
import 'core/api/api_client.dart';
import 'core/blocs/app_config_bloc.dart';
import 'core/branding/org_logo_store.dart';
import 'core/blocs/auth_bloc.dart';
import 'core/blocs/locale_cubit.dart';
import 'core/blocs/theme_cubit.dart';
import 'core/i18n/i18n.dart';
import 'core/notifications/fcm_service.dart';
import 'core/notifications/wns_channel.dart';
import 'core/repositories/repositories.dart';
import 'core/router/app_router.dart';
import 'core/router/relay_link.dart';
import 'core/storage/app_storage.dart';
import 'core/util/server_link.dart' show knownServers, normalizeServerLink;
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'features/knowledge/data/knowledge_repository.dart';
import 'features/sprint/modals/glass_modal.dart'
    show GlassToastKind, showGlassToastIn;

/// Whether the "this session will not be kept" notice belongs on screen.
///
/// Top-level and public so the rule can be tested without booting the whole
/// app, because the states it must *not* fire on are as load-bearing as the
/// ones it must. `unknown` (boot) and `authenticating` render a spinner or a
/// disabled form and the router has not settled on a route to raise a toast
/// over; `twoFactorRequired` is mid sign-in and interrupting it with storage
/// advice would be noise at the worst moment. What is left is the two settled
/// outcomes — signed in, and bounced back to the login screen — and both of
/// them need the explanation for the same reason.
///
/// [alreadyAnnounced] keeps it to once per launch: the flag stays true for the
/// life of the process, and re-authenticating (or switching servers) would
/// otherwise repeat the same paragraph.
@visibleForTesting
bool shouldAnnounceMemoryOnlySession({
  required AuthStatus status,
  required bool sessionIsMemoryOnly,
  required bool alreadyAnnounced,
}) =>
    !alreadyAnnounced &&
    sessionIsMemoryOnly &&
    (status == AuthStatus.authenticated ||
        status == AuthStatus.unauthenticated);

class HinataApp extends StatefulWidget {
  const HinataApp({
    super.key,
    required this.storage,
    required this.apiClient,
    required this.repositories,
    this.initialLink,
  });

  final AppStorage storage;
  final ApiClient apiClient;
  final HinataRepositories repositories;

  /// A `hinata://` link the process was launched with, read from the command
  /// line by `main`. Linux only — see `_launchDeepLink` there for why the
  /// plugin cannot see that one.
  final Uri? initialLink;

  @override
  State<HinataApp> createState() => _HinataAppState();
}

class _HinataAppState extends State<HinataApp> with WidgetsBindingObserver {
  late final AppConfigBloc _appConfig;
  late final AuthBloc _auth;
  late final LocaleCubit _locale;
  late final OrgLogoStore _orgLogo;
  late final GoRouter _router;
  late final AccountEventStream _accountEvents;
  late final FcmService _fcm;
  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<AppConfigState>? _configSub;
  // The server the auth session was last (re)checked against. When the user
  // switches servers, AppConfig re-verifies the new backend and reaches `ready`
  // with a different URL than this — that's our cue to re-check auth so the
  // session reflects the new server (its own token, or a sign-in prompt).
  String? _authServer;
  // The server the realtime streams (SSE sign-out + FCM) are currently bound to,
  // so a switch tears them down and reopens them against the new backend.
  String? _streamServer;
  // One warning per launch that the session is not being persisted; repeating
  // it on every re-authentication would be nagging, not informing.
  bool _warnedMemoryOnlySession = false;
  // Shared backend-backed Knowledge Base store: the KB screen and the real
  // issue detail both resolve smart-links / "Documented in" against this single
  // instance. Loaded lazily on first use (post-auth), not at startup.
  late final KnowledgeRepository _knowledge = KnowledgeRepository(
    articles: widget.repositories.articles,
    users: widget.repositories.users,
    auth: widget.repositories.auth,
  );
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Effective UI language (hydrated across restarts). Prime the API client's
    // Accept-Language from it *before* the AuthChecked /me request below, so the
    // very first request already carries the user's real language rather than
    // racing the first build() and going out as the default 'en'. The server
    // syncs the stored User.locale from this header, and async e-mails/push
    // (which have no request context) localize off that stored value.
    _locale = LocaleCubit();
    widget.apiClient.localeCode = _locale.state.languageCode;
    final domains = widget.repositories;
    _appConfig = AppConfigBloc(
      repository: domains.meta,
      storage: widget.storage,
    )..add(const AppConfigStarted());
    // App-wide, because the organization's logo is chrome: the shell, the
    // sign-in hero and the admin console all show it, and it must be fetched
    // once per server rather than once per surface.
    _orgLogo = OrgLogoStore(meta: domains.meta, api: widget.apiClient);
    _auth = AuthBloc(repository: domains.auth, storage: widget.storage)
      ..add(const AuthChecked());
    widget.apiClient.onSessionExpired = () =>
        _auth.add(const LogoutRequested());
    // Real-time sign-out: hold the account event stream open while signed in so
    // the server can push a `logout` (revoked session) and end this device's
    // session at once, rather than waiting for the next request to 401.
    _accountEvents = AccountEventStream(
      repository: domains.account,
      onLogout: () => _auth.add(const LogoutRequested()),
    );
    _router = buildRouter(
      appConfig: _appConfig,
      auth: _auth,
      storage: widget.storage,
    );
    // Push: a tapped notification carries the in-app route in its data payload;
    // forward it straight to the router (same routes as the web deep links).
    // Must exist before the first _syncAccountStream call below, which starts
    // FCM when the persisted session is already authenticated.
    _fcm = FcmService(
      apiClient: widget.apiClient,
      storage: widget.storage,
      onDeepLink: (link) => _router.go(link),
    );
    // Cold start: a notification tap that launched the fully-terminated app
    // carries its route in the initial message. Consume it now — before FCM's
    // sign-in-gated, token-handshake-gated start() below — so the slow APNs +
    // token resolution can't defer or drop it. Routed through _router.go, the
    // gate-parking preserves the link until the app is ready + authenticated
    // (mirrors the App Links getInitialLink() cold-start handling below).
    unawaited(_fcm.handleInitialMessage());
    // Windows toasts activate the app instead of delivering through FCM, so
    // their deep link arrives over its own channel — same routing target.
    const WnsChannel().listenForDeepLinks((link) => _router.go(link));
    unawaited(
      const WnsChannel().initialDeepLink().then((link) {
        if (link != null) _router.go(link);
      }),
    );
    // Record the server the boot-time AuthChecked above runs against, so the
    // listener below doesn't redundantly re-check it on the first `ready`.
    _authServer = widget.storage.serverUrl;
    _syncAccountStream(_auth.state);
    _authSub = _auth.stream.listen(_syncAccountStream);
    _configSub = _appConfig.stream.listen(_onAppConfig);
    unawaited(_listenForDeepLinks());
  }

  /// Re-checks the auth session whenever AppConfig settles on a *different*
  /// server than the one auth was last validated against. This is the single
  /// place that reacts to a server switch (from the switcher, the connect
  /// screen, or a deep link), regardless of who triggered it: the new backend
  /// either has a stored token (→ straight back in) or doesn't (→ sign-in).
  void _onAppConfig(AppConfigState state) {
    if (state.status != AppConfigStatus.ready) return;
    final server = widget.storage.serverUrl;
    if (_authServer == server) return;
    _authServer = server;
    _auth.add(const AuthChecked());
  }

  /// Opens the account event stream once authenticated and closes it otherwise,
  /// so the real-time sign-out channel is only live for a signed-in user.
  void _syncAccountStream(AuthState state) {
    if (state.status == AuthStatus.authenticated) {
      final server = widget.storage.serverUrl;
      // Switched backends while signed in (same `authenticated` status, new
      // server): tear the streams down so they reopen against the new host
      // below — start() is a no-op while already running and would otherwise
      // keep streaming from the old server.
      if (_streamServer != server) {
        _accountEvents.stop();
        _fcm.stop();
        _streamServer = server;
      }
      _accountEvents.start();
      // Screenshot mode (tooling: a pre-seeded `screenshot_route` pref) never
      // starts push — otherwise the OS notification-permission prompt would pop
      // over the very screen we're capturing. Normal launches are unaffected.
      if (widget.storage.screenshotRoute == null) _fcm.start();
    } else {
      _streamServer = null;
      _accountEvents.stop();
      _fcm.stop();
    }
    _warnIfSessionWontPersist(state);
  }

  /// Says once per launch when the sign-in cannot be written to the OS secret
  /// store — and names the one thing that would fix it.
  ///
  /// [AppStorage.sessionIsMemoryOnly] is set whenever a secure-storage call
  /// throws, which in practice means Linux: a desktop with no keyring, a
  /// strictly confined snap whose `password-manager-service` interface has not
  /// been connected, or a keyring that is simply locked. Staying quiet would
  /// make the login look like it worked right up until the next launch asks for
  /// the password again, with nothing to connect the two.
  ///
  /// Fires from *both* halves of [_syncAccountStream], which is the half of the
  /// problem that used to be missed. The user this hurts most never reaches
  /// `authenticated` at all: their tokens were stored on a previous run,
  /// [AppStorage] could not read them back, and the app drops them on the login
  /// screen with no idea why. That is `unauthenticated`, and it now gets the
  /// same explanation. The two in-flight states (`unknown` at boot,
  /// `authenticating`) are skipped — they render as a spinner or a disabled
  /// form, and the router has not settled anywhere to raise a toast over.
  void _warnIfSessionWontPersist(AuthState state) {
    if (!shouldAnnounceMemoryOnlySession(
      status: state.status,
      sessionIsMemoryOnly: widget.storage.sessionIsMemoryOnly,
      alreadyAnnounced: _warnedMemoryOnlySession,
    )) {
      return;
    }
    // Which sentence this is, and whether there is a command to copy, comes
    // from the storage layer: the environment says what kind of system this is,
    // the thrown error says whether the store was unreachable or merely locked.
    // A `snap connect` line is never shown to someone who is not running a
    // snap, nor to a snap that already has the permission.
    final notice = widget.storage.secretStoreNotice;
    if (notice == null) return;
    final command = notice.command;
    // Claimed now, so a second settled auth state in this same frame cannot
    // queue a second toast — and given back below if this frame turns out to
    // have nowhere to put one.
    _warnedMemoryOnlySession = true;
    // After the frame: this runs from a bloc listener, and the navigator whose
    // overlay the toast goes into is still being rebuilt for the route it just
    // settled on.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = rootNavigatorKey.currentContext;
      // The navigator's own overlay, not Overlay.of(context) — showGlassToastIn
      // carries the reason.
      final overlay = rootNavigatorKey.currentState?.overlay;
      if (context == null || !context.mounted || overlay == null) {
        // No root navigator on this frame: go_router renders nothing at all
        // until its first match list resolves, and whether that has happened by
        // now is a property of the router — a redirect that becomes async, a
        // deep link that defers the first match — not of anything decided here.
        // Nothing was said, so nothing counts as announced: the next settled
        // auth state gets to try again instead of the notice being dropped for
        // the whole launch with nothing to show it was ever due.
        _warnedMemoryOnlySession = false;
        return;
      }
      showGlassToastIn(
        overlay,
        context.t(notice.messageKey, variables: {'command': ?command}),
        kind: GlassToastKind.warning,
        // Long, because it carries a sentence to understand and sometimes a
        // command to copy. The default 3.2s is sized for "Saved".
        duration: const Duration(seconds: 12),
        // Copying the command is only offered where there is one, i.e. inside a
        // snap that still needs the permission. That also makes this pill
        // interactive, so it stops ignoring pointers for those 12 seconds — and
        // a Linux window can be narrower than the compact breakpoint (the GTK
        // runner only sets a *default* size, and a tiling WM is free to hand it
        // half a column), in which case the toast anchors to the *bottom*,
        // right over the sign-in button. Tapping the pill anywhere but the
        // action dismisses it; see [showGlassToastIn].
        actionLabel: command == null
            ? null
            : context.t('errors.sessionNotPersisted.copyCommand'),
        onAction: command == null
            ? null
            : () {
                Clipboard.setData(ClipboardData(text: command));
                final after = rootNavigatorKey.currentContext;
                final overlayAfter = rootNavigatorKey.currentState?.overlay;
                if (after == null || !after.mounted || overlayAfter == null) {
                  return;
                }
                showGlassToastIn(
                  overlayAfter,
                  after.t('common.copied'),
                  kind: GlassToastKind.success,
                );
              },
      );
    });
  }

  /// Subscribes to the two doors a deep link can come through: the link the app
  /// was *launched* from, and the ones that arrive while it is already running.
  ///
  /// Both feed [_handleUri], which understands the app's `hinata://` links (the
  /// SSO callback and the token-carrying invite / reset / verify flows) and the
  /// https Universal / App Links the Connect gateway sends in every e-mail.
  Future<void> _listenForDeepLinks() async {
    final appLinks = AppLinks();
    // Cold start: the link that launched the app (e.g. tapping an email link).
    // Read *before* subscribing, because subscribing replays that very link as
    // the stream's first event (app_links' `onListen` hands out an initial link
    // it has not sent yet). Following one link twice re-submits the server and
    // bounces the app back out through /connecting — right out of the screen it
    // had just opened.
    Uri? fromPlugin;
    try {
      fromPlugin = await appLinks.getInitialLink();
    } catch (e) {
      debugPrint('Initial deep link lookup failed: $e');
    }
    if (!mounted) return;
    // Only the plugin's own initial link is the one the stream replays; a link
    // that came in on the command line was never in that stream to begin with.
    Uri? replay = fromPlugin;
    final initial = fromPlugin ?? widget.initialLink;
    _linkSubscription = appLinks.uriLinkStream.listen((uri) {
      // Only the *first* stream event can be that replay; from then on an
      // identical link is a second, deliberate tap and is followed again.
      final isReplay = uri == replay;
      replay = null;
      if (isReplay) return;
      unawaited(_handleUri(uri));
    });
    if (initial != null) await _handleUri(initial);
  }

  Future<void> _handleUri(Uri uri) async {
    // Custom-scheme links (hinata://…) — SSO callback + token email flows.
    if (uri.scheme == 'hinata') {
      switch (uri.host) {
        case 'auth-callback':
          // SSO handoff. Modern servers redirect natively with a single-use
          // `code` (hinata://auth-callback?code=…); older ones embed the token
          // pair directly. Forward the whole query to the /auth-callback route
          // so SsoCallbackScreen redeems the code (or accepts the legacy
          // tokens) through the exact same path the web flow uses. The previous
          // handler only understood access_token/refresh_token and silently
          // dropped the modern `code`, so a native SSO login stored nothing and
          // stranded the user on the login screen.
          _router.go('/auth-callback?${uri.query}');
        case 'invite':
          _openTokenFlow(uri, '/invite');
        case 'reset-password':
          _openTokenFlow(uri, '/reset-password');
        case 'verify-email':
          _openTokenFlow(uri, '/verify-email');
      }
      return;
    }

    // Universal / App Links (https) from the production web domain. Verified
    // against /.well-known/{assetlinks.json,apple-app-site-association}, these
    // carry the same in-app routes as the website (e.g. /issues/MOB-9), so we
    // forward the path straight to the router. The token flows carry a server
    // their screen has to consent to before using, so they keep going through
    // _openTokenFlow.
    if (uri.scheme == 'https' || uri.scheme == 'http') {
      if (uri.path.startsWith('/l/')) {
        await _openRelayLink(uri);
      } else if (uri.path.startsWith('/invite')) {
        _openTokenFlow(uri, '/invite');
      } else if (uri.path.startsWith('/reset-password')) {
        _openTokenFlow(uri, '/reset-password');
      } else if (uri.path.startsWith('/verify-email')) {
        _openTokenFlow(uri, '/verify-email');
      } else if (uri.path.isNotEmpty && uri.path != '/') {
        _router.go(uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path);
      }
    }
  }

  /// Hinata Connect relay links: `https://connect…/l/<base64url(payload)>.<sig>`.
  /// The payload carries the originating server's API URL (`a`), the in-app path
  /// (`p`) and, for invite/reset flows only, a one-time token (`t`) — plain
  /// notification links (mentions, assignments, …) omit it. We decode it
  /// locally (the gateway's signature is only for its own web-fallback
  /// redirect; a token, when present, is validated server-side anyway), point
  /// the app at that server, and open the flow.
  Future<void> _openRelayLink(Uri uri) async {
    final link = RelayLink.parse(uri);
    // Only the *decode* is allowed to fail quietly — a garbage relay link is
    // nothing we can act on. Switching servers and routing used to sit inside
    // that same `catch`, which turned any failure on the way to the screen into
    // a link that silently did nothing at all.
    if (link == null) return;

    // The relay payload is decoded locally and is not authenticated — the
    // gateway's signature only protects its own web fallback — so the server it
    // names is a claim, exactly like the one in a hinata:// link.
    //
    // The three token routes gate that claim themselves, so it is handed to
    // them. Every other relay link opens an ordinary screen with no gate, and
    // those may only follow a server this device already uses: a notification
    // link comes from a server the user is signed in to, so nothing legitimate
    // needs more, and it means no link can move the app to a backend the user
    // has never seen without ever asking.
    final path = link.route.split('?').first;
    if (_serverGatedRoutes.contains(path)) {
      _router.go(_routeWithServer(link.route, link.server));
      return;
    }
    final known = knownServers(widget.storage);
    final server = normalizeServerLink(link.server, known: known);
    if (server != null && known.contains(server)) await _selectServer(server);
    _router.go(link.route);
  }

  /// The routes that ask the user themselves before switching backends — see
  /// [applyServerFromLink], which each of their screens runs.
  static const _serverGatedRoutes = {
    '/invite',
    '/reset-password',
    '/verify-email',
  };

  /// [route] with the link's `server` appended, merging into a query it may
  /// already have rather than starting a second one.
  static String _routeWithServer(String route, String? server) {
    if (server == null || server.isEmpty) return route;
    final separator = route.contains('?') ? '&' : '?';
    return '$route${separator}server=${Uri.encodeQueryComponent(server)}';
  }

  /// Points the app at the server a deep link came from.
  ///
  /// Deliberately a no-op when that server is already the current one: a
  /// [ServerUrlSubmitted] restarts the connection, which drops AppConfig back to
  /// `connecting` and bounces the router onto /connecting — undoing the very
  /// navigation the link just made. Every push/e-mail deep link carries its
  /// origin server, so without this guard *every* one of them took that detour.
  /// A failed connection is still re-submitted, since that is the case where
  /// re-connecting is the whole point.
  ///
  /// The value is checked before it is stored. It arrives inside a link — from
  /// the OS scheme handler, from the process arguments on Linux, from a relay
  /// payload — so it is an outside claim about which backend this app should
  /// talk to, and [AppConfigBloc] refuses anything that is not an absolute
  /// http(s) URL with a host. Writing first and letting the bloc refuse
  /// afterwards would leave that refused value in storage as the API client's
  /// base URL.
  Future<void> _selectServer(String? raw) async {
    if (raw == null) return;
    // Normalized and checked exactly the way [ServerUrlSubmitted] does it, and
    // no more strictly: being stricter here would drop a link the connect
    // screen would have accepted, and writing the un-normalized string would
    // save a second profile for the same server the moment a link spelled it
    // with a trailing slash. In particular not `isAbsolute`, which Dart also
    // makes false for a URL that merely carries a fragment.
    var server = raw.trim();
    if (server.endsWith('/')) server = server.substring(0, server.length - 1);
    if (server.isEmpty) return;
    final uri = Uri.tryParse(server);
    if (uri == null ||
        !(uri.isScheme('https') || uri.isScheme('http')) ||
        uri.host.isEmpty) {
      return;
    }
    if (widget.storage.serverUrl == server &&
        _appConfig.state.status != AppConfigStatus.needsServerUrl) {
      return;
    }
    await widget.storage.setServerUrl(server);
    _appConfig.add(ServerUrlSubmitted(server));
  }

  /// Shared handoff for the token-carrying email deep links (invite / reset /
  /// verify): route to the in-app screen, carrying the server the link named.
  ///
  /// The server is *forwarded*, not applied here. Each of these three screens
  /// already runs it through `applyServerFromLink`, which requires https and
  /// asks the user before switching to a backend they have never used — the
  /// whole point being that a link is not allowed to silently repoint the app
  /// at somebody else's server and collect the password typed into the next
  /// screen. Applying it here instead, and then dropping the parameter on the
  /// way to the route, meant that consent gate was handed a null and never ran
  /// on any deep link at all: `hinata://invite?token=…&server=http://attacker`
  /// switched servers on its own. Passing it on is what makes the gate real.
  void _openTokenFlow(Uri uri, String route) {
    final token = uri.queryParameters['token'];
    if (token == null || token.isEmpty) return;
    _router.go(
      _routeWithServer(
        '$route?token=${Uri.encodeQueryComponent(token)}',
        uri.queryParameters['server'],
      ),
    );
  }

  /// Dismiss the keyboard whenever the app leaves the foreground. If a TextField
  /// is still focused (keyboard up) when iOS snapshots the app for the background,
  /// UIKit's own keyboard layout (TUIKeyboardContentView / UIKeyboardImpl) logs a
  /// spurious "Unable to simultaneously satisfy constraints" warning — its
  /// internal 250 vs. 216 height conflict, not ours. Unfocusing first removes the
  /// trigger so the keyboard is already gone before the snapshot is taken.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    super.didChangeAppLifecycleState(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _linkSubscription?.cancel();
    _authSub?.cancel();
    _configSub?.cancel();
    _accountEvents.stop();
    _router.dispose();
    _appConfig.close();
    _auth.close();
    _locale.close();
    _orgLogo.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final domains = widget.repositories;
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: widget.storage),
        RepositoryProvider.value(value: widget.apiClient),
        RepositoryProvider.value(value: _knowledge),
        // Domain layer: one repository per domain (see core/repositories/).
        // Feature code injects exactly the repository it needs.
        RepositoryProvider<MetaRepository>.value(value: domains.meta),
        RepositoryProvider<AuthRepository>.value(value: domains.auth),
        RepositoryProvider<AccountRepository>.value(value: domains.account),
        RepositoryProvider<UserRepository>.value(value: domains.users),
        RepositoryProvider<ProjectRepository>.value(value: domains.projects),
        RepositoryProvider<IssueRepository>.value(value: domains.issues),
        RepositoryProvider<CommentRepository>.value(value: domains.comments),
        RepositoryProvider<MediaRepository>.value(value: domains.media),
        RepositoryProvider<BoardRepository>.value(value: domains.boards),
        RepositoryProvider<SprintRepository>.value(value: domains.sprints),
        RepositoryProvider<TimesheetRepository>.value(value: domains.timesheet),
        RepositoryProvider<SearchRepository>.value(value: domains.search),
        RepositoryProvider<ArticleRepository>.value(value: domains.articles),
        RepositoryProvider<DashboardRepository>.value(value: domains.dashboard),
        RepositoryProvider<WeeklySummaryRepository>.value(
          value: domains.weeklySummary,
        ),
        RepositoryProvider<NotificationRepository>.value(
          value: domains.notifications,
        ),
        RepositoryProvider<AdminRepository>.value(value: domains.admin),
        RepositoryProvider<TeamRepository>.value(value: domains.teams),
        RepositoryProvider<GitRepository>.value(value: domains.git),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider.value(value: _appConfig),
          BlocProvider.value(value: _auth),
          BlocProvider.value(value: _locale),
          BlocProvider.value(value: _orgLogo),
          BlocProvider(create: (_) => ThemeCubit()),
        ],
        child: BlocBuilder<ThemeCubit, ThemeMode>(
          builder: (context, themeMode) {
            return BlocBuilder<LocaleCubit, Locale>(
              builder: (context, locale) {
                // Keep the API client's Accept-Language in sync so the server
                // localizes its error messages to the user's chosen language.
                widget.apiClient.localeCode = locale.languageCode;
                // The OS task switcher and the browser tab are chrome like any
                // other: on a self-hosted instance they should name the
                // organization. Resolved at runtime — never baked — because one
                // web bundle serves every deployment. `select` so it follows the
                // meta arriving after the first connect, rather than staying on
                // whatever was known at boot.
                final organization = context
                    .select<AppConfigBloc, String?>(
                      (bloc) => bloc.state.meta?.organizationName,
                    )
                    ?.trim();
                return MaterialApp.router(
                  title: (organization == null || organization.isEmpty)
                      ? 'Hinata'
                      : organization,
                  debugShowCheckedModeBanner: false,
                  theme: AppTheme.light(),
                  darkTheme: AppTheme.dark(),
                  themeMode: themeMode,
                  locale: locale,
                  supportedLocales: I18n.supportedLocales,
                  localizationsDelegates: I18n.delegates(),
                  routerConfig: _router,
                  // Sync the runtime brightness that drives AppColors' neutral
                  // getters with the user's chosen ThemeMode (following the OS
                  // for ThemeMode.system). We resolve this from the mode/platform
                  // directly rather than Theme.of(context).brightness: MaterialApp
                  // *animates* between the light/dark ThemeData and that discrete
                  // brightness flag only flips at the animation midpoint, which
                  // would make AppColors' neutral colors lag the switch by ~100ms.
                  // Runs above the router subtree each build, so screens that read
                  // AppColors get the correct value on the very first frame.
                  builder: (context, child) {
                    AppColors.brightness = switch (themeMode) {
                      ThemeMode.light => Brightness.light,
                      ThemeMode.dark => Brightness.dark,
                      ThemeMode.system => MediaQuery.platformBrightnessOf(
                        context,
                      ),
                    };
                    // Performance + stability: install the liquid-glass adaptive
                    // quality scope at the app root. Without it, every explicit
                    // `quality: GlassQuality.premium` in the app renders the full
                    // (and crash-prone on some Mali GPUs) two-BackdropFilter +
                    // fragment-shader pipeline *ungated* on every device. The
                    // scope acts as a device-capability ceiling that caps those
                    // surfaces. We cap at `standard` (the lightweight single-pass
                    // shader — 5-10x cheaper, and the path that does NOT trigger
                    // the shader-related production crashes) and let the runtime
                    // monitor degrade to `standard` (BackdropFilter-only) on weak
                    // GPUs, stepping back up when headroom returns. Raise
                    // maxQuality to premium only if flagship refraction is wanted.
                    return LiquidGlassWidgets.wrap(
                      adaptiveQuality: true,
                      // Deliberately using the package's experimental adaptive
                      // quality API — it is the intended, supported way to gate
                      // glass cost per device.
                      // ignore: experimental_member_use
                      adaptiveConfig: const GlassAdaptiveScopeConfig(
                        initialQuality: GlassQuality.standard,
                        maxQuality: GlassQuality.premium,
                        minQuality: GlassQuality.standard,
                        allowStepUp: true,
                        targetFrameMs: 16,
                      ),
                      child: child ?? const SizedBox.shrink(),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}
