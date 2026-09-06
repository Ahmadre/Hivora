import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/theme/glass_ceiling.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// What the app-root glass scope is allowed to decide, and what it must not.
///
/// The app wraps its root (`lib/app.dart`, `MaterialApp.builder`) with
/// `LiquidGlassWidgets.wrap(adaptiveQuality: true, adaptiveConfig: kGlassCeiling)`.
/// `GlassThemeHelpers.resolveQuality` caps every quality against that scope —
/// an explicit widget-level `quality: premium` included — so this config is the
/// ceiling for the whole app.
///
/// Premium is reachable on hardware that measures well enough for it. The rules
/// worth pinning are the ones that keep that from becoming a free-for-all: the
/// scope has to exist, it has to be able to fall all the way to minimal, and it
/// must not be handed a starting quality — [GlassAdaptiveScopeConfig.initialQuality]
/// overrides the warm-up benchmark and skips it, which is exactly how the cap
/// once ended up deciding for hardware it had never measured.
void main() {
  test('the app lets a capable device reach premium', () {
    expect(kGlassCeiling.maxQuality, GlassQuality.premium);
  });

  test('and lets a weak one fall all the way', () {
    expect(kGlassCeiling.minQuality, GlassQuality.minimal);
    expect(kGlassCeiling.allowStepUp, isTrue);
  });

  test('the device benchmark is left to run', () {
    expect(
      kGlassCeiling.initialQuality,
      isNull,
      reason:
          'a seeded initialQuality skips the warm-up benchmark entirely, so '
          'every device would keep whatever tier was guessed for it here',
    );
  });

  // The app's own ceiling, not a copy of it. It used to be a copy under a
  // "keep in sync" comment, and it drifted: the root wrap said premium while
  // this test went on passing against its own standard.
  Widget wrapWithAppCeiling(Widget child) => LiquidGlassWidgets.wrap(
    adaptiveQuality: true,
    // ignore: experimental_member_use
    adaptiveConfig: kGlassCeiling,
    child: child,
  );

  testWidgets('the scope is actually installed, and resolves a tier', (
    tester,
  ) async {
    GlassAdaptiveScopeData? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: wrapWithAppCeiling(
          Builder(
            builder: (context) {
              captured = GlassAdaptiveScopeData.maybeOf(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      captured,
      isNotNull,
      reason:
          'without the scope every explicit premium in the app renders ungated '
          'on every device, including the ones where that shader crashes',
    );
    // Headless, so the static probe settles this one low; what matters is that
    // a tier was resolved at all rather than which.
    expect(GlassQuality.values, contains(captured!.effectiveQuality));
  });
}
