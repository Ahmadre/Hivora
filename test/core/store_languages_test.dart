/// Every store's idea of which languages this app speaks, checked against the
/// app's own list.
///
/// The App Store's "Languages" row, the Microsoft Store's "Supported languages"
/// and an Android bundle's locale splits are all read from the *build*, not from
/// the code. A Flutter app that translates at runtime — from `assets/i18n`, as
/// this one does — ships no `.lproj` folders and no `values-<lang>` resources,
/// so each platform has to be told. Until it was, the App Store listed English
/// for an app that speaks nine languages.
///
/// Five platforms now repeat that list, which is five chances to add a tenth
/// language and tell only some of them. This is the thing that notices.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/i18n/i18n.dart';

void main() {
  final expected = I18n.supportedLocales
      .map((l) => l.languageCode)
      .toList(growable: false);

  /// The strings inside the `CFBundleLocalizations` array of a plist.
  List<String> plistLocalizations(String path) {
    final text = File(path).readAsStringSync();
    final key = text.indexOf('<key>CFBundleLocalizations</key>');
    expect(
      key,
      isNot(-1),
      reason:
          '$path must declare CFBundleLocalizations — without it Apple '
          'infers the languages from .lproj folders this app does not have, '
          'and lists the development region alone',
    );
    final open = text.indexOf('<array>', key);
    final close = text.indexOf('</array>', open);
    return RegExp(r'<string>([^<]+)</string>')
        .allMatches(text.substring(open, close))
        .map((m) => m.group(1)!)
        .toList(growable: false);
  }

  test('the iOS bundle declares every language the app speaks', () {
    expect(plistLocalizations('ios/Runner/Info.plist'), expected);
  });

  test('and so does the macOS bundle', () {
    expect(plistLocalizations('macos/Runner/Info.plist'), expected);
  });

  // Play has no "languages" field to fix; this keeps the bundle's resource
  // filter honest with the app instead — see the note in build.gradle.kts.
  test('the Android bundle keeps the resources for all of them', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final call = RegExp(
      r'resourceConfigurations\s*\+?=\s*listOf\(([^)]*)\)',
    ).firstMatch(gradle);
    expect(
      call,
      isNotNull,
      reason:
          'without a filter the bundle ships every locale AndroidX and the '
          'plugins carry, which is not the set this app can speak',
    );
    final declared = RegExp('"([^"]+)"')
        .allMatches(call!.group(1)!)
        .map((m) => m.group(1)!)
        .toList(growable: false);
    expect(declared, expected);
  });

  test('the Linux stores are told, and told the truth', () {
    final metainfo = File(
      'packaging/linux/com.ahmadre.hinata.metainfo.xml',
    ).readAsStringSync();
    final block = RegExp(
      r'<languages>(.*?)</languages>',
      dotAll: true,
    ).firstMatch(metainfo);
    expect(
      block,
      isNotNull,
      reason:
          'AppStream infers languages from gettext catalogues, which a '
          'runtime-translated app has none of — so GNOME Software, Discover '
          'and Flathub show nothing unless this says so',
    );
    final entries = RegExp(
      r'<lang(?: percentage="(\d+)")?>([^<]+)</lang>',
    ).allMatches(block!.group(1)!);
    expect(entries.map((m) => m.group(2)!).toList(), expected);
    // The percentage is a claim about the bundles, so check the bundles.
    final keys = <String, Set<String>>{
      for (final code in expected)
        code: _keysOf(
          jsonDecode(File('assets/i18n/$code/common.json').readAsStringSync())
              as Map<String, dynamic>,
        ),
    };
    for (final m in entries) {
      final code = m.group(2)!;
      if (m.group(1) != '100') continue;
      expect(
        keys[code],
        keys['en'],
        reason:
            '$code is advertised as a complete translation; an incomplete '
            'one advertised as complete is worse than an honest number',
      );
    }
  });

  test('the Windows package lists them too', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final line = RegExp(
      r'^\s*languages:\s*(.+)$',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(line, isNotNull, reason: 'msix_config must carry a languages list');
    // Windows wants region-tagged tags (`de-de`); compare on the language.
    final declared = line!
        .group(1)!
        .split(',')
        .map((t) => t.trim().split('-').first)
        .toList(growable: false);
    expect(declared, expected);
  });
}

/// Every leaf key in a translation bundle, dotted.
Set<String> _keysOf(Map<String, dynamic> node, [String prefix = '']) {
  final out = <String>{};
  node.forEach((key, value) {
    if (value is Map<String, dynamic>) {
      out.addAll(_keysOf(value, '$prefix$key.'));
    } else {
      out.add('$prefix$key');
    }
  });
  return out;
}
