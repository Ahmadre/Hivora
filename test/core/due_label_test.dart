/// Due dates used to be the one place the app always spoke English: a German
/// user read "23d overdue" and "Jul 24" on every board card, issue row and
/// sprint card. This pumps the *real* message bundle, so it fails if a key goes
/// missing or a form stops interpolating.
///
/// Everything lives in one `testWidgets` on purpose: the asset-backed i18next
/// delegate only resolves in the first widget test of a file, so a second one
/// would render an empty tree and assert nothing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/i18n/i18n.dart';
import 'package:hinata/core/widgets/hive_widgets.dart';

void main() {
  testWidgets('due labels speak the app language', (tester) async {
    /// Renders the label for a date [days] away, in [locale]. `days == 999`
    /// stands for "no due date at all".
    Future<String?> label(int days, {required String locale}) async {
      final due = days == 999
          ? null
          : DateUtils.dateOnly(DateTime.now().add(Duration(days: days)));
      String? text;
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey('$locale-$days'),
          locale: Locale(locale),
          supportedLocales: I18n.supportedLocales,
          localizationsDelegates: I18n.delegates(),
          home: Builder(
            builder: (context) {
              text = dueLabel(context, due)?.text;
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
      return text;
    }

    // ── German ──
    expect(
      await label(-23, locale: 'de'),
      '23 T. überfällig',
      reason: 'the reported bug: "23d overdue" on a German board',
    );
    expect(await label(-1, locale: 'de'), '1 T. überfällig');
    expect(await label(0, locale: 'de'), 'Heute');
    expect(await label(1, locale: 'de'), 'Morgen');
    expect(await label(4, locale: 'de'), 'in 4 T.');

    final farDe = await label(40, locale: 'de');
    expect(farDe, isNotNull);
    expect(
      farDe,
      isNot(matches(RegExp(r'^[A-Z][a-z]{2} \d+$'))),
      reason: 'a far date must not fall back to the English "Jul 24" form',
    );

    // ── English keeps the compact original wording ──
    expect(await label(-23, locale: 'en'), '23d overdue');
    expect(await label(0, locale: 'en'), 'Today');
    expect(await label(1, locale: 'en'), 'Tomorrow');
    expect(await label(4, locale: 'en'), '4d');

    // ── No due date, no label ──
    expect(await label(999, locale: 'de'), isNull);
  });
}
