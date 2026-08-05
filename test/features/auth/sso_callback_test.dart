import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/blocs/auth_bloc.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/repositories/auth_repository.dart';
import 'package:hinata/core/storage/app_storage.dart';
import 'package:hinata/features/auth/sso_callback_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The SSO handoff used to be a one-way street. `/auth-callback` is deliberately
/// allowed for an *unauthenticated* user (it has to be — the user is mid
/// sign-in), so no router redirect ever moves them off it. When the handoff then
/// failed, the screen only asked the bloc to re-check the session — which stays
/// unauthenticated — and nothing navigated. The user sat on "Signing you in…"
/// forever, on every platform, with the app unusable: quitting and retrying just
/// reproduced it.
///
/// These tests pin the exit: whatever goes wrong, this screen leaves for /login.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppStorage storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'server_url': 'https://server.test',
    });
    FlutterSecureStorage.setMockInitialValues({});
    storage = AppStorage(
      await SharedPreferences.getInstance(),
      const FlutterSecureStorage(),
    );
  });

  /// Boots just the callback route + a login marker, with [repository] behind
  /// the screen. Returns the router so a test can assert the landing location.
  Future<GoRouter> pumpCallback(
    WidgetTester tester,
    AuthRepository repository, {
    String? code,
    String? accessToken,
    String? refreshToken,
  }) async {
    // Deliberately not closed here: awaiting Bloc.close() inside a
    // testWidgets body (or its teardown) runs against the fake clock and never
    // settles, which reads as a mysterious 10-minute test timeout. An open
    // bloc holds no timers, so leaving it is harmless.
    final auth = AuthBloc(repository: repository, storage: storage);
    final query = <String>[
      if (code != null) 'code=$code',
      if (accessToken != null) 'access_token=$accessToken',
      if (refreshToken != null) 'refresh_token=$refreshToken',
    ].join('&');
    final router = GoRouter(
      initialLocation: query.isEmpty
          ? '/auth-callback'
          : '/auth-callback?$query',
      routes: [
        GoRoute(
          path: '/auth-callback',
          builder: (_, state) => SsoCallbackScreen(
            code: state.uri.queryParameters['code'],
            accessToken: state.uri.queryParameters['access_token'],
            refreshToken: state.uri.queryParameters['refresh_token'],
          ),
        ),
        GoRoute(
          path: '/login',
          builder: (_, _) => const Scaffold(body: Text('login-screen')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      RepositoryProvider<AuthRepository>.value(
        value: repository,
        child: BlocProvider.value(
          value: auth,
          child: MaterialApp.router(routerConfig: router),
        ),
      ),
    );
    return router;
  }

  String location(GoRouter router) =>
      router.routerDelegate.currentConfiguration.uri.path;

  /// The callback screen renders [HiveLoader], which animates forever, so
  /// `pumpAndSettle` never returns here. Pump a bounded number of frames
  /// instead: enough for the redeem future, the post-frame bail and the route
  /// transition that follows it.
  Future<void> advance(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('a rejected handoff code leaves the callback for /login', (
    tester,
  ) async {
    final router = await pumpCallback(
      tester,
      _FakeAuthRepository(
        onExchange: () =>
            throw ApiFailure('error.sso.invalidCode', statusCode: 400),
      ),
      code: 'expired-code',
    );

    // The exchange rejects, the screen must route itself out.
    await advance(tester);

    expect(location(router), '/login');
    expect(find.text('login-screen'), findsOneWidget);
  });

  testWidgets('an exchange that fails on the transport still leaves', (
    tester,
  ) async {
    final router = await pumpCallback(
      tester,
      _FakeAuthRepository(
        // Not an ApiFailure: the old catch-all still swallowed it into an
        // AuthChecked that changed nothing.
        onExchange: () => throw StateError('socket died'),
      ),
      code: 'some-code',
    );
    await advance(tester);

    expect(location(router), '/login');
  });

  testWidgets('a callback carrying nothing usable leaves for /login', (
    tester,
  ) async {
    final router = await pumpCallback(tester, _FakeAuthRepository());
    await advance(tester);

    expect(location(router), '/login');
  });

  testWidgets('a successful handoff stays put and signs the user in', (
    tester,
  ) async {
    final repository = _FakeAuthRepository(
      onExchange: () => (access: 'access-1', refresh: 'refresh-1'),
    );
    final router = await pumpCallback(tester, repository, code: 'good-code');
    await advance(tester);

    // No bail-out: the real router redirects an authenticated user onward from
    // here, and bouncing to /login would undo the login that just succeeded.
    expect(location(router), '/auth-callback');
    expect(storage.accessToken, 'access-1');

    // The screen keeps a watchdog armed while it waits; tear the tree down so
    // it is cancelled and the test doesn't trip the pending-timer check.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a replayed code does not throw the signed-in user out', (
    tester,
  ) async {
    // app_links can hand a cold-start link to BOTH getInitialLink() and
    // uriLinkStream, and a router refresh can rebuild the route — so the same
    // single-use code can reach this screen twice. The second POST always
    // fails; that must not undo the first one's successful sign-in.
    var exchanges = 0;
    final repository = _FakeAuthRepository(
      onExchange: () {
        exchanges++;
        if (exchanges > 1) throw ApiFailure('error.sso.invalidCode');
        return (access: 'access-1', refresh: 'refresh-1');
      },
    );
    await pumpCallback(tester, repository, code: 'replayed');
    await advance(tester);

    final router = await pumpCallback(tester, repository, code: 'replayed');
    await advance(tester);

    expect(exchanges, 1, reason: 'the code must only be redeemed once');
    expect(location(router), '/auth-callback');

    await tester.pumpWidget(const SizedBox());
  });

  group('AuthBloc always settles', () {
    test('AuthChecked emits even when /me fails unexpectedly', () async {
      await storage.setTokens(access: 'a', refresh: 'r');
      final bloc = AuthBloc(
        repository: _FakeAuthRepository(
          // A 200 with a body that doesn't parse throws a plain TypeError, not
          // an ApiFailure. That used to escape the handler, so the bloc emitted
          // nothing at all and stayed `authenticating` — which renders the
          // login screen with every control disabled. Forever.
          onMe: () => throw TypeError(),
        ),
        storage: storage,
      );
      addTearDown(bloc.close);

      final states = <AuthStatus>[];
      final sub = bloc.stream.listen((s) => states.add(s.status));
      bloc.add(const AuthChecked());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      expect(states, [AuthStatus.unauthenticated]);
      // An unparseable response is not proof the session is dead, so the tokens
      // survive for the next attempt (unlike a 401, which does clear them).
      expect(storage.accessToken, 'a');
    });

    test('AuthChecked clears the session when the server rejects it', () async {
      await storage.setTokens(access: 'a', refresh: 'r');
      final bloc = AuthBloc(
        repository: _FakeAuthRepository(
          onMe: () => throw ApiFailure('unauthorized', statusCode: 401),
        ),
        storage: storage,
      );
      addTearDown(bloc.close);

      final states = <AuthStatus>[];
      final sub = bloc.stream.listen((s) => states.add(s.status));
      bloc.add(const AuthChecked());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      expect(states, [AuthStatus.unauthenticated]);
      expect(storage.accessToken, isNull);
    });
  });
}

/// Stands in for the network. Only the two calls the SSO handoff makes are
/// scripted; everything else inherits the real (unused) implementation.
class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository({this.onExchange, this.onMe})
    : super(ApiClient(_UnusedStorage()));

  final ({String access, String refresh}) Function()? onExchange;
  final AuthUser Function()? onMe;

  @override
  Future<({String access, String refresh})> exchangeSso(String code) async {
    if (onExchange == null) throw StateError('exchange not scripted');
    return onExchange!();
  }

  @override
  Future<AuthUser> me() async {
    if (onMe != null) return onMe!();
    return const AuthUser(
      id: 'u1',
      email: 'sso@server.test',
      username: 'sso',
      displayName: 'SSO User',
      roles: {'USER'},
    );
  }
}

/// The fake repository never issues a request, but [ApiClient] needs a storage
/// to construct. Nothing on it is ever read.
class _UnusedStorage implements AppStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
