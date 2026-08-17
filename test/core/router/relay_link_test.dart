/// The link every Hinata e-mail actually carries.
///
/// Nothing in a mail points at an instance directly — it points at the Connect
/// gateway, which hands the app a base64url payload naming the server, the
/// in-app path and (for invite/reset only) a one-time token. This is the single
/// translation step between "the user tapped the button in an e-mail" and "the
/// app opens that screen", so it is worth pinning down exactly.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/router/relay_link.dart';

/// Builds a relay URL the way GatewayService.relayLink does.
Uri relay(Map<String, dynamic> payload, {String sig = 'c2ln'}) {
  final code = base64Url
      .encode(utf8.encode(jsonEncode(payload)))
      .replaceAll('=', '');
  return Uri.parse('https://connect.hinata.ahmadre.com/l/$code.$sig');
}

void main() {
  const server = 'https://track.asta.hn';

  test('opens the issue a notification mail points at', () {
    final link = RelayLink.parse(
      relay({'a': server, 'p': '/issues/HIN-4?comment=c1', 't': null}),
    );

    expect(link?.route, '/issues/HIN-4?comment=c1');
    expect(link?.server, server);
  });

  test('carries an invite token into the route', () {
    final link = RelayLink.parse(
      relay({'a': server, 'p': '/invite', 't': 'tok en/+1'}),
    );

    expect(link?.route, '/invite?token=tok+en%2F%2B1');
  });

  test('merges a token into a route that already has a query', () {
    final link = RelayLink.parse(
      relay({'a': server, 'p': '/admin/users?user=u1', 't': 'abc'}),
    );

    expect(link?.route, '/admin/users?user=u1&token=abc');
  });

  test('reads a payload the gateway left unpadded', () {
    // The gateway encodes without '=' padding; decoding has to add it back or
    // every link whose payload length isn't a multiple of four is thrown away.
    final link = RelayLink.parse(relay({'p': '/board'}));

    expect(link?.route, '/board');
    expect(link?.server, isNull);
  });

  test('ignores a payload that names no screen', () {
    // A bare "/" matches no route, so following it throws "no routes for
    // location" instead of opening anything — a digest mail once shipped one.
    for (final route in <Object?>[null, '', '/', 'issues/HIN-4', 42]) {
      expect(RelayLink.parse(relay({'a': server, 'p': route})), isNull);
    }
  });

  test('ignores garbage rather than throwing', () {
    final garbage = [
      Uri.parse('https://connect.hinata.ahmadre.com/l/'),
      Uri.parse('https://connect.hinata.ahmadre.com/l/....'),
      Uri.parse('https://connect.hinata.ahmadre.com/l/not-base64!!.sig'),
      Uri.parse('https://connect.hinata.ahmadre.com/issues/HIN-4'),
      Uri.parse('https://connect.hinata.ahmadre.com/'),
    ];
    for (final uri in garbage) {
      expect(RelayLink.parse(uri), isNull, reason: '$uri');
    }
    // Valid base64, but not a JSON object.
    expect(
      RelayLink.parse(
        Uri.parse(
          'https://connect.hinata.ahmadre.com/'
          'l/${base64Url.encode(utf8.encode('[1,2]')).replaceAll('=', '')}.sig',
        ),
      ),
      isNull,
    );
  });

  test('still decodes a link the gateway did not sign', () {
    // The signature only guards the gateway's own web redirect; the app decodes
    // locally and the server validates any token anyway.
    final code = base64Url
        .encode(utf8.encode(jsonEncode({'p': '/notifications'})))
        .replaceAll('=', '');
    final link = RelayLink.parse(
      Uri.parse('https://connect.hinata.ahmadre.com/l/$code'),
    );

    expect(link?.route, '/notifications');
  });
}
