import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show ProgressiveBlur, ProgressiveBlurDirection;

/// Performance regression guard for [ProgressiveBlur].
///
/// The whole point of the current design is that the graduated ("Instagram
/// header") blur is a SINGLE GPU pass — one [BackdropFilter] whose fragment
/// shader varies the blur radius per-pixel — instead of the old stack of ~8-50
/// separate [BackdropFilter] slices that made every scroll/keystroke frame
/// re-run N blur passes and was the app's dominant Android jank source.
///
/// These tests pin that invariant: at most ONE BackdropFilter is ever emitted.
/// If someone reintroduces a slice stack, the first test fails loudly.
///
/// (In the test VM there is no Impeller, so [ProgressiveBlur] renders its uniform
/// single-pass fallback — still exactly one BackdropFilter, which is what we
/// assert. The Impeller path also emits exactly one, just with the shader.)
void main() {
  Widget host(double maxSigma) => MaterialApp(
    home: Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: Colors.white)),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 120,
            child: ProgressiveBlur(maxSigma: maxSigma),
          ),
        ],
      ),
    ),
  );

  testWidgets('is a single backdrop pass — never a slice stack', (
    tester,
  ) async {
    await tester.pumpWidget(host(30));
    await tester.pump();

    expect(
      find.byType(BackdropFilter),
      findsOneWidget,
      reason:
          'ProgressiveBlur must stay a single-pass blur. More than one '
          'BackdropFilter means the old per-slice stack (N blur passes per '
          'frame) has crept back — the original global jank bug.',
    );
  });

  testWidgets('emits no blur pass at all when maxSigma is 0', (tester) async {
    await tester.pumpWidget(host(0));
    await tester.pump();
    // maxSigma <= 0 short-circuits to a plain box — zero backdrop cost when the
    // bar is scrolled to its sharp (top-of-page) state.
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('builds with the default (optional) maxSigma', (tester) async {
    // maxSigma is optional now; the default must still render a blur pass.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SizedBox(height: 120, child: ProgressiveBlur())),
      ),
    );
    await tester.pump();
    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('every direction builds as a single pass', (tester) async {
    for (final dir in ProgressiveBlurDirection.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 120,
              child: ProgressiveBlur(maxSigma: 24, direction: dir),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(BackdropFilter), findsOneWidget, reason: 'dir=$dir');
    }
  });
}
