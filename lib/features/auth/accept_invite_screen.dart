import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInput;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/repositories/auth_repository.dart';
import '../../core/blocs/app_config_bloc.dart';
import '../../core/blocs/auth_bloc.dart';
import '../../core/i18n/i18n.dart';
import '../../core/util/server_link.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/hive_loader.dart';
import 'auth_shell.dart';

/// Lands here from the invitation deep link (web URL or `hinata://invite`).
/// Validates the invitation, lets the invitee set a password in the app's UI,
/// then signs them in. [server] (carried by the link) points a freshly opened
/// web/app at the right backend.
class AcceptInviteScreen extends StatefulWidget {
  const AcceptInviteScreen({super.key, required this.token, this.server});

  final String token;
  final String? server;

  @override
  State<AcceptInviteScreen> createState() => _AcceptInviteScreenState();
}

class _AcceptInviteScreenState extends State<AcceptInviteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();

  bool _loading = true;
  bool _submitting = false;
  bool _obscure = true;
  String? _email;
  String? _loadError; // token invalid/expired
  String? _submitError;

  @override
  void initState() {
    super.initState();
    // After the first frame, not during initState: the first thing _init does
    // is apply the server named in the link, which reads localized strings —
    // and an inherited-widget lookup from a state that is still being created
    // trips an assertion that an async method swallows into its future, so the
    // screen would sit on its spinner forever. Same reason verify_email_screen
    // defers.
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    await _applyServer();
    if (!mounted) return;
    await _loadInfo();
  }

  /// Point a freshly opened web/app at the backend named in the link before any
  /// API call resolves — validated + consent-gated (see [applyServerFromLink]).
  Future<void> _applyServer() => applyServerFromLink(context, widget.server);

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _loadInfo() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final info = await context.read<AuthRepository>().inviteInfo(
        widget.token,
      );
      if (!mounted) return;
      setState(() {
        _email = info.email;
        _loading = false;
      });
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = failure.message;
      });
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final tokens = await context.read<AuthRepository>().acceptInvite(
        widget.token,
        _password.text,
      );
      if (!mounted) return;
      // Password set — let the password manager offer to save the new
      // credential for this account.
      TextInput.finishAutofillContext();
      context.read<AuthBloc>().add(
        SsoTokensReceived(tokens.access, tokens.refresh),
      );
      context.go('/dashboard');
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = failure.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      maxContentWidth: 460,
      child: AuthGlassCard(
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: HiveLoader()),
              )
            : _loadError != null
            ? _invalid(context)
            : _form(context),
      ),
    );
  }

  Widget _invalid(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(LucideIcons.mailWarning, size: 40, color: AppColors.danger),
        const SizedBox(height: 16),
        Text(
          context.t('invite.invalidTitle'),
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          context.t('invite.invalidBody'),
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => context.go('/login'),
          child: Text(context.t('invite.goToLogin')),
        ),
      ],
    );
  }

  Widget _form(BuildContext context) {
    final passwordMin = context.select(
      (AppConfigBloc b) => b.state.meta?.passwordMinLength ?? 10,
    );
    return Form(
      key: _formKey,
      // Lets a password manager capture the new password (and offer to save it
      // for this invited account) on submit.
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.t('invite.title'),
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              context.t('invite.subtitle', variables: {'email': _email ?? ''}),
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              autofocus: true,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: context.t('invite.passwordLabel'),
                hintText: context.t('invite.passwordHint'),
                prefixIcon: const Icon(LucideIcons.lock),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? LucideIcons.eye : LucideIcons.eyeOff),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              onFieldSubmitted: (_) => _submit(),
              validator: (v) => (v ?? '').length >= passwordMin
                  ? null
                  : context.t(
                      'errors.passwordTooShort',
                      variables: {'min': passwordMin},
                    ),
            ),
            if (_submitError != null) ...[
              const SizedBox(height: 8),
              Text(
                context.t(_submitError!),
                style: const TextStyle(color: AppColors.danger),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: HiveLoader(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(context.t('invite.createAccount')),
            ),
          ],
        ),
      ),
    );
  }
}
