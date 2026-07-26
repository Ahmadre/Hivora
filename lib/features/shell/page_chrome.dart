import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// A single primary action a sub-page publishes into the shell's glass app bar
/// (e.g. Save, Invite). The shell renders it in the app bar's trailing slot:
/// an icon-only frosted circle on compact, an icon+label frosted pill on wide.
/// A [primary] action is tinted amber; a [busy] one swaps its glyph for a small
/// spinner and ignores taps.
///
/// It's a value type (with [==]/[hashCode]) so the shell can diff action lists
/// cheaply and pages can rebuild them freely each frame without churning the bar.
@immutable
class PageAction {
  const PageAction({
    required this.icon,
    required this.label,
    this.onTap,
    this.primary = false,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final bool busy;

  @override
  bool operator ==(Object other) =>
      other is PageAction &&
      other.icon == icon &&
      other.label == label &&
      identical(other.onTap, onTap) &&
      other.primary == primary &&
      other.busy == busy;

  @override
  int get hashCode => Object.hash(icon, label, onTap, primary, busy);
}

/// Chrome a sub-page hands the app shell to render in its top app bar: the
/// page's real (often dynamic) [title], an optional [onBack] override for
/// back navigation that isn't a plain route pop — e.g. an in-page master→detail
/// step — and optional trailing [actions]. When a page publishes nothing the
/// shell falls back to a route-derived title and a pop/parent-route back.
@immutable
class PageChromeData {
  const PageChromeData({
    this.location,
    this.title,
    this.onBack,
    this.bottom,
    this.bottomHeight = 0,
    this.actions = const [],
    this.fullWidth = false,
  });

  /// Whether the page takes the whole content area instead of being centred in
  /// [Breakpoints.readingWidth]. For pages whose content is a spatial layout
  /// rather than something to read — and only where that is actually true of
  /// the data on screen, which is why it is published by the page rather than
  /// derived from the route. The shell applies it to the sub-page bar as well,
  /// so the back button never sits off the page's own left edge.
  final bool fullWidth;

  /// The route this chrome belongs to. The shell only honours an override whose
  /// [location] matches the route currently on screen, so stale chrome from a
  /// page being torn down is ignored automatically (no dispose ordering race).
  final String? location;
  final String? title;
  final VoidCallback? onBack;

  /// An optional widget the page docks into the app bar *below* the title row —
  /// e.g. a filter/sort toolbar that stays pinned and shares the bar's single
  /// glass blur (no separate blurred band). [bottomHeight] is its fixed height,
  /// added to the bar and to the injected top gutter so page content still
  /// clears the whole bar. Compact shell only; the wide shell ignores it.
  final Widget? bottom;
  final double bottomHeight;

  /// Trailing primary actions the page surfaces in the shell's glass app bar,
  /// so pages no longer draw their own header/save chrome. Rendered by both the
  /// compact and wide shells (see [PageAction]).
  final List<PageAction> actions;
}

/// Carries the chrome published by the visible sub-page to the shell's top bar.
class PageChromeController extends ChangeNotifier {
  PageChromeData _data = const PageChromeData();

  String? titleFor(String location) =>
      _data.location == location ? _data.title : null;

  VoidCallback? onBackFor(String location) =>
      _data.location == location ? _data.onBack : null;

  Widget? bottomFor(String location) =>
      _data.location == location ? _data.bottom : null;

  double bottomHeightFor(String location) =>
      _data.location == location ? _data.bottomHeight : 0;

  List<PageAction> actionsFor(String location) =>
      _data.location == location ? _data.actions : const [];

  /// Defaults to false, so a page that publishes nothing — or has not published
  /// yet — is laid out like every other page rather than flashing wide first.
  bool fullWidthFor(String location) =>
      _data.location == location && _data.fullWidth;

  void publish(PageChromeData data) {
    if (_data.location == data.location &&
        _data.title == data.title &&
        identical(_data.onBack, data.onBack) &&
        identical(_data.bottom, data.bottom) &&
        _data.bottomHeight == data.bottomHeight &&
        _data.fullWidth == data.fullWidth &&
        listEquals(_data.actions, data.actions)) {
      return;
    }
    _data = data;
    notifyListeners();
  }
}

/// Provides a [PageChromeController] to the shell's top bar (which listens) and
/// to descendant pages (which publish without subscribing).
class PageChromeScope extends InheritedNotifier<PageChromeController> {
  const PageChromeScope({
    super.key,
    required PageChromeController controller,
    required super.child,
  }) : super(notifier: controller);

  /// Listening lookup — the caller rebuilds when the chrome changes.
  static PageChromeController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<PageChromeScope>();
    assert(scope != null, 'No PageChromeScope found in context');
    return scope!.notifier!;
  }

  /// Non-listening lookup — for pages that only publish.
  static PageChromeController? maybeRead(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PageChromeScope>()?.notifier;
}

/// Declarative helper a sub-page wraps around its body to publish [title] /
/// [onBack] to the shell's app bar. Re-publishes whenever those change and is a
/// silent no-op where no [PageChromeScope] is present (e.g. in unit tests).
class PageChrome extends StatefulWidget {
  const PageChrome({
    super.key,
    this.title,
    this.onBack,
    this.bottom,
    this.bottomHeight = 0,
    this.actions = const [],
    this.fullWidth = false,
    required this.child,
  });

  final String? title;
  final VoidCallback? onBack;

  /// Optional toolbar docked into the app bar below the title (compact only).
  /// See [PageChromeData.bottom].
  final Widget? bottom;
  final double bottomHeight;

  /// Trailing primary actions rendered in the shell's glass app bar.
  /// See [PageChromeData.actions].
  final List<PageAction> actions;

  /// Whether this page sizes itself to the whole content area.
  /// See [PageChromeData.fullWidth].
  final bool fullWidth;

  final Widget child;

  @override
  State<PageChrome> createState() => _PageChromeState();
}

class _PageChromeState extends State<PageChrome> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedulePublish();
  }

  @override
  void didUpdateWidget(PageChrome oldWidget) {
    super.didUpdateWidget(oldWidget);
    // [bottom] is rebuilt with fresh state on every page build, so compare by
    // identity — a new instance re-publishes so the docked toolbar reflects the
    // latest grouping/sort/filter selection.
    if (oldWidget.title != widget.title ||
        !identical(oldWidget.onBack, widget.onBack) ||
        !identical(oldWidget.bottom, widget.bottom) ||
        oldWidget.bottomHeight != widget.bottomHeight ||
        oldWidget.fullWidth != widget.fullWidth ||
        !listEquals(oldWidget.actions, widget.actions)) {
      _schedulePublish();
    }
  }

  // Publishing after the frame keeps us clear of the build phase (the shell's
  // top bar listens to the same controller) and lets us read the active route.
  void _schedulePublish() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = PageChromeScope.maybeRead(context);
      if (controller == null) return;
      controller.publish(
        PageChromeData(
          location: GoRouterState.of(context).matchedLocation,
          title: widget.title,
          onBack: widget.onBack,
          bottom: widget.bottom,
          bottomHeight: widget.bottomHeight,
          actions: widget.actions,
          fullWidth: widget.fullWidth,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
