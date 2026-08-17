import 'dart:convert';

/// A Hinata Connect relay link, decoded.
///
/// Every e-mail the server sends links through the gateway rather than straight
/// at the instance: `https://connect.hinata.ahmadre.com/l/<base64url(payload)>.<sig>`.
/// One verified domain means invite / reset / notification links from *any*
/// self-hosted server open the published app, and the gateway can still redirect
/// a browser that has no app installed.
///
/// The payload carries the originating server's API URL (`a`), the in-app path
/// (`p`) and, for the invite/reset flows only, a one-time token (`t`) — plain
/// notification links (mentions, assignments, …) omit it. We decode it locally:
/// the gateway's signature only protects its own web-fallback redirect, and a
/// token, where there is one, is validated server-side anyway.
class RelayLink {
  const RelayLink({required this.route, this.server});

  /// The in-app route to open, query string and token already merged in.
  final String route;

  /// The server the link came from, so a freshly installed app knows which
  /// backend to talk to. Null when the payload names none.
  final String? server;

  /// Decodes [uri], or returns null if it is not a relay link we can act on.
  ///
  /// Anything malformed — a truncated payload, a corrupted base64 segment, a
  /// payload that names no real route — yields null rather than throwing. A
  /// route of `/` counts as "no real route": it matches no screen, and routing
  /// it would only throw "no routes for location" (which is how a weekly-digest
  /// link once managed to look like a crash).
  static RelayLink? parse(Uri uri) {
    if (uri.pathSegments.length < 2 || uri.pathSegments.first != 'l') {
      return null;
    }
    final segment = uri.pathSegments[1];
    final dot = segment.indexOf('.');
    final b64 = dot > 0 ? segment.substring(0, dot) : segment;
    if (b64.isEmpty) return null;

    final Map<String, dynamic> payload;
    try {
      final padded = b64.padRight((b64.length + 3) ~/ 4 * 4, '=');
      payload =
          jsonDecode(utf8.decode(base64Url.decode(padded)))
              as Map<String, dynamic>;
    } catch (_) {
      return null;
    }

    final route = payload['p'];
    if (route is! String || !route.startsWith('/') || route.length <= 1) {
      return null;
    }
    final token = payload['t'];
    final server = payload['a'];

    // `route` may already carry its own query string (e.g. "/admin/users?user=…"),
    // so merge rather than appending a second "?".
    final q = route.indexOf('?');
    final path = q < 0 ? route : route.substring(0, q);
    final query = <String>[
      if (q >= 0) route.substring(q + 1),
      if (token is String && token.isNotEmpty)
        'token=${Uri.encodeQueryComponent(token)}',
    ];

    return RelayLink(
      route: query.isEmpty ? path : '$path?${query.join('&')}',
      server: server is String && server.isNotEmpty ? server : null,
    );
  }
}
