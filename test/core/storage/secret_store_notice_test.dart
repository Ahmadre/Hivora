/// The words a user with no working secret store actually reads.
///
/// This pumps the *real* message bundle, in both languages, so it fails if a
/// key goes missing, if a translation is forgotten, or — the one that matters —
/// if the wrong advice reaches the wrong system. A `snap connect` line shown to
/// someone on a plain desktop is not a small cosmetic slip: it is an
/// instruction that cannot work, given at the exact moment they are trying to
/// understand why they keep getting signed out.
///
/// Everything lives in one `testWidgets` on purpose: the asset-backed i18next
/// delegate only resolves in the first widget test of a file, so a second one
/// would render an empty tree and assert nothing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/i18n/i18n.dart';
import 'package:hinata/core/storage/secret_store_environment.dart';

void main() {
  testWidgets('the session-not-persisted notice fits the system', (
    tester,
  ) async {
    const snap = SecretStoreEnvironment(
      remedy: SecretStoreRemedy.snapPermission,
      snapInstanceName: 'hinata',
    );
    const desktop = SecretStoreEnvironment(
      remedy: SecretStoreRemedy.linuxKeyring,
    );

    // System + failure, because the message needs both. `lockedSnap` is the
    // case the environment alone gets wrong: the plug *is* connected (the store
    // answered), so telling that user to run `snap connect` sends them to App
    // Center to look at a permission that is already on.
    final cases = <String, SecretStoreNotice>{
      'snap': snap.noticeFor(SecretStoreFailure.unreachable),
      'keyring': desktop.noticeFor(SecretStoreFailure.unreachable),
      'generic': SecretStoreEnvironment.plain.noticeFor(
        SecretStoreFailure.unreachable,
      ),
      'locked': desktop.noticeFor(SecretStoreFailure.locked),
      'lockedSnap': snap.noticeFor(SecretStoreFailure.locked),
    };

    /// Every notice, rendered by the app's own lookup in [locale], plus the
    /// action label that goes with the snap one.
    Future<Map<String, String>> notices(String locale) async {
      final out = <String, String>{};
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(locale),
          locale: Locale(locale),
          supportedLocales: I18n.supportedLocales,
          localizationsDelegates: I18n.delegates(),
          home: Builder(
            builder: (context) {
              for (final entry in cases.entries) {
                // Exactly the call `_warnIfSessionWontPersist` makes.
                out[entry.key] = context.t(
                  entry.value.messageKey,
                  variables: {'command': ?entry.value.command},
                );
              }
              out['copyCommand'] = context.t(
                'errors.sessionNotPersisted.copyCommand',
              );
              return const SizedBox();
            },
          ),
        ),
      );
      // The bundle comes from a real asset: let the I/O run, then give the
      // delegate the timed frame on which it hands its translations down.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      return out;
    }

    const command = 'snap connect hinata:password-manager-service';

    // ── English ──
    final en = await notices('en');

    for (final entry in en.entries) {
      expect(
        entry.value,
        isNot(startsWith('errors.')),
        reason: '${entry.key} has no English translation',
      );
    }

    expect(en['snap'], contains(command));
    expect(en['snap'], contains('App Center'));
    expect(en['snap'], contains('sign in again after every restart'));
    expect(en['copyCommand'], 'Copy command');

    // The keyring notice names the thing to install and never the snap fix.
    expect(en['keyring'], contains('GNOME Keyring'));
    expect(en['keyring'], contains('KWallet'));
    expect(en['keyring'], isNot(contains('snap')));

    // A store that answered "locked" is a store we can reach: nothing to
    // install, nothing to connect — just unlock it. Same sentence inside a snap
    // as outside one, because the snap's permission is evidently granted.
    expect(en['locked'], contains('locked'));
    expect(en['locked'], isNot(contains('snap')));
    expect(en['locked'], isNot(contains('install')));
    expect(en['lockedSnap'], en['locked']);
    expect(cases['lockedSnap']!.command, isNull);

    // The generic one promises nothing it cannot know: no daemon to install,
    // no permission to connect, just what is and is not affected.
    expect(en['generic'], isNot(contains('snap')));
    expect(en['generic'], isNot(contains('eyring')));
    expect(en['generic'], contains('only staying signed in is affected'));

    // No leftover interpolation anywhere — a stray {{command}} on screen is
    // how a user learns the message was written for someone else.
    for (final value in en.values) {
      expect(value, isNot(contains('{{')));
    }

    // ── German ──
    final de = await notices('de');

    for (final entry in de.entries) {
      expect(
        entry.value,
        isNot(startsWith('errors.')),
        reason: '${entry.key} has no German translation',
      );
      expect(
        entry.value,
        isNot(en[entry.key]),
        reason: '${entry.key} is still the English string',
      );
    }

    expect(de['snap'], contains(command));
    expect(de['snap'], contains('App Center'));
    expect(de['snap'], contains('erneute Anmeldung'));
    expect(de['copyCommand'], 'Befehl kopieren');

    expect(de['keyring'], contains('Schlüsselbund'));
    expect(de['keyring'], contains('GNOME Keyring'));
    expect(de['keyring'], isNot(contains('snap connect')));

    expect(de['locked'], contains('gesperrt'));
    expect(de['locked'], isNot(contains('snap')));
    expect(de['lockedSnap'], de['locked']);

    expect(de['generic'], isNot(contains('snap')));
    expect(de['generic'], isNot(contains('Schlüsselbund')));

    for (final value in de.values) {
      expect(value, isNot(contains('{{')));
    }
  });
}
