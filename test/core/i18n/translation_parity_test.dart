import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/i18n/i18n.dart';

/// Every language the app claims to speak must actually answer to every key.
///
/// A missing key is not a crash and not a compile error — i18next hands back
/// the key itself, so the screen renders `admin.um.colUser` and nobody finds
/// out until a reader of that language opens it. A dropped `{{count}}` is
/// worse: the sentence still looks like a sentence, with the number gone.
///
/// So the bundles are diffed against English here, which is the only place
/// this can be caught before somebody hits it. This test is why adding a
/// language is a file rather than a search through 2000 strings.
void main() {
  final english = _flatten(_load('en'));

  test('every supported locale ships a bundle', () {
    for (final locale in I18n.supportedLocales) {
      final file = File('assets/i18n/${locale.languageCode}/common.json');
      expect(
        file.existsSync(),
        isTrue,
        reason:
            'I18n.supportedLocales offers ${locale.languageCode} but '
            '${file.path} does not exist — the picker would show a language '
            'that renders as raw keys.',
      );
    }
  });

  test('every supported locale is named in the picker', () {
    for (final locale in I18n.supportedLocales) {
      expect(
        I18n.localeNames[locale.languageCode],
        isNotNull,
        reason:
            '${locale.languageCode} has no entry in I18n.localeNames, so the '
            'language picker would list its bare code.',
      );
    }
  });

  for (final locale in I18n.supportedLocales) {
    final code = locale.languageCode;
    if (code == 'en') continue;

    group(code, () {
      late final Map<String, String> translated;

      setUpAll(() => translated = _flatten(_load(code)));

      test('answers to exactly the English key set', () {
        final missing = english.keys.where((k) => !translated.containsKey(k));
        final unknown = translated.keys.where((k) => !english.containsKey(k));
        expect(
          missing,
          isEmpty,
          reason:
              '$code is missing ${missing.length} key(s) — they would '
              'render as raw keys',
        );
        expect(unknown, isEmpty, reason: '$code has keys English does not');
      });

      test('keeps every interpolation placeholder', () {
        final placeholder = RegExp(r'\{\{[^}]*\}\}');
        for (final entry in english.entries) {
          final mine = translated[entry.key];
          if (mine == null) continue;
          expect(
            placeholder.allMatches(mine).map((m) => m[0]).toSet(),
            placeholder.allMatches(entry.value).map((m) => m[0]).toSet(),
            reason:
                '$code:${entry.key} does not carry the same placeholders — '
                'the value would be missing from the rendered sentence',
          );
        }
      });
    });
  }
}

Map<String, dynamic> _load(String code) =>
    json.decode(File('assets/i18n/$code/common.json').readAsStringSync())
        as Map<String, dynamic>;

/// `{"a": {"b": "c"}}` -> `{"a.b": "c"}`.
Map<String, String> _flatten(Map<String, dynamic> node, [String prefix = '']) {
  final out = <String, String>{};
  node.forEach((key, value) {
    final path = prefix.isEmpty ? key : '$prefix.$key';
    if (value is Map<String, dynamic>) {
      out.addAll(_flatten(value, path));
    } else {
      out[path] = '$value';
    }
  });
  return out;
}
