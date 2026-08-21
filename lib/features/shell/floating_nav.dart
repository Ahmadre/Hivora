import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

// ───────────────────────── Floating nav geometry ──────────────────────────
//
// Where the compact shell's floating nav sits — the tab pill plus the detached
// search button beside it. Four places have to agree on that: the pill itself,
// the footprint the shell injects into MediaQuery.padding so page content can
// scroll clear of it, the inset it publishes to ShellInsets for the overlays
// that float above the shell (the toast), and the scrim the pill dissolves
// content into. They all read it from here because they did drift apart: the
// footprint carried a literal 80 long after the padding it described had
// changed.

/// Height of the floating tab pill. This is `GlassTabBar.bottom`'s `barHeight`,
/// and the call site passes it explicitly, so this constant is the source of
/// truth rather than a copy of a package default that a version bump could move
/// out from under the footprint.
const double kFloatingNavBarHeight = 64;

/// Breathing room around the floating nav. The horizontal value is cosmetic;
/// the vertical one is the smallest gap that may ever sit between the pill and
/// the bottom of the window.
const double kFloatingNavPaddingH = 24;
const double kFloatingNavPaddingV = 16;

/// How far the floating nav has to be lifted off the bottom of the window so it
/// is not sitting inside system chrome.
///
/// The bottom inset does not mean the same thing on every platform, and Flutter
/// reports all of them as `viewPadding.bottom`, so the distinction has to be
/// drawn somewhere.
///
/// On **Android** that band belongs to the system's navigation affordance — in
/// both of its modes — and interactive chrome cannot live inside it:
///  * three-button navigation is ~48dp of opaque chrome that swallows every
///    touch under it. The nav pill sat inside it and its tabs could not be
///    pressed at all; that is HIN-57, filed from a real device.
///  * gesture navigation is a thinner band the system only *draws* into, but it
///    is also where it watches for the swipe-up home gesture, so a tab down
///    there sits under the handle and answers taps unreliably.
///
/// On **iOS** the same number is the home indicator: a hairline drawn *over*
/// the app, with no gesture competing for a tap at rest. The design lets the
/// pill sit beside it on purpose — lifting by it pushes the bar visibly too
/// high, which is why the safe area was switched off for the nav in the first
/// place. The desktops and web have no such band at all.
///
/// Pass the inset the nav is actually being placed against. Inside a `Scaffold`
/// body that resizes for the keyboard that inset is already keyboard-adjusted,
/// which is exactly right: with the keyboard up there is no navigation bar
/// between the pill and the field, so there is nothing to lift over.
///
/// [isWeb] and [platform] are injectable so the rule can be tested without a
/// device. The web check is not decoration: Chrome on a phone reports
/// `TargetPlatform.android`, and what earns the lift is *native* Android system
/// chrome — the browser's own is not ours to clear.
double floatingNavLift(
  double bottomViewPadding, {
  bool isWeb = kIsWeb,
  TargetPlatform? platform,
}) => !isWeb && (platform ?? defaultTargetPlatform) == TargetPlatform.android
    ? bottomViewPadding
    : 0;

/// Distance from the bottom of the window up to the *top edge* of the pill: its
/// bottom gap, the lift out of system chrome, and the pill itself.
///
/// This is the line content must clear, and the value the shell publishes to
/// `ShellInsets` so a toast rides above the nav rather than on it. It is
/// deliberately the pill's edge and not the height of the padded slot: the gap
/// above the pill is empty space, and anchoring to it would double every gap
/// measured from here.
double floatingNavTopEdge(
  double bottomViewPadding, {
  bool isWeb = kIsWeb,
  TargetPlatform? platform,
}) {
  final lift = floatingNavLift(
    bottomViewPadding,
    isWeb: isWeb,
    platform: platform,
  );
  return kFloatingNavPaddingV + lift + kFloatingNavBarHeight;
}

/// Places the floating nav [child] against the bottom of the window, owning
/// every inset it has to spend: the horizontal safe area, its own gaps, and the
/// lift out of system chrome.
class FloatingNavPadding extends StatelessWidget {
  const FloatingNavPadding({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // viewPaddingOf, not MediaQuery.of: this needs one field, and depending on
    // the whole MediaQueryData would rebuild the nav — and at the shell, the
    // entire glass Stack around it — on every frame of the keyboard animation.
    final lift = floatingNavLift(MediaQuery.viewPaddingOf(context).bottom);
    return SafeArea(
      // Left/right only, and load-bearing: those are the landscape insets —
      // Android's side navigation bar, a notched iPhone turned sideways — and
      // nothing else clears them for a pill pinned to the window. The vertical
      // sides stay off on purpose; the padding below spends the bottom inset
      // itself, where a full SafeArea would spend it on every platform.
      top: false,
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          kFloatingNavPaddingH,
          kFloatingNavPaddingV,
          kFloatingNavPaddingH,
          kFloatingNavPaddingV + lift,
        ),
        child: child,
      ),
    );
  }
}
