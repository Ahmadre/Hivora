import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/widgets/hive_loader.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/blocs/app_config_bloc.dart';
import '../../core/i18n/i18n.dart';
import '../../core/storage/app_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/hex_mark.dart';
import '../../core/widgets/soft_card.dart';
import 'server_switcher.dart';

/// First screen: the app cannot run without a server, so we ask for its URL
/// and only continue once /api/v1/meta answers.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _controller = TextEditingController(text: 'https://');
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
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
              constraints: const BoxConstraints(maxWidth: 440),
              child: BlocBuilder<AppConfigBloc, AppConfigState>(
                builder: (context, state) {
                  final connecting = state.status == AppConfigStatus.connecting;
                  return SoftCard(
                    padding: const EdgeInsets.all(32),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Center(child: HivBrandLockup(hexSize: 64)),
                          const SizedBox(height: 24),
                          Text(
                            context.t('connect.title'),
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            context.t('connect.subtitle'),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: _controller,
                            enabled: !connecting,
                            keyboardType: TextInputType.url,
                            autofillHints: const [AutofillHints.url],
                            autocorrect: false,
                            textInputAction: TextInputAction.done,
                            decoration: InputDecoration(
                              hintText: 'https://hinata.example.org',
                              prefixIcon: const Icon(LucideIcons.server),
                              labelText: context.t('connect.serverUrl'),
                            ),
                            validator: (value) {
                              final uri = Uri.tryParse(value?.trim() ?? '');
                              if (uri == null ||
                                  uri.host.isEmpty ||
                                  !(uri.isScheme('http') ||
                                      uri.isScheme('https'))) {
                                return context.t('connect.invalidUrl');
                              }
                              return null;
                            },
                            onFieldSubmitted: (_) => _submit(),
                          ),
                          if (state.errorKey != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              context.t(state.errorKey!),
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: AppColors.danger),
                            ),
                          ],
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: connecting ? null : _submit,
                            child: connecting
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: HiveLoader(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(context.t('connect.action')),
                          ),
                          ..._savedServers(context, connecting),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      context.read<AppConfigBloc>().add(
        ServerUrlSubmitted(_controller.text.trim()),
      );
    }
  }

  /// Previously connected servers, offered as one-tap shortcuts below the URL
  /// field — handy when re-connecting (e.g. after a server was unreachable) or
  /// hopping between several backends. Empty on a truly first launch.
  List<Widget> _savedServers(BuildContext context, bool connecting) {
    final servers = context.read<AppStorage>().servers;
    if (servers.isEmpty) return const [];
    return [
      const SizedBox(height: 24),
      Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              context.t('server.saved'),
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
          const Expanded(child: Divider()),
        ],
      ),
      const SizedBox(height: 8),
      for (final server in servers)
        ListTile(
          dense: true,
          enabled: !connecting,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(
            LucideIcons.server,
            size: 18,
            color: AppColors.accentStrong,
          ),
          title: Text(
            server.displayName,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            server.host,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          trailing: const Icon(LucideIcons.chevronRight, size: 18),
          onTap: connecting ? null : () => switchToServer(context, server.url),
        ),
    ];
  }
}
