// Frame-timing benchmark for the notification bell popover.
//
// Run with:
// flutter drive --profile --no-dds -d emulator-5554 \
//   --driver=test_driver/perf_driver.dart \
//   --target=integration_test/notification_popover_perf_test.dart

// A fresh install boots into the connect screen, so the test walks the full
// flow (server URL → login → onboarding) before measuring. Every step is
// skipped automatically when the app restores a persisted session. Frame
// timings are recorded with integration_test's watchPerformance — the same
// FrameTiming data DevTools shows.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:hinata/main.dart' as app;

// Supplied via --dart-define (see the "Popover Perf Benchmark" VSCode task):
//   --dart-define=HINATA_SERVER_URL=https://…
//   --dart-define=HINATA_USER=… --dart-define=HINATA_PASSWORD=…
// Only needed when the device has no persisted session yet.
const _serverUrl = String.fromEnvironment('HINATA_SERVER_URL');
const _user = String.fromEnvironment('HINATA_USER');
const _password = String.fromEnvironment('HINATA_PASSWORD');

Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  final steps = duration.inMilliseconds ~/ 100;
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Pumps until [finder] matches or [timeout] elapses. Returns whether found.
Future<bool> _waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final steps = timeout.inMilliseconds ~/ 250;
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 250));
    if (tester.any(finder)) return true;
  }
  return false;
}

/// Replaces the complete value of a [TextFormField], including any prefill.
///
/// On a device the platform IME can retain ownership of the input connection,
/// which makes `enterText`/`TestTextInput` unreliable for this prefilled URL
/// field. Updating the controller is deterministic; the `TextFormField`
/// observes the controller value before the form is submitted.
Future<void> _replaceFieldText(
  WidgetTester tester,
  Finder field,
  String text,
) async {
  await tester.tap(field, warnIfMissed: true);
  await tester.pump(const Duration(milliseconds: 300));
  final controller = tester.widget<TextFormField>(field).controller;
  if (controller == null) {
    throw StateError('Expected the test field to have a TextEditingController');
  }
  controller.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'notification popover open/close frame timings',
    (tester) async {
      // main now takes the process arguments (a Linux deep link arrives that
      // way); a perf run launches with none.
      await app.main(const []);
      await _pumpFor(tester, const Duration(seconds: 3));

      final bell = find.byIcon(LucideIcons.bell);
      final connectField = find.byIcon(LucideIcons.server);
      final loginUserField = find.byIcon(LucideIcons.user);

      // ── Step 1: connect screen (fresh install only) ───────────────────────
      if (!tester.any(bell) && !tester.any(loginUserField)) {
        if (await _waitFor(
          tester,
          connectField,
          timeout: const Duration(seconds: 10),
        )) {
          debugPrint('PERF-TEST step: connect screen');
          expect(
            _serverUrl,
            isNotEmpty,
            reason:
                'No session on device and HINATA_SERVER_URL not set — '
                'pass the connection via --dart-define.',
          );
          // The connect field is prefilled with `https://`; replace its value
          // directly because the device IME may keep the test channel detached.
          await _replaceFieldText(
            tester,
            find.byType(TextFormField).first,
            _serverUrl,
          );
          await tester.tap(find.byType(FilledButton).first);
          await _pumpFor(tester, const Duration(seconds: 3));
        }
      }

      // ── Step 2: onboarding — keep tapping the CTA until it's gone ────────
      final cta = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_CtaButton',
      );
      for (var i = 0; i < 6 && tester.any(cta); i++) {
        debugPrint('PERF-TEST step: onboarding cta tap ${i + 1}');
        await tester.tap(cta, warnIfMissed: true);
        await _pumpFor(tester, const Duration(seconds: 1));
      }

      // ── Step 3: login (skipped when a session was restored) ──────────────
      if (!tester.any(bell) &&
          await _waitFor(
            tester,
            loginUserField,
            timeout: const Duration(seconds: 10),
          )) {
        debugPrint('PERF-TEST step: login screen');
        final fields = find.byType(TextFormField);
        await _replaceFieldText(tester, fields.at(0), _user);
        await _replaceFieldText(tester, fields.at(1), _password);
        await tester.tap(find.byType(FilledButton).first);
        await _pumpFor(tester, const Duration(seconds: 4));
      }

      // ── Step 4: wait for the shell (bell in the top bar) ─────────────────
      final reachedShell = await _waitFor(
        tester,
        bell,
        timeout: const Duration(seconds: 10),
      );
      if (!reachedShell) {
        // Diagnostic: dump visible texts so the failing screen is identifiable.
        final texts = find
            .byType(Text)
            .evaluate()
            .map((e) => (e.widget as Text).data)
            .whereType<String>()
            .take(25)
            .toList();
        debugPrint('PERF-TEST visible texts: $texts');
      }
      expect(
        reachedShell,
        isTrue,
        reason: 'bell trigger not found — login flow did not reach the shell',
      );

      // Warm-up round (shader/pipeline compilation must not skew the measure).
      await tester.tap(bell.first, warnIfMissed: false);
      await _pumpFor(tester, const Duration(milliseconds: 1200));
      await tester.tapAt(const Offset(50, 500));
      await _pumpFor(tester, const Duration(milliseconds: 1000));

      await binding.watchPerformance(() async {
        for (var i = 0; i < 6; i++) {
          await tester.tap(bell.first, warnIfMissed: false);
          await _pumpFor(tester, const Duration(milliseconds: 1200));
          await tester.tapAt(const Offset(50, 500));
          await _pumpFor(tester, const Duration(milliseconds: 1000));
        }
      }, reportKey: 'popover_perf');
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
