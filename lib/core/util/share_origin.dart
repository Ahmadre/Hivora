import 'package:flutter/widgets.dart';

/// Where the OS share sheet should point.
///
/// On iOS and iPadOS the share sheet is a `UIActivityViewController`, and UIKit
/// requires the popover it may become to name a source rectangle. `share_plus`
/// forwards [ShareParams.sharePositionOrigin] as that rectangle and UIKit then
/// validates it against the presenting view's own bounds, refusing anything
/// that is not — in its words — "non-zero and within coordinate space of source
/// view".
///
/// That refusal is a `PlatformException`, not a fallback, and it is what broke
/// every export on iOS in 10.2.0:
///
/// ```text
/// sharePositionOrigin: argument must be set,
/// {{0, 157.2}, {393, 2188.5}} must be non-zero and within coordinate space
/// of source view: {{0, 0}, {393, 852}}
/// ```
///
/// The caller had passed the global bounds of the widget it was called from —
/// the issue sheet's scrolling body, 2188 points tall inside an 852-point
/// window. Perfectly ordinary as a widget, and impossible as a popover anchor.
/// A rectangle taller than the screen is not a rare edge case here: any
/// scrollable that is longer than one screen produces one, which is why this
/// rule belongs in one function rather than at each of the three call sites
/// that pass an origin.
///
/// Two rules, and both matter:
///
///  * **Inside the window.** The candidate is clipped to the window's bounds.
///    A widget scrolled halfway off the top keeps the part that is visible.
///  * **Never empty.** UIKit rejects a zero-sized rectangle as readily as an
///    oversized one, and `Rect.zero` is what the menu anchor falls back to when
///    its render object has gone. A degenerate result is replaced by a small
///    square at the same place, and a candidate that is off-screen entirely
///    collapses to the window's centre — the same place iOS puts a popover it
///    cannot anchor.
///
/// Elsewhere the value is ignored, so this is safe to pass on every platform
/// and there is no `Platform.isIOS` here to get wrong.

/// The share-sheet anchor for [context], preferring [preferred] when the caller
/// knows the exact control that was tapped.
///
/// [preferred] should be in global (window) coordinates, as
/// `box.localToGlobal(Offset.zero) & box.size` produces. Pass the button the
/// user actually pressed: the popover then grows out of it, which is what makes
/// an iPad share sheet look deliberate rather than dropped in the middle.
///
/// Read this on the frame the gesture arrives, before the first `await` — a
/// render object answers for the frame it was laid out in, and a share sheet is
/// always presented after at least one network round trip.
Rect shareOriginOf(BuildContext context, {Rect? preferred}) {
  final window = MediaQuery.sizeOf(context);
  final box = context.findRenderObject() as RenderBox?;
  final candidate = preferred ??
      ((box != null && box.hasSize)
          ? box.localToGlobal(Offset.zero) & box.size
          : null);
  return shareAnchorWithin(candidate, window);
}

/// The part of [candidate] a share popover may be anchored to inside a window
/// of [window] points — see the rules above.
///
/// Separate from [shareOriginOf] and public so the geometry can be pinned by
/// tests without a widget tree; every case that reached the platform channel as
/// an exception is one of these.
@visibleForTesting
Rect shareAnchorWithin(Rect? candidate, Size window) {
  // A window with no area gives nothing to clip against and nothing to centre
  // in. It does not happen in a laid-out app; if it ever does, a small square
  // at the origin is still a rectangle UIKit accepts.
  if (!window.width.isFinite ||
      !window.height.isFinite ||
      window.width <= 0 ||
      window.height <= 0) {
    return const Rect.fromLTWH(0, 0, _minimumSide, _minimumSide);
  }
  final bounds = Offset.zero & window;
  final centre = Rect.fromCenter(
    center: bounds.center,
    width: _minimumSide,
    height: _minimumSide,
  );
  if (candidate == null || !_isUsable(candidate)) return centre;

  final clipped = candidate.intersect(bounds);
  if (clipped.width >= _minimumSide && clipped.height >= _minimumSide) {
    return clipped;
  }
  // `Rect.intersect` reports two rectangles that do not overlap at all as a
  // negative extent rather than an empty rectangle, and that is the case with
  // no sensible anchor: the control has scrolled out of the window entirely.
  // Centre it, which is where iOS itself puts a popover it cannot anchor.
  if (clipped.width < 0 || clipped.height < 0) return centre;
  // Touching the window but too thin to be an anchor — a control at the very
  // edge, or a Rect.zero from a menu whose render object is gone. Keep where it
  // is and give it enough size to be accepted, pushed back inside if that grew
  // it past an edge.
  const side = _minimumSide;
  final left =
      candidate.left.clamp(0.0, (window.width - side).clamp(0.0, double.infinity));
  final top =
      candidate.top.clamp(0.0, (window.height - side).clamp(0.0, double.infinity));
  return Rect.fromLTWH(left, top, side, side);
}

/// Whether a rectangle is finite — a NaN or infinite edge out of a render
/// object mid-layout would survive clipping and be handed to the platform.
bool _isUsable(Rect rect) =>
    rect.left.isFinite &&
    rect.top.isFinite &&
    rect.right.isFinite &&
    rect.bottom.isFinite;

/// The smallest anchor worth handing over. UIKit only asks for "non-zero", but
/// a sub-point rectangle makes the popover's arrow land in an arbitrary place;
/// a point square keeps it where the user tapped.
const double _minimumSide = 1;
