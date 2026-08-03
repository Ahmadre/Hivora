import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Golden-ratio driven responsive system. Instead of hard-coded device
/// breakpoints, layout classes are derived from how many "golden columns"
/// (content column of [baseColumnWidth] logical px, ~φ-proportioned) fit.
abstract final class Breakpoints {
  static const double phi = 1.618033988749;

  /// A comfortable reading column (~377 = Fibonacci, φ-friendly).
  static const double baseColumnWidth = 377;

  /// Width below which we collapse to a single column with bottom navigation.
  static double get compactMax => baseColumnWidth * phi; // ≈ 610
  /// Width below which we show a medium two-column layout.
  static double get mediumMax => baseColumnWidth * phi * phi; // ≈ 987

  /// How wide a page body may get before it stops being comfortable to read.
  /// The wide shell centres every page inside this; pages whose content is a
  /// spatial layout rather than something to read may opt out of it.
  static const double readingWidth = 1618; // 1000 · φ
}

/// Chrome insets published by whichever app shell is mounted, for widgets that
/// live in the ROOT overlay — the toast — and therefore float above every route
/// with no way to measure the shell they cover. While no shell is mounted (the
/// auth flow, the server picker, the splash) the insets are zero, so those
/// overlays hug the window edge instead of leaving a gap for chrome that isn't
/// on screen.
abstract final class ShellInsets {
  /// How far the mounted shell's top chrome — the wide shell's floating top
  /// bar, the compact shell's glass app bar — reaches *below the status-bar
  /// inset*. Overlays read that inset from their own [MediaQuery] and add
  /// whatever gap they want below this. Zero when no shell is mounted.
  static ValueListenable<double> get top => _top;
  static final ValueNotifier<double> _top = ValueNotifier<double>(0);

  /// How far the mounted shell's bottom chrome — the compact shell's floating
  /// nav — reaches above the *window edge*. Unlike the top bar, the nav floats
  /// over the safe area instead of above it, so this already spans that inset:
  /// overlays take whichever of the two reaches higher, never their sum. The
  /// keyboard, which lifts the nav with it, still stacks on top. Zero on the
  /// routes that hide the nav (immersive pages) and on the wide shell, which
  /// navigates from a rail instead.
  static ValueListenable<double> get bottom => _bottom;
  static final ValueNotifier<double> _bottom = ValueNotifier<double>(0);

  /// The shell that published the current values, so a departing shell cannot
  /// clear its successor's.
  static Object? _owner;

  /// Publishes [value] on behalf of [owner] (the shell's [State]). Safe to call
  /// from `build`: the notification is deferred to the end of the frame, since
  /// a listener rebuilding mid-build would throw.
  static void publishTop(Object owner, double value) =>
      _publish(owner, _top, value);

  /// Bottom counterpart of [publishTop].
  static void publishBottom(Object owner, double value) =>
      _publish(owner, _bottom, value);

  static void _publish(
    Object owner,
    ValueNotifier<double> inset,
    double value,
  ) {
    if (identical(_owner, owner) && inset.value == value) return;
    _owner = owner;
    _afterFrame(() {
      if (identical(_owner, owner)) inset.value = value;
    });
  }

  /// Withdraws [owner]'s insets as its shell goes away. Ignored once another
  /// shell has taken over — crossing the breakpoint disposes the outgoing shell
  /// *after* its replacement is initialised, so this must never clobber the
  /// newcomer's values.
  static void withdraw(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _afterFrame(() {
      if (_owner != null) return;
      _top.value = 0;
      _bottom.value = 0;
    });
  }

  static void _afterFrame(VoidCallback fn) =>
      WidgetsBinding.instance.addPostFrameCallback((_) => fn());

  /// Back to "no shell mounted", immediately. For tests, which share this
  /// static across cases; the app itself goes through [withdraw].
  @visibleForTesting
  static void reset() {
    _owner = null;
    _top.value = 0;
    _bottom.value = 0;
  }
}

enum LayoutSize { compact, medium, expanded }

extension ResponsiveContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;

  LayoutSize get layoutSize {
    final width = screenWidth;
    if (width < Breakpoints.compactMax) return LayoutSize.compact;
    if (width < Breakpoints.mediumMax) return LayoutSize.medium;
    return LayoutSize.expanded;
  }

  bool get isCompact => layoutSize == LayoutSize.compact;
  bool get isExpanded => layoutSize == LayoutSize.expanded;

  /// Page gutter that grows with the golden ratio between sizes.
  double get pageGutter => switch (layoutSize) {
    LayoutSize.compact => 16,
    LayoutSize.medium => 16 * Breakpoints.phi,
    LayoutSize.expanded => 16 * Breakpoints.phi * Breakpoints.phi,
  };

  /// Extra bottom padding scrollable page content should add so its last items
  /// can scroll clear of the floating bottom nav. The compact shell injects the
  /// nav's footprint into [MediaQuery] padding; on wider layouts (no bottom nav)
  /// this is just the device's bottom inset.
  double get bottomGutter => MediaQuery.paddingOf(this).bottom;

  /// Extra top padding scrollable page content should add so its first items
  /// rest just below the translucent app bar (and can scroll *behind* it). The
  /// compact shell injects the glass app bar's footprint into [MediaQuery]
  /// padding; on wider layouts the desktop top bar already consumes the status
  /// bar inset, so this is 0 there.
  double get topGutter => MediaQuery.paddingOf(this).top;

  /// Standard scroll-content padding: even [pageGutter] on every side plus
  /// [topGutter]/[bottomGutter] clearance so content rests below the glass app
  /// bar and the last items scroll clear of the floating nav.
  EdgeInsets get pagePadding => EdgeInsets.fromLTRB(
    pageGutter,
    pageGutter + topGutter,
    pageGutter,
    pageGutter + bottomGutter,
  );

  /// Number of columns for card grids derived from available width.
  int gridColumns({double minTileWidth = 320}) {
    final usable = screenWidth - pageGutter * 2;
    return usable <= minTileWidth
        ? 1
        : (usable / minTileWidth).floor().clamp(1, 4);
  }
}

/// Rebuilding helper for diverging compact/expanded subtrees.
class ResponsiveBuilder extends StatelessWidget {
  const ResponsiveBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, LayoutSize size) builder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, _) => builder(context, context.layoutSize),
  );
}
