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
