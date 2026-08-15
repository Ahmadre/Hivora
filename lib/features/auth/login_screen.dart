import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInput;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/widgets/hive_loader.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_client.dart' show ApiFailure;
import '../../core/repositories/auth_repository.dart';
import '../../core/blocs/app_config_bloc.dart';
import '../../core/blocs/auth_bloc.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/core_models.dart';
import '../../core/storage/app_storage.dart';
import '../../core/theme/app_colors.dart';
import '../account/twofa_modals.dart' show OtpInput;
import '../connect/server_switcher.dart';
import '../legal/legal_links.dart';
import '../sprint/modals/glass_modal.dart' show showGlassErrorToast;
import 'auth_shell.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

/// How the SSO provider list is doing. The buttons come from a *second*
/// request, so "none yet" and "we couldn't ask" are different states — and only
/// the second one may be presented as a problem.
enum _SsoDiscovery { loading, done, failed }

class _LoginScreenState extends State<LoginScreen> with WidgetsBindingObserver {
  /// Attempts spent on discovering the SSO providers before giving up, and how
  /// long to wait before each of them.
  static const List<Duration> _ssoRetryDelays = [
    Duration.zero,
    Duration(milliseconds: 500),
    Duration(milliseconds: 2000),
  ];

  /// What to wait instead after a 429. Provider discovery draws from the
  /// server's *auth* rate-limit bucket — the same small budget as sign-in and
  /// token refresh — so a couple of app restarts in a minute can empty it. That
  /// bucket refills continuously, so the next token is seconds away; retrying
  /// on the ordinary backoff would just burn attempts against an empty one.
  static const Duration _ssoRateLimitedDelay = Duration(seconds: 7);

  final _formKey = GlobalKey<FormState>();
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  List<SsoProvider> _providers = const [];
  _SsoDiscovery _ssoDiscovery = _SsoDiscovery.loading;

  /// Generation counter for [_loadProviders]: a reload (server switch, retry
  /// tap) invalidates whatever an older, still-retrying run would report.
  int _ssoLoad = 0;

  /// Which server [_providers] were discovered on. The selector sits right
  /// above the form, so the list must never outlive the backend it came from —
  /// its buttons would start a flow the new server doesn't have.
  String? _providersServer;

  /// The 2FA code typed during a login challenge.
  String _otpCode = '';

  /// Id of the SSO provider currently launching, or null. Drives the per-button
  /// loader; combined with [AuthStatus.authenticating] it disables every button
  /// so no second login can start while one is in flight.
  String? _launchingSsoId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadProviders();
    _showSsoErrorIfPresent();
  }

  /// Re-enables the SSO buttons when the user comes back without having
  /// completed the login (they cancelled at the provider, or hit Back). Native
  /// resets right after handing off to the browser, but on the web the tab
  /// itself leaves — and if it is restored from the back/forward cache the
  /// Dart state comes back exactly as it left, buttons still disabled, with no
  /// way to start another attempt.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_launchingSsoId != null) setState(() => _launchingSsoId = null);
      // Discovery that never landed (the app started before the network was
      // up, a tunnel was still cold) gets another go now that we are back —
      // otherwise the buttons stay missing for the rest of the session.
      if (_ssoDiscovery == _SsoDiscovery.failed) _loadProviders();
    }
    super.didChangeAppLifecycleState(state);
  }

  /// A failed SSO login lands back here as `/login?ssoError=<reason>` — either
  /// a message from the server, or a key from [SsoCallbackScreen] when the
  /// handoff itself failed. `t()` returns unknown strings unchanged, so both
  /// render correctly.
  void _showSsoErrorIfPresent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final error = GoRouterState.of(context).uri.queryParameters['ssoError'];
      if (error != null && error.isNotEmpty) {
        showGlassErrorToast(
          context,
          '${context.t('auth.ssoFailed')}: ${context.t(error)}',
        );
      }
    });
  }

  /// Discovers the server's SSO providers, retrying a couple of times.
  ///
  /// This is the *second* request of the session, fired the instant the sign-in
  /// screen mounts — right after a cold start, when the connection is often
  /// still waking up (DNS, TLS, a proxy or tunnel warming its first upstream,
  /// or Wi-Fi that hasn't associated yet). One swallowed failure used to mean
  /// the SSO buttons silently never appeared for the rest of the session, on a
  /// server that has SSO configured: exactly the "it's missing on the first
  /// start, fine after a restart" report. So try again a few times, and let
  /// [didChangeAppLifecycleState] and the server switch below re-arm it.
  Future<void> _loadProviders() async {
    final load = ++_ssoLoad;
    // Read the tree before the first await — the context may be gone after one.
    final repository = context.read<AuthRepository>();
    final server = context.read<AppStorage>().serverUrl;
    if (_ssoDiscovery != _SsoDiscovery.loading) {
      setState(() => _ssoDiscovery = _SsoDiscovery.loading);
    }
    var delay = Duration.zero;
    for (var attempt = 0; attempt < _ssoRetryDelays.length; attempt++) {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      if (!mounted || load != _ssoLoad) return;
      try {
        final providers = await repository.ssoProviders();
        if (!mounted || load != _ssoLoad) return;
        setState(() {
          _providers = providers;
          _providersServer = server;
          _ssoDiscovery = _SsoDiscovery.done;
        });
        return;
      } catch (error) {
        // Never fatal: password login stays available either way. Said out loud
        // in debug, because a missing button is otherwise indistinguishable
        // from a server without SSO.
        if (kDebugMode) {
          debugPrint(
            '[sso] provider discovery failed '
            '(${attempt + 1}/${_ssoRetryDelays.length}): $error',
          );
        }
        final rateLimited = error is ApiFailure && error.statusCode == 429;
        delay = rateLimited
            ? _ssoRateLimitedDelay
            : _ssoRetryDelays[(attempt + 1).clamp(
                0,
                _ssoRetryDelays.length - 1,
              )];
      }
    }
    if (mounted && load == _ssoLoad) {
      setState(() => _ssoDiscovery = _SsoDiscovery.failed);
    }
  }

  /// Re-discovers after a server switch settles: the providers of the backend
  /// we just left must not linger, and the new one's have never been fetched.
  void _onConfigChanged(BuildContext context, AppConfigState state) {
    if (state.status != AppConfigStatus.ready) return;
    if (context.read<AppStorage>().serverUrl == _providersServer) return;
    setState(() => _providers = const []);
    _loadProviders();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final organization = context.select(
      (AppConfigBloc bloc) => bloc.state.meta?.organizationName,
    );
    // Local email/password auth can be disabled server-side (SSO-only mode);
    // and self-registration can be closed independently. Default on for servers
    // that predate the flags.
    final localAuth = context.select(
      (AppConfigBloc bloc) => bloc.state.meta?.localAuthEnabled ?? true,
    );
    final registrationEnabled = context.select(
      (AppConfigBloc bloc) => bloc.state.meta?.registrationEnabled ?? true,
    );
    return AuthShell(
      maxContentWidth: 440,
      child: BlocListener<AppConfigBloc, AppConfigState>(
        listener: _onConfigChanged,
        child: BlocConsumer<AuthBloc, AuthState>(
          listener: (context, state) {
            if (state.errorKey != null) {
              showGlassErrorToast(context, context.t(state.errorKey!));
            }
          },
          builder: (context, state) {
            if (state.status == AuthStatus.twoFactorRequired ||
                (state.status == AuthStatus.authenticating &&
                    state.mfaToken != null)) {
              return _twoFactorPanel(context, state);
            }
            final passwordBusy = state.status == AuthStatus.authenticating;
            // While any login is in flight every button is disabled, so a
            // second flow can't start on top of the first.
            final busy = passwordBusy || _launchingSsoId != null;
            return AuthGlassCard(
              child: Form(
                key: _formKey,
                // Groups the identifier + password fields so the OS/password
                // manager fills both when a saved credential is picked, and can
                // offer to save the pair on submit.
                child: AutofillGroup(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Let the user re-target a different backend before
                      // signing in (or add a new one).
                      const ServerSelectorButton(),
                      const SizedBox(height: 16),
                      Text(
                        organization ?? 'Hinata',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        localAuth
                            ? context.t('auth.subtitle')
                            : context.t('auth.ssoOnlyBody'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      if (localAuth) ...[
                        const SizedBox(height: 20),
                        TextFormField(
                          controller: _identifier,
                          enabled: !busy,
                          autofillHints: const [AutofillHints.username],
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          decoration: InputDecoration(
                            labelText: context.t('auth.identifier'),
                            prefixIcon: const Icon(LucideIcons.user),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? context.t('errors.required')
                              : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _password,
                          enabled: !busy,
                          obscureText: true,
                          autofillHints: const [AutofillHints.password],
                          textInputAction: TextInputAction.done,
                          decoration: InputDecoration(
                            labelText: context.t('auth.password'),
                            prefixIcon: const Icon(LucideIcons.lock),
                          ),
                          validator: (v) => (v == null || v.isEmpty)
                              ? context.t('errors.required')
                              : null,
                          onFieldSubmitted: (_) => _submit(),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: busy
                                ? null
                                : () => context.go('/forgot-password'),
                            child: Text(context.t('auth.forgotPassword')),
                          ),
                        ),
                        const SizedBox(height: 10),
                        FilledButton(
                          onPressed: busy ? null : _submit,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: passwordBusy
                                ? const SizedBox(
                                    key: ValueKey('loader'),
                                    width: 22,
                                    height: 22,
                                    child: HiveLoader(
                                      size: 22,
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    context.t('auth.signIn'),
                                    key: const ValueKey('label'),
                                  ),
                          ),
                        ),
                      ],
                      // The "or" divider only makes sense when both local
                      // sign-in and SSO are offered.
                      if (localAuth && _providers.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            const Expanded(child: Divider()),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Text(
                                context.t('auth.or'),
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                            const Expanded(child: Divider()),
                          ],
                        ),
                      ],
                      // SSO buttons are shown whenever a provider exists,
                      // including SSO-only mode (localAuth == false).
                      if (_providers.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        for (final provider in _providers)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: OutlinedButton.icon(
                              onPressed: busy
                                  ? null
                                  : () => _launchSso(provider),
                              icon: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                child: _launchingSsoId == provider.id
                                    ? const SizedBox(
                                        key: ValueKey('loader'),
                                        width: 18,
                                        height: 18,
                                        child: HiveLoader(
                                          size: 18,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        LucideIcons.shield,
                                        size: 18,
                                        key: ValueKey('icon'),
                                      ),
                              ),
                              label: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                child: _launchingSsoId == provider.id
                                    ? Text(
                                        context.t('auth.signingIn'),
                                        key: const ValueKey('signing'),
                                      )
                                    : Text(
                                        context.t(
                                          'auth.continueWith',
                                          variables: {
                                            'provider': provider.displayName,
                                          },
                                        ),
                                        key: const ValueKey('continue'),
                                      ),
                              ),
                            ),
                          ),
                      ],
                      // Discovery is a second request. While it is in flight an
                      // SSO-only server must not be declared misconfigured — on
                      // that server this screen is the only way in.
                      if (!localAuth &&
                          _providers.isEmpty &&
                          _ssoDiscovery == _SsoDiscovery.loading) ...[
                        const SizedBox(height: 20),
                        const Center(child: HiveLoader(size: 28)),
                      ],
                      // The lookup itself failed. Say so and offer another go:
                      // silence here reads as "this server has no SSO", which is
                      // wrong and (in SSO-only mode) a dead end.
                      if (_ssoDiscovery == _SsoDiscovery.failed) ...[
                        const SizedBox(height: 14),
                        Text(
                          context.t('auth.ssoLoadFailed'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: busy ? null : _loadProviders,
                          icon: const Icon(LucideIcons.refreshCw, size: 15),
                          label: Text(context.t('common.retry')),
                        ),
                      ],
                      // SSO-only, and the server really did answer "none" — the
                      // user has no way to sign in; point them at their admin.
                      if (!localAuth &&
                          _providers.isEmpty &&
                          _ssoDiscovery == _SsoDiscovery.done) ...[
                        const SizedBox(height: 16),
                        Text(
                          context.t('auth.ssoOnlyNoProviders'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                      if (localAuth && registrationEnabled) ...[
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              context.t('auth.noAccount'),
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                            TextButton(
                              onPressed: busy
                                  ? null
                                  : () => context.go('/register'),
                              child: Text(context.t('auth.createAccount')),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      const LegalLinks(),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      // Commit the autofill context so the OS/password manager can offer to
      // save or update the entered credentials.
      TextInput.finishAutofillContext();
      context.read<AuthBloc>().add(
        LoginSubmitted(_identifier.text.trim(), _password.text),
      );
    }
  }

  /// The post-password 2FA challenge: a 6-digit OTP (or recovery code) entry.
  Widget _twoFactorPanel(BuildContext context, AuthState state) {
    final busy = state.status == AuthStatus.authenticating;
    return AuthGlassCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            LucideIcons.shieldCheck,
            size: 30,
            color: AppColors.accentStrong,
          ),
          const SizedBox(height: 14),
          Text(
            context.t('auth.twoFactorTitle'),
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            context.t('auth.twoFactorSubtitle'),
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          OtpInput(onChanged: (v) => _otpCode = v),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: busy ? null : _submitOtp,
            child: busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: HiveLoader(
                      size: 22,
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(context.t('auth.verify')),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: busy
                ? null
                : () => context.read<AuthBloc>().add(const LogoutRequested()),
            child: Text(context.t('auth.backToSignIn')),
          ),
        ],
      ),
    );
  }

  void _submitOtp() {
    final code = _otpCode.trim();
    if (code.length < 6) return;
    context.read<AuthBloc>().add(TwoFactorSubmitted(code));
  }

  Future<void> _launchSso(SsoProvider provider) async {
    final serverUrl = context.read<AuthBloc>().storage.serverUrl ?? '';
    var uri = Uri.parse('$serverUrl${provider.loginUrl}');
    setState(() => _launchingSsoId = provider.id);
    try {
      // Let the disabled/loading state actually reach the screen before we
      // hand the tab to the browser. On web `launchUrl('_self')` changes
      // window.location synchronously and tears this page down; a single
      // endOfFrame fires before the rasterized frame is composited, so the
      // loader was being skipped. A short delay lets the browser paint a few
      // frames (loader visible, buttons disabled) first.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (!mounted) return;
      if (kIsWeb) {
        // Web: tell the server where to return; the whole flow stays in this
        // tab and ends at <origin>/auth-callback with the handoff code.
        uri = uri.replace(
          queryParameters: {...uri.queryParameters, 'return': Uri.base.origin},
        );
        final launched = await launchUrl(uri, webOnlyWindowName: '_self');
        // Only keep the buttons disabled if the tab is genuinely on its way to
        // the provider — re-enabling them then would let the user start a
        // second login on top of the first. A refused navigation is the
        // opposite case: nothing is in flight, so leaving the form disabled
        // would strand the user on a login screen they cannot use.
        if (!launched && mounted) {
          setState(() => _launchingSsoId = null);
          showGlassErrorToast(context, context.t('auth.ssoLaunchFailed'));
        }
        return;
      }
      // Native: the server redirects back via hinata://auth-callback.
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      // The external browser took over; restore the buttons so the user can
      // retry if they return without completing the login.
      if (!mounted) return;
      setState(() => _launchingSsoId = null);
      if (!launched) {
        showGlassErrorToast(context, context.t('auth.ssoLaunchFailed'));
      }
    } catch (_) {
      // Launch failed before the redirect — restore the buttons to try again.
      if (!mounted) return;
      setState(() => _launchingSsoId = null);
      showGlassErrorToast(context, context.t('auth.ssoLaunchFailed'));
    }
  }
}
