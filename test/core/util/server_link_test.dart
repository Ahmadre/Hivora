import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/util/server_link.dart';

/// The rules a deep link's `server` parameter has to pass before the app will
/// talk to it.
///
/// This is the gate in front of every token-carrying link — invite, password
/// reset, e-mail verification — so the interesting cases are the ones where
/// being slightly too strict breaks a legitimate self-hosted setup, and being
/// slightly too loose hands a password to somebody else's backend.
void main() {
  const known = ['https://track.asta.hn', 'http://localhost:8080'];

  group('normalizeServerLink', () {
    test('takes any https server, known or not', () {
      // Not knowing the server yet is the normal case for an invite; that is
      // what the caller's confirmation dialog is for.
      expect(
        normalizeServerLink('https://new.example.org', known: known),
        'https://new.example.org',
      );
      expect(
        normalizeServerLink('https://track.asta.hn', known: known),
        'https://track.asta.hn',
      );
    });

    test('keeps a sub-path deployment intact', () {
      // Reducing this to its origin would point every later request at the
      // wrong place while still looking right in the confirmation dialog.
      expect(
        normalizeServerLink('https://example.com/hinata', known: known),
        'https://example.com/hinata',
      );
    });

    test('normalizes the way the connect screen does', () {
      expect(
        normalizeServerLink('  https://example.com/  ', known: known),
        'https://example.com',
      );
      expect(
        normalizeServerLink('https://example.com:3356', known: known),
        'https://example.com:3356',
      );
    });

    test('takes http only for a server the device already uses', () {
      // The LAN and localhost deployments this app supports keep working…
      expect(
        normalizeServerLink('http://localhost:8080', known: known),
        'http://localhost:8080',
      );
      expect(
        normalizeServerLink('http://localhost:8080/', known: known),
        'http://localhost:8080',
      );
      // …while the shape that is only ever an attack does not: a link
      // introducing a brand-new unencrypted backend, on a screen that is about
      // to ask for a password.
      expect(normalizeServerLink('http://attacker.tld', known: known), isNull);
      expect(
        normalizeServerLink('http://192.168.1.50:8080', known: known),
        isNull,
      );
    });

    test('refuses anything that is not a server URL', () {
      for (final raw in [
        null,
        '',
        '   ',
        '/',
        'https://',
        'not a url',
        'javascript:alert(1)',
        'file:///etc/passwd',
        'hinata://auth-callback',
        'ftp://example.com',
      ]) {
        expect(
          normalizeServerLink(raw, known: known),
          isNull,
          reason: 'accepted $raw',
        );
      }
    });

    test('without a known list, only https passes', () {
      expect(normalizeServerLink('https://example.com'), 'https://example.com');
      expect(normalizeServerLink('http://localhost:8080'), isNull);
    });
  });
}
