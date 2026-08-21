import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/features/shell/floating_nav.dart';

/// How far the floating bottom nav is lifted off the bottom of the window.
///
/// The bar is a pill that floats over the content rather than a
/// `Scaffold.bottomNavigationBar`, so nothing lifts it for us. Pinned to the
/// window it lands inside whatever the system draws down there — and what that
/// is differs by platform in a way Flutter does not model: Android reports its
/// navigation bar and iOS its home indicator, both as `viewPadding.bottom`.
///
/// The rule is asserted twice on purpose. Once on the function, which says what
/// the rule *is*; and once through a mounted [FloatingNavPadding], because a
/// rule the shell forgets to apply is HIN-57 shipping again with a green build.
void main() {
  const screen = Size(390, 844);

  group('the platform rule', () {
    group('Android', () {
      // Three-button navigation: ~48dp of opaque chrome that swallows every
      // touch under it. This is HIN-57 — the nav pill sat inside it, so its
      // left-hand tabs could not be pressed at all.
      test('the bar clears a three-button navigation bar', () {
        expect(floatingNavLift(48, platform: TargetPlatform.android), 48);
      });

      // Thinner, and the system only draws into it — but it is also where the
      // swipe-up home gesture is watched for, so a tab down there is both under
      // the handle and unreliable to hit.
      test('the bar clears a gesture pill too', () {
        expect(floatingNavLift(24, platform: TargetPlatform.android), 24);
      });

      test('a device with no bottom chrome is not lifted at all', () {
        expect(floatingNavLift(0, platform: TargetPlatform.android), 0);
      });

      // Chrome on a phone reports TargetPlatform.android, but the browser's
      // chrome is not ours to clear — and the engine's inset there means
      // something else again.
      test('android in a browser is not native android', () {
        expect(
          floatingNavLift(48, platform: TargetPlatform.android, isWeb: true),
          0,
        );
      });
    });

    group('the platforms that must not move', () {
      // The fix for Android has to leave these pixel-identical. The home
      // indicator is a hairline the system draws over the app, and the design
      // deliberately lets the pill sit beside it; lifting by it pushes the bar
      // visibly too high, which is why the safe area was switched off for the
      // nav in the first place.
      for (final platform in const [
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        test('$platform is not lifted, however large its inset', () {
          expect(floatingNavLift(34, platform: platform), 0);
          expect(floatingNavLift(48, platform: platform), 0);
        });
      }
    });

    test('the platform defaults to the running one when not given', () {
      // The shell calls it without an argument; only the tests inject.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(floatingNavLift(48), 48);

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(floatingNavLift(48), 0);
    });

    // What content has to clear, and what the shell publishes to ShellInsets so
    // a toast rides above the nav instead of on it: the pill's top edge, never
    // the top of the empty gap above it.
    test('the top edge is the gap, the lift and the pill', () {
      expect(
        floatingNavTopEdge(48, platform: TargetPlatform.android),
        kFloatingNavPaddingV + 48 + kFloatingNavBarHeight,
      );
      expect(
        floatingNavTopEdge(34, platform: TargetPlatform.iOS),
        kFloatingNavPaddingV + kFloatingNavBarHeight,
      );
    });
  });

  group('on screen', () {
    const navKey = ValueKey('nav');

    /// Mounts the pill the way the compact shell does — pinned to the bottom of
    /// a `Scaffold` body — and returns where it landed.
    Future<Rect> pumpNav(
      WidgetTester tester, {
      required TargetPlatform platform,
      required double bottomInset,
      double keyboard = 0,
    }) async {
      // Set here and cleared in the test body, NOT via addTearDown:
      // testWidgets asserts every foundation debug variable is unset while the
      // body is still unwinding, which runs before any tearDown does. This has
      // bitten this repository once already.
      debugDefaultTargetPlatformOverride = platform;

      // What the platform still reports as safe area once the keyboard has
      // eaten into it.
      final uncovered = math.max(0.0, bottomInset - keyboard);
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = screen
        ..viewPadding = FakeViewPadding(bottom: bottomInset)
        ..padding = FakeViewPadding(bottom: uncovered)
        ..viewInsets = FakeViewPadding(bottom: keyboard);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: FloatingNavPadding(
                    // Stands in for the glass pill: same height, none of the
                    // shader work a software renderer would crawl through.
                    child: SizedBox(key: navKey, height: kFloatingNavBarHeight),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return tester.getRect(find.byKey(navKey));
    }

    testWidgets('android: the pill clears the navigation bar', (tester) async {
      final nav = await pumpNav(
        tester,
        platform: TargetPlatform.android,
        bottomInset: 48,
      );
      debugDefaultTargetPlatformOverride = null;

      // The whole point of HIN-57: not one pixel of the pill inside the 48dp
      // the navigation bar owns.
      expect(screen.height - nav.bottom, 48 + kFloatingNavPaddingV);
      // And the shell reserves exactly this much for it.
      expect(
        screen.height - nav.top,
        floatingNavTopEdge(48, platform: TargetPlatform.android),
      );
    });

    testWidgets('ios: the pill sits beside the home indicator, not above it', (
      tester,
    ) async {
      final nav = await pumpNav(
        tester,
        platform: TargetPlatform.iOS,
        bottomInset: 34,
      );
      debugDefaultTargetPlatformOverride = null;

      // Unchanged from before the Android fix: the gap and nothing else.
      expect(screen.height - nav.bottom, kFloatingNavPaddingV);
      expect(
        screen.height - nav.top,
        floatingNavTopEdge(34, platform: TargetPlatform.iOS),
      );
    });

    testWidgets('android: the keyboard leaves no navigation bar to clear', (
      tester,
    ) async {
      const keyboard = 300.0;
      final nav = await pumpNav(
        tester,
        platform: TargetPlatform.android,
        bottomInset: 48,
        keyboard: keyboard,
      );
      debugDefaultTargetPlatformOverride = null;

      // The Scaffold shrinks its body to the top of the keyboard, where there
      // is no navigation bar — so the pill must sit straight on that edge. Lift
      // it anyway and it floats 48dp above the keyboard, and every gap measured
      // from the nav (the toast, the last row of a list) is wrong by that much,
      // because the footprint reads the same keyboard-adjusted inset.
      expect(screen.height - keyboard - nav.bottom, kFloatingNavPaddingV);
    });
  });
}
