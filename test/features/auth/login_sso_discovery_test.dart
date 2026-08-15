/// The sign-in screen discovers SSO providers with a *second* request, fired
/// the moment it mounts — which on a cold start races DNS, TLS and a backend
/// that may still be waking up. A single swallowed failure used to hide the SSO
/// buttons for the rest of the session on a server that has SSO configured:
/// "the button just isn't there on the first start, fine after a restart".
///
/// These tests pin the recovery: retry, and say so when it still fails.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/blocs/app_config_bloc.dart';
import 'package:hinata/core/blocs/auth_bloc.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/repositories/auth_repository.dart';
import 'package:hinata/core/repositories/meta_repository.dart';
import 'package:hinata/core/storage/app_storage.dart';
import 'package:hinata/features/auth/login_screen.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  Future<void> pumpLogin(WidgetTester tester, AuthRepository repository) async {
    tester.view
      ..physicalSize = const Size(900, 1400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Left open on purpose: awaiting Bloc.close() inside a testWidgets body
    // runs against the fake clock and never settles.
    final auth = AuthBloc(repository: repository, storage: storage);
    final config = AppConfigBloc(repository: _UnusedMeta(), storage: storage);
    final router = GoRouter(
      routes: [GoRoute(path: '/login', builder: (_, _) => const LoginScreen())],
      initialLocation: '/login',
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<AuthRepository>.value(value: repository),
          RepositoryProvider<AppStorage>.value(value: storage),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: auth),
            BlocProvider.value(value: config),
          ],
          // Text is scaled down because widget tests render i18n *keys* in the
          // square test font, which makes every label far wider than the real
          // translation — enough to overflow the fixed-width card for test
          // reasons alone.
          child: MaterialApp.router(
            routerConfig: router,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(0.5)),
              child: child!,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// The SSO button, whatever its (untranslated) label reads in a test.
  final ssoButton = find.byIcon(LucideIcons.shield);
  final retryButton = find.byIcon(LucideIcons.refreshCw);

  testWidgets('providers that answer straight away are rendered', (
    tester,
  ) async {
    final repository = _FakeAuthRepository(providers: [_provider]);
    await pumpLogin(tester, repository);
    await tester.pump();

    expect(ssoButton, findsOneWidget);
    expect(repository.calls, 1);
    expect(retryButton, findsNothing);
  });

  testWidgets('a failed first lookup is retried, and the button appears', (
    tester,
  ) async {
    final repository = _FakeAuthRepository(
      providers: [_provider],
      failures: 1, // the classic cold-start failure
    );
    await pumpLogin(tester, repository);
    await tester.pump();

    expect(ssoButton, findsNothing, reason: 'first attempt failed');

    await tester.pump(const Duration(milliseconds: 600));

    expect(ssoButton, findsOneWidget);
    expect(repository.calls, 2);
  });

  testWidgets('the retry survives two failures', (tester) async {
    final repository = _FakeAuthRepository(providers: [_provider], failures: 2);
    await pumpLogin(tester, repository);
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(ssoButton, findsOneWidget);
    expect(repository.calls, 3);
  });

  testWidgets('when every attempt fails the screen offers a manual retry', (
    tester,
  ) async {
    final repository = _FakeAuthRepository(providers: [_provider], failures: 3);
    await pumpLogin(tester, repository);
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    // Silence would read as "this server has no SSO" — which is wrong.
    expect(ssoButton, findsNothing);
    expect(retryButton, findsOneWidget);

    await tester.tap(retryButton);
    await tester.pump();
    await tester.pump();

    expect(ssoButton, findsOneWidget);
    expect(retryButton, findsNothing);
    expect(repository.calls, 4);
  });

  testWidgets('a rate-limited lookup waits for the bucket to refill', (
    tester,
  ) async {
    // Discovery shares the server's *auth* rate-limit bucket with sign-in and
    // token refresh (10/min per IP), so a few restarts in a minute answer 429.
    // Retrying inside a second would only burn attempts on an empty bucket.
    final repository = _FakeAuthRepository(
      providers: [_provider],
      failures: 1,
      failure: ApiFailure('error.rateLimited', statusCode: 429),
    );
    await pumpLogin(tester, repository);
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(ssoButton, findsNothing, reason: 'the bucket is still empty');
    expect(repository.calls, 1);

    await tester.pump(const Duration(seconds: 5));

    expect(ssoButton, findsOneWidget);
    expect(repository.calls, 2);
  });

  testWidgets('a server without SSO stays quiet', (tester) async {
    final repository = _FakeAuthRepository(providers: const []);
    await pumpLogin(tester, repository);
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(ssoButton, findsNothing);
    expect(retryButton, findsNothing);
    expect(repository.calls, 1);
  });
}

const _provider = SsoProvider(
  id: 'oidc',
  displayName: 'AStA SSO',
  loginUrl: '/api/v1/auth/sso/start/oidc',
);

/// Stands in for the network: fails the first [failures] lookups, then answers
/// with [providers].
class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository({
    required this.providers,
    this.failures = 0,
    ApiFailure? failure,
  }) : failure = failure ?? ApiFailure('errors.unexpected'),
       super(ApiClient(_UnusedStorage()));

  final List<SsoProvider> providers;
  final int failures;
  final ApiFailure failure;
  int calls = 0;

  @override
  Future<List<SsoProvider>> ssoProviders() async {
    calls++;
    if (calls <= failures) throw failure;
    return providers;
  }
}

/// Neither the meta repository nor the storage behind [ApiClient] is ever
/// reached: no event is dispatched to the config bloc, and the fake repository
/// issues no request.
class _UnusedMeta implements MetaRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _UnusedStorage implements AppStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
