import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/widgets/hive_loader.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api/api_client.dart';
import '../../core/repositories/meta_repository.dart';
import '../../core/blocs/app_config_bloc.dart';
import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/soft_card.dart';

/// Rocket.Chat-style first-run wizard: organization + first admin account.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _organization = TextEditingController();
  final _email = TextEditingController();
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  final _password = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in [
      _organization,
      _email,
      _username,
      _displayName,
      _password,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SoftCard(
                padding: const EdgeInsets.all(32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        context.t('setup.title'),
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        context.t('setup.subtitle'),
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 24),
                      _field(
                        _organization,
                        'setup.organization',
                        LucideIcons.building2,
                        textCapitalization: TextCapitalization.words,
                      ),
                      _field(
                        _displayName,
                        'setup.displayName',
                        LucideIcons.idCard,
                        textCapitalization: TextCapitalization.words,
                      ),
                      _field(
                        _email,
                        'setup.email',
                        LucideIcons.atSign,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        autocorrect: false,
                        validator: (v) => v != null && v.contains('@')
                            ? null
                            : context.t('errors.invalidEmail'),
                      ),
                      _field(
                        _username,
                        'setup.username',
                        LucideIcons.user,
                        autocorrect: false,
                        validator: (v) =>
                            RegExp(r'^[a-zA-Z0-9._-]{3,40}$').hasMatch(v ?? '')
                            ? null
                            : context.t('errors.invalidUsername'),
                      ),
                      _field(
                        _password,
                        'setup.password',
                        LucideIcons.lock,
                        obscure: true,
                        validator: (v) => (v ?? '').length >= 10
                            ? null
                            : context.t('errors.passwordTooShort'),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _error!,
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
                                child: HiveLoader(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(context.t('setup.action')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String labelKey,
    IconData icon, {
    bool obscure = false,
    TextInputType? keyboardType,
    List<String>? autofillHints,
    bool autocorrect = true,
    TextCapitalization textCapitalization = TextCapitalization.none,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        autofillHints: autofillHints,
        autocorrect: autocorrect,
        textCapitalization: textCapitalization,
        decoration: InputDecoration(
          labelText: context.t(labelKey),
          prefixIcon: Icon(icon),
        ),
        validator:
            validator ??
            (v) => (v == null || v.trim().isEmpty)
                ? context.t('errors.required')
                : null,
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await context.read<MetaRepository>().completeSetup(
        organizationName: _organization.text.trim(),
        adminEmail: _email.text.trim(),
        adminUsername: _username.text.trim(),
        adminDisplayName: _displayName.text.trim(),
        adminPassword: _password.text,
      );
      if (mounted) {
        context.read<AppConfigBloc>().add(const SetupFinished());
      }
    } on ApiFailure catch (failure) {
      setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
