import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/util/reader_time_zone.dart';

/// The zone id travels to the server as a query parameter on a download, so
/// whatever the platform answers with is checked before it is put in a URL.
/// The server ignores what it cannot parse, which makes this belt and braces —
/// but a value from a platform channel is still a value from outside the app.
void main() {
  group('looksLikeZoneId', () {
    test('accepts the shapes the tz database actually uses', () {
      for (final zone in <String>[
        'Europe/Berlin',
        'America/Argentina/Buenos_Aires',
        'Asia/Ho_Chi_Minh',
        'Etc/GMT+5',
        'America/Port-au-Prince',
        'UTC',
        'Zulu',
      ]) {
        expect(ReaderTimeZone.looksLikeZoneId(zone), isTrue, reason: zone);
      }
    });

    test('refuses anything that is not one', () {
      for (final wrong in <String>[
        '',
        ' ',
        '/Berlin',
        'Europe//Berlin',
        'Europe/Berlin?x=1',
        'Europe/Berlin&tz=x',
        'Europe/Berlin/../../etc/passwd',
        'Europe/Ber lin',
        'Europe/Berlin\nX-Injected: 1',
        'Zone/With/Too/Many/Parts',
      ]) {
        expect(
          ReaderTimeZone.looksLikeZoneId(wrong),
          isFalse,
          reason: 'accepted ${wrong.replaceAll('\n', r'\n')}',
        );
      }
    });

    test('refuses an answer long enough to be something else', () {
      expect(ReaderTimeZone.looksLikeZoneId('A/${'b' * 200}'), isFalse);
    });
  });
}
