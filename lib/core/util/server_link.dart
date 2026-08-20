import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../features/sprint/modals/glass_modal.dart'
    show GlassToastKind, showGlassConfirm, showGlassToast;
import '../blocs/app_config_bloc.dart';
import '../i18n/i18n.dart';
import '../storage/app_storage.dart';

/// Validates a deep-link `server` parameter and returns the URL to use, or
/// `null` when the value must not be trusted.
///
/// [known] is every server this device already talks to — the current one and
/// the saved ones. It is what decides the `http` question: a link may always
/// name an **https** server, because the confirmation the caller shows is only
/// meaningful if the connection behind it is authenticated, but a plain `http`
/// server is accepted **only when the device already uses that exact URL**.
/// That keeps the self-hosted LAN and localhost setups this app supports
/// working, while refusing the one shape that is purely an attack: a link
/// introducing a brand-new unencrypted backend, on a screen that is about to
/// ask for a password.
///
/// The value is normalized the way [ServerUrlSubmitted] normalizes what the
/// connect screen accepts — trimmed, one trailing slash removed — and **the
/// path is kept**. `https://example.com/hinata` is a server this app supports
/// (a deployment behind a sub-path), and reducing it to its origin would point
/// every later request at the wrong place.
String? normalizeServerLink(String? raw, {Iterable<String> known = const []}) {
  if (raw == null) return null;
  var url = raw.trim();
  if (url.endsWith('/')) url = url.substring(0, url.length - 1);
  if (url.isEmpty) return null;
  final uri = Uri.tryParse(url);
  if (uri == null ||
      !(uri.isScheme('https') || uri.isScheme('http')) ||
      uri.host.isEmpty) {
    return null;
  }
  if (uri.isScheme('https')) return url;
  return known.contains(url) ? url : null;
}

/// The servers this device already talks to: the selected one first, then the
/// saved list. Both the validation above and the "do we need to ask?" decision
/// below read the same set, so a server can never be trusted by one and not the
/// other.
List<String> knownServers(AppStorage storage) => [
  ?storage.serverUrl,
  for (final profile in storage.servers) profile.url,
];

/// Safely applies the backend named in an auth deep link (`/invite`,
/// `/reset-password`, `/verify-email`).
///
/// A crafted link could otherwise silently repoint the app at an attacker
/// backend and phish credentials/tokens. So: a value that [normalizeServerLink]
/// refuses is reported and ignored; a server this device already uses is
/// applied silently; anything else asks the user first, naming the host.
///
/// Call it after the first frame, not from `initState`. It reads localized
/// strings, and looking an inherited widget up while the state is still being
/// created trips an assertion that — because this method is async — is captured
/// into the returned future instead of thrown, leaving the caller waiting on a
/// future that never completes.
Future<void> applyServerFromLink(BuildContext context, String? raw) async {
  final storage = context.read<AppStorage>();
  final known = knownServers(storage);
  final server = normalizeServerLink(raw, known: known);
  if (server == null) {
    if (raw != null && raw.isNotEmpty && context.mounted) {
      showGlassToast(
        context,
        context.t('auth.serverLink.invalid'),
        kind: GlassToastKind.error,
      );
    }
    return;
  }
  if (!known.contains(server)) {
    final ok = await showGlassConfirm(
      context,
      icon: LucideIcons.serverCog,
      title: context.t('auth.serverLink.title'),
      message: context.t(
        'auth.serverLink.body',
        variables: {'host': Uri.parse(server).host},
      ),
      confirmLabel: context.t('auth.serverLink.confirm'),
    );
    if (ok != true) return;
  }
  if (!context.mounted) return;
  if (storage.serverUrl != server) {
    await storage.setServerUrl(server);
    if (context.mounted) {
      context.read<AppConfigBloc>().add(ServerUrlSubmitted(server));
    }
  }
}
