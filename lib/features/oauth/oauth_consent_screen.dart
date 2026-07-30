import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_client.dart';
import '../../core/repositories/auth_repository.dart';
import '../../core/blocs/app_config_bloc.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/oauth_consent.dart';
import '../../core/models/personal_access_token.dart' show patScopeKey;
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hex_mark.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/soft_card.dart';
import '../sprint/modals/glass_modal.dart' show showGlassErrorToast;

/// The OAuth 2.1 consent screen an AI client (e.g. Claude) lands the user on
/// when it starts an authorization flow against their Hinata instance.
///
/// The backend validates `GET /oauth/authorize?...` and 302-redirects the
/// browser here, to `/oauth-consent?request_id=<id>`. The router already gates
/// this route behind authentication (an unauthenticated user is bounced to
/// `/login` and returned here, query param intact). This page fetches the
/// pending request, shows the requesting client + scopes, and on Allow/Deny
/// hard-navigates the browser to the `redirectUri` the backend returns (the AI
/// client's callback). Web-only — the connector flow runs in a browser.
class OAuthConsentScreen extends StatefulWidget {
  const OAuthConsentScreen({super.key, required this.requestId});

  final String requestId;

  @override
  State<OAuthConsentScreen> createState() => _OAuthConsentScreenState();
}

class _OAuthConsentScreenState extends State<OAuthConsentScreen> {
  AuthRepository get _repo => context.read<AuthRepository>();

  OAuthConsentInfo? _info;
  bool _loading = true;

  /// True once the request could not be loaded (unknown/expired link, or a
  /// transport error) — the screen shows the "please retry" state.
  bool _failed = false;

  /// True while a decision POST + browser redirect is in flight. Stays true
  /// after a successful decision (the tab is on its way to the AI client).
  bool _deciding = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.requestId.isEmpty) {
      setState(() {
        _failed = true;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final info = await _repo.oauthConsentInfo(widget.requestId);
      if (mounted) {
        setState(() {
          _info = info;
          _loading = false;
        });
      }
    } catch (_) {
      // A 404 (unknown/expired request) or any transport error resolves to the
      // same friendly "retry from your AI client" state.
      if (mounted) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  Future<void> _decide(bool approved) async {
    final info = _info;
    if (info == null || _deciding) return;
    setState(() => _deciding = true);
    try {
      final redirectUri = await _repo.oauthConsentDecision(
        info.requestId,
        approved: approved,
        grantedScopes: info.scopes,
      );
      if (!mounted) return;
      // Hand the browser back to the AI client's callback. On web this is a hard
      // same-tab navigation that tears this page down; keep [_deciding] true so
      // no second decision can start while the redirect is in flight.
      final uri = Uri.tryParse(redirectUri);
      if (uri != null) {
        await launchUrl(
          uri,
          webOnlyWindowName: kIsWeb ? '_self' : null,
          mode: kIsWeb
              ? LaunchMode.platformDefault
              : LaunchMode.externalApplication,
        );
      }
    } on ApiFailure catch (f) {
      if (mounted) {
        setState(() => _deciding = false);
        showGlassErrorToast(context, context.t(f.message));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _deciding = false);
        showGlassErrorToast(context, context.t('errors.unexpected'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: _body(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) {
      return const SoftCard(
        padding: EdgeInsets.symmetric(vertical: 56),
        child: Center(child: HiveLoader()),
      );
    }
    if (_failed || _info == null) {
      return SoftCard(
        padding: const EdgeInsets.all(28),
        child: HiveEmptyState(
          card: false,
          title: context.t('oauthConsent.expired.title'),
          message: context.t('oauthConsent.expired.message'),
        ),
      );
    }
    return _ConsentCard(
      info: _info!,
      busy: _deciding,
      onAllow: () => _decide(true),
      onDeny: () => _decide(false),
    );
  }
}

/// The consent card itself: brand mark, "`<client>` wants to access your
/// Hinata account", the requested scopes and the redirect target, and
/// Allow/Deny.
class _ConsentCard extends StatelessWidget {
  const _ConsentCard({
    required this.info,
    required this.busy,
    required this.onAllow,
    required this.onDeny,
  });

  final OAuthConsentInfo info;
  final bool busy;
  final VoidCallback onAllow;
  final VoidCallback onDeny;

  @override
  Widget build(BuildContext context) {
    final organization = context.select(
      (AppConfigBloc bloc) => bloc.state.meta?.organizationName,
    );
    final product = organization ?? 'Hinata';
    return SoftCard(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: HexMark(size: 40)),
          const SizedBox(height: 20),
          Text(
            context.t(
              'oauthConsent.title',
              variables: {'client': info.clientName},
            ),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.t(
              'oauthConsent.subtitle',
              variables: {'client': info.clientName, 'product': product},
            ),
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.inkSoft, fontSize: 13.5),
          ),
          const SizedBox(height: 24),
          Text(
            context.t('oauthConsent.scopesHeader'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.inkSoft,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 12),
          if (info.scopes.isEmpty)
            Text(
              context.t('oauthConsent.noScopes'),
              style: TextStyle(fontSize: 13, color: AppColors.inkFaint),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                border: Border.all(color: AppColors.hairline2),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < info.scopes.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: AppColors.hairline2),
                    _ScopeRow(scope: info.scopes[i]),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 16),
          _RedirectNote(host: info.redirectHost),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: busy ? null : onAllow,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.navy,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              ),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: busy
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
                      context.t('oauthConsent.allow'),
                      key: const ValueKey('label'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: busy ? null : onDeny,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.inkSoft,
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
            child: Text(context.t('oauthConsent.deny')),
          ),
        ],
      ),
    );
  }
}

/// One requested scope: a friendly label (from the shared `pat.scope.*` keys,
/// falling back to the raw id) above the mono scope id.
class _ScopeRow extends StatelessWidget {
  const _ScopeRow({required this.scope});

  final String scope;

  @override
  Widget build(BuildContext context) {
    final key = patScopeKey(scope);
    final label = context.t(key);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          const Icon(LucideIcons.check, size: 16, color: AppColors.success),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label == key ? scope : label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  scope,
                  style: TextStyle(
                    fontFamily: AppTheme.fontMono,
                    fontSize: 11,
                    color: AppColors.inkFaint,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The "you'll be sent back to `<host>`" reassurance line.
class _RedirectNote extends StatelessWidget {
  const _RedirectNote({required this.host});

  final String host;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(LucideIcons.externalLink, size: 15, color: AppColors.inkFaint),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            context.t('oauthConsent.redirectNote', variables: {'host': host}),
            style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
          ),
        ),
      ],
    );
  }
}
