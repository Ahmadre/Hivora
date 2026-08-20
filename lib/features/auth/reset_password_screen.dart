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

/// Lands here from the reset deep link (web URL or `hinata://reset-password`).
/// Lets the user choose a new password in the app's UI, then signs them in.
/// [server] (carried by the link) points a freshly opened web/app at the right
/// backend.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, required this.token, this.server});

  final String token;
  final String? server;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _submitting = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // After the first frame, not during initState: applying the server named in
    // the link reads localized strings, and an inherited-widget lookup from a
    // state that is still being created trips an assertion that an async method
    // swallows into its future. Same reason verify_email_screen defers.
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyServer());
  }

  /// Point a freshly opened web/app at the backend named in the link —
  /// validated + consent-gated (see [applyServerFromLink]).
  Future<void> _applyServer() => applyServerFromLink(context, widget.server);

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final tokens = await context.read<AuthRepository>().acceptPasswordReset(
        widget.token,
        _password.text,
      );
      if (!mounted) return;
      // New password accepted — let the password manager offer to update the
      // stored credential.
      TextInput.finishAutofillContext();
      context.read<AuthBloc>().add(
        SsoTokensReceived(tokens.access, tokens.refresh),
      );
      context.go('/dashboard');
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = failure.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final invalid = widget.token.isEmpty;
    return AuthShell(
      maxContentWidth: 460,
      child: AuthGlassCard(child: invalid ? _invalid(context) : _form(context)),
    );
  }

  Widget _invalid(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          LucideIcons.triangleAlert,
          size: 40,
          color: AppColors.danger,
        ),
        const SizedBox(height: 16),
        Text(
          context.t('reset.invalidTitle'),
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          context.t('reset.invalidBody'),
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => context.go('/login'),
          child: Text(context.t('reset.goToLogin')),
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
      // Pairs the new + confirm password fields so a manager can capture and
      // save the updated password.
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.t('reset.title'),
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              context.t('reset.subtitle'),
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              autofocus: true,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: context.t('reset.passwordLabel'),
                hintText: context.t('reset.passwordHint'),
                prefixIcon: const Icon(LucideIcons.lock),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? LucideIcons.eye : LucideIcons.eyeOff),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) => (v ?? '').length >= passwordMin
                  ? null
                  : context.t(
                      'errors.passwordTooShort',
                      variables: {'min': passwordMin},
                    ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _confirm,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: context.t('reset.confirmLabel'),
                prefixIcon: const Icon(LucideIcons.lock),
              ),
              onFieldSubmitted: (_) => _submit(),
              validator: (v) => (v == _password.text)
                  ? null
                  : context.t('errors.passwordsDoNotMatch'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                context.t(_error!),
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
                  : Text(context.t('reset.updatePassword')),
            ),
          ],
        ),
      ),
    );
  }
}
