/// Keys are typed once and then live in every issue id, so the suggestion has
/// to be both predictable and legal: `[A-Z][A-Z0-9]{1,9}`, which is what the
/// server enforces.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/util/keys.dart';

void main() {
  final legal = RegExp(r'^[A-Z][A-Z0-9]{1,9}$');

  group('suggestKey', () {
    test('a single word gives its opening letters', () {
      expect(suggestKey('Hinata'), 'HIN');
      expect(suggestKey('Mobile'), 'MOB');
      // Shorter than three letters is still a legal key.
      expect(suggestKey('Ops'), 'OPS');
      expect(suggestKey('Hr'), 'HR');
    });

    test('several words give their initials', () {
      expect(suggestKey('Board Views'), 'BV');
      expect(suggestKey('Asta Kultur Referat'), 'AKR');
      expect(suggestKey('Billing & Plans'), 'BP');
      // Four initials is the cap.
      expect(suggestKey('One Two Three Four Five'), 'OTTF');
    });

    test('German names keep their meaning', () {
      expect(suggestKey('Öffentlichkeit'), 'OEF');
      expect(suggestKey('Übergabe Team'), 'UT');
      expect(suggestKey('Straße'), 'STR');
    });

    test('a key never starts with a digit and is never too short', () {
      expect(suggestKey('3D Modelling'), 'DM');
      expect(suggestKey('42'), '');
      expect(suggestKey('  '), '');
      expect(suggestKey('X'), '');
      for (final name in ['3D Modelling', 'Übergabe Team', 'Hinata']) {
        expect(legal.hasMatch(suggestKey(name)), isTrue, reason: name);
      }
    });

    test('long names are cut to the server limit', () {
      final key = suggestKey('Öffentlichkeitsarbeitsgruppe');
      expect(key.length, lessThanOrEqualTo(kMaxKeyLength));
      expect(legal.hasMatch(key), isTrue);
    });

    test('a taken key is stepped around, not handed out twice', () {
      expect(suggestKey('Mobile', taken: {'MOB'}), 'MOB2');
      expect(suggestKey('Mobile', taken: {'MOB', 'MOB2'}), 'MOB3');
      // Case does not buy you a free key.
      expect(suggestKey('Mobile', taken: {'mob'}), 'MOB2');
    });

    test('the number fits inside the limit, it does not push past it', () {
      final key = suggestKey('Mobile', taken: {'MOB'}, maxLength: 4);
      expect(key.length, lessThanOrEqualTo(4));
      expect(legal.hasMatch(key), isTrue);
    });
  });

  group('isGeneratedKey', () {
    test('recognises its own output', () {
      expect(isGeneratedKey('HIN', 'Hinata'), isTrue);
      expect(isGeneratedKey('hin', 'Hinata'), isTrue);
      expect(isGeneratedKey('', 'Hinata'), isTrue);
    });

    test('a key somebody chose is left alone', () {
      expect(isGeneratedKey('CORE', 'Hinata'), isFalse);
      expect(isGeneratedKey('MOB2', 'Mobile'), isFalse);
    });
  });
}
