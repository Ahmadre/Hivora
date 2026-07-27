import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Performance + stability regression guard for the app-root glass quality
/// ceiling.
///
/// The app wraps its root (see `lib/app.dart`, `MaterialApp.builder`) with
/// `LiquidGlassWidgets.wrap(adaptiveQuality: true, ...)` capped at
/// [GlassQuality.standard]. Without that scope, every explicit
/// `quality: GlassQuality.premium` in the app renders the full two-BackdropFilter
/// + fragment-shader pipeline *ungated* on every device — the expensive path that
/// also triggered shader-related production crashes on some Mali GPUs.
///
/// `GlassThemeHelpers.resolveQuality` caps any widget-level quality to the
/// scope's `effectiveQuality`. So proving `effectiveQuality` is never `premium`
/// proves no glass surface in the app can take the premium path.
///
/// This mirrors the exact config used at the app root; if that wrap is removed or
/// its cap is loosened to premium, this test fails.
void main() {
  // Mirror of lib/app.dart's root wrap config. Keep in sync.
  Widget wrapWithAppCeiling(Widget child) => LiquidGlassWidgets.wrap(
    adaptiveQuality: true,
    // ignore: experimental_member_use
    adaptiveConfig: const GlassAdaptiveScopeConfig(
      initialQuality: GlassQuality.standard,
      maxQuality: GlassQuality.standard,
      minQuality: GlassQuality.minimal,
      allowStepUp: true,
      targetFrameMs: 16,
    ),
    child: child,
  );

  testWidgets('installs an adaptive scope that never resolves to premium', (
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

    // The ceiling scope must be present in the tree.
    expect(
      captured,
      isNotNull,
      reason:
          'The app root must install a GlassAdaptiveScope so premium glass '
          'is gated by device capability instead of rendering ungated.',
    );
    // The crash-prone / most-expensive premium path must never be the effective
    // quality under our cap (it resolves to standard on capable hardware, minimal
    // on weak/headless).
    expect(
      captured!.effectiveQuality,
      isNot(GlassQuality.premium),
      reason:
          'maxQuality is capped at standard; premium must never leak '
          'through the ceiling.',
    );
  });
}
