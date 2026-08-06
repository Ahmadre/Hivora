import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/util/dates.dart';

/// The duration half of the wire contract.
///
/// A few server settings are a `java.time.Duration`, which arrives as `PT5S`
/// rather than as a number — and the admin panel renders them in a field
/// labelled "seconds". Getting this wrong is silent in the direction that
/// matters: the field shows a default, the admin saves it, and the classifier
/// timeout they set last month is quietly replaced.
void main() {
  group('parseIsoSeconds', () {
    test('reads the plain seconds form the server sends', () {
      expect(parseIsoSeconds('PT5S'), 5);
      expect(parseIsoSeconds('PT45S'), 45);
    });

    test('reads the forms Java normalises larger values into', () {
      // Duration.ofSeconds(60).toString() is "PT1M", never "PT60S" — a parser
      // that only understood seconds would show this field as empty.
      expect(parseIsoSeconds('PT1M'), 60);
      expect(parseIsoSeconds('PT1M30S'), 90);
      expect(parseIsoSeconds('PT2H'), 7200);
    });

    test('rounds a fractional second rather than dropping it', () {
      expect(parseIsoSeconds('PT1.500S'), 2);
      expect(parseIsoSeconds('PT7.000000000S'), 7);
    });

    test(
      'returns null for anything it cannot read, so callers can default',
      () {
        expect(parseIsoSeconds(null), isNull);
        expect(parseIsoSeconds(''), isNull);
        expect(parseIsoSeconds('5'), isNull);
        expect(parseIsoSeconds(5), isNull);
        expect(parseIsoSeconds('PT0S'), isNull);
        expect(parseIsoSeconds('tomorrow'), isNull);
      },
    );
  });

  test('isoSeconds writes the form the server parses back', () {
    expect(isoSeconds(5), 'PT5S');
    expect(isoSeconds(90), 'PT90S');
    // Round-trips, which is the only property the panel actually depends on.
    expect(parseIsoSeconds(isoSeconds(42)), 42);
  });
}
