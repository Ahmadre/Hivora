import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/util/share_origin.dart';

/// The contract UIKit enforces on a share popover's source rectangle: it must be
/// non-empty and it must fit inside the presenting view. Every case here is one
/// the platform channel answers with a `PlatformException` rather than a
/// fallback, so each is a download that fails in front of the user.
void main() {
  // An iPhone 14/15 in portrait — the window from the 10.2.0 crash report.
  const window = Size(393, 852);

  Matcher fitsInside(Size size) => predicate<Rect>(
    (rect) =>
        rect.left >= 0 &&
        rect.top >= 0 &&
        rect.right <= size.width &&
        rect.bottom <= size.height &&
        rect.width > 0 &&
        rect.height > 0,
    'is non-empty and inside $size',
  );

  group('shareAnchorWithin', () {
    test('leaves a rectangle that already fits alone', () {
      const button = Rect.fromLTWH(320, 60, 40, 40);
      expect(shareAnchorWithin(button, window), button);
    });

    test('clips the scrolling body that crashed 10.2.0', () {
      // Reported verbatim by iOS: {{0, 157.2}, {393, 2188.5}} against a
      // {{0,0},{393,852}} source view.
      const body = Rect.fromLTWH(0, 157.19999999999993, 393, 2188.5);
      final anchor = shareAnchorWithin(body, window);
      expect(anchor, fitsInside(window));
      expect(anchor, const Rect.fromLTRB(0, 157.19999999999993, 393, 852));
    });

    test('keeps the visible part of a widget scrolled off the top', () {
      const scrolledUp = Rect.fromLTRB(20, -300, 200, 120);
      final anchor = shareAnchorWithin(scrolledUp, window);
      expect(anchor, fitsInside(window));
      expect(anchor, const Rect.fromLTRB(20, 0, 200, 120));
    });

    test('gives Rect.zero a size — a menu whose render object is gone', () {
      final anchor = shareAnchorWithin(Rect.zero, window);
      expect(anchor, fitsInside(window));
    });

    test('gives a zero-height control at the very bottom edge a size', () {
      final anchor = shareAnchorWithin(
        const Rect.fromLTWH(10, 852, 100, 0),
        window,
      );
      expect(anchor, fitsInside(window));
    });

    test('falls back to the centre when the candidate is off-screen', () {
      final anchor = shareAnchorWithin(
        const Rect.fromLTWH(2000, 4000, 40, 40),
        window,
      );
      expect(anchor, fitsInside(window));
      expect(anchor.center, const Offset(393 / 2, 852 / 2));
    });

    test('falls back to the centre when there is no candidate at all', () {
      final anchor = shareAnchorWithin(null, window);
      expect(anchor, fitsInside(window));
      expect(anchor.center, const Offset(393 / 2, 852 / 2));
    });

    test('refuses a rectangle carrying NaN or infinity', () {
      for (final broken in <Rect>[
        const Rect.fromLTRB(0, 0, double.nan, 40),
        const Rect.fromLTRB(0, 0, double.infinity, double.infinity),
      ]) {
        expect(shareAnchorWithin(broken, window), fitsInside(window));
      }
    });

    test('still answers with a usable rectangle in a zero-sized window', () {
      // Not reachable in a laid-out app, but "no window" must not become "no
      // rectangle" — that is the other half of the same PlatformException.
      final anchor = shareAnchorWithin(
        const Rect.fromLTWH(0, 0, 10, 10),
        Size.zero,
      );
      expect(anchor.width, greaterThan(0));
      expect(anchor.height, greaterThan(0));
    });
  });

  group('shareOriginOf', () {
    testWidgets('prefers the control that was tapped', (tester) async {
      late Rect origin;
      const tapped = Rect.fromLTWH(300, 40, 40, 40);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: window),
          child: Builder(
            builder: (context) {
              origin = shareOriginOf(context, preferred: tapped);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(origin, tapped);
    });

    testWidgets('clips what it reads from the context to the window', (
      tester,
    ) async {
      late Rect origin;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: window),
          child: Builder(
            builder: (context) => SizedBox(
              width: window.width,
              // Three screens of content, as an issue sheet's body routinely is.
              height: window.height * 3,
              child: Builder(
                builder: (context) {
                  origin = shareOriginOf(context);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );
      expect(origin, fitsInside(window));
    });
  });
}
