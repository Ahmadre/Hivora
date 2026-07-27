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

  /// The route this chrome belongs to — the key it is filed under in
  /// [PageChromeController], and the only route the shell will render it for.
  /// Chrome from a page being torn down, or from one still mounted under a
  /// pushed route, is therefore ignored rather than shown or allowed to
  /// displace the visible page's own chrome.
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

/// Carries the chrome published by sub-pages to the shell's top bar.
///
/// Chrome is kept **per route location**, not in a single slot. A page that is
/// no longer on top stays mounted and keeps rebuilding — `/admin` sits under an
/// imperatively pushed `/admin/users`, `/board` under a pushed `/issues/:id` —
/// and every rebuild re-publishes its own (perfectly valid) chrome for its own
/// route. With one slot the background page wins whenever it publishes last,
/// and because the shell only honours chrome whose location matches the visible
/// route, the visible page's title/actions/toolbar don't just get replaced —
/// they vanish, falling back to the route-derived title with no actions at all.
///
/// Who publishes last is genuinely unpredictable: a page under a `LayoutBuilder`
/// (`ResponsiveBuilder`) builds in the layout phase, after pages that build
/// normally, so the loser flips with the widget tree. Keying by location makes
/// the outcome independent of ordering — each route reads back exactly what it
/// published.
class PageChromeController extends ChangeNotifier {
  final Map<String, PageChromeData> _byLocation = {};

  /// The [PageChrome] state behind each entry, so a page can only ever retract
  /// or move chrome it published itself.
  final Map<String, Object> _owners = {};

  PageChromeData? _dataFor(String location) => _byLocation[location];

  String? titleFor(String location) => _dataFor(location)?.title;

  VoidCallback? onBackFor(String location) => _dataFor(location)?.onBack;

  Widget? bottomFor(String location) => _dataFor(location)?.bottom;

  double bottomHeightFor(String location) =>
      _dataFor(location)?.bottomHeight ?? 0;

  List<PageAction> actionsFor(String location) =>
      _dataFor(location)?.actions ?? const [];

  /// Defaults to false, so a page that publishes nothing — or has not published
  /// yet — is laid out like every other page rather than flashing wide first.
  bool fullWidthFor(String location) => _dataFor(location)?.fullWidth ?? false;

  /// Records [data] as the chrome for its own [PageChromeData.location], on
  /// behalf of [owner] (the publishing [PageChrome] state).
  void publish(Object owner, PageChromeData data) {
    final location = data.location;
    // Nothing to key on — a page outside the router can't claim a route's bar.
    if (location == null) return;

    var changed = false;
    // The owner may have published under a different location before (its route
    // changed underneath it); drop that entry so it can't outlive the page.
    for (final stale in _locationsOwnedBy(owner)) {
      if (stale == location) continue;
      _byLocation.remove(stale);
      _owners.remove(stale);
      changed = true;
    }

    final previous = _byLocation[location];
    if (previous == null || !_sameChrome(previous, data)) {
      _byLocation[location] = data;
      changed = true;
    }
    _owners[location] = owner;

    if (changed) notifyListeners();
  }

  /// Drops the chrome [owner] published, on dispose.
  ///
  /// Deliberately silent: a page only unmounts on a route change (the shell
  /// rebuilds for that anyway) or because another page replaced it at the same
  /// location (which publishes on its own). Notifying here would mean marking
  /// the shell dirty from inside the build phase that is tearing the page down.
  void retract(Object owner) {
    for (final location in _locationsOwnedBy(owner)) {
      _byLocation.remove(location);
      _owners.remove(location);
    }
  }

  /// Snapshot — callers mutate the maps while iterating it.
  List<String> _locationsOwnedBy(Object owner) => [
    for (final entry in _owners.entries)
      if (identical(entry.value, owner)) entry.key,
  ];

  static bool _sameChrome(PageChromeData a, PageChromeData b) =>
      a.title == b.title &&
      identical(a.onBack, b.onBack) &&
      identical(a.bottom, b.bottom) &&
      a.bottomHeight == b.bottomHeight &&
      a.fullWidth == b.fullWidth &&
      listEquals(a.actions, b.actions);
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
  /// Held so [dispose] can retract this page's chrome — the context is defunct
  /// by then, so the scope can no longer be looked up.
  PageChromeController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller = PageChromeScope.maybeRead(context);
    _schedulePublish();
  }

  @override
  void dispose() {
    _controller?.retract(this);
    super.dispose();
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
      final controller = _controller;
      if (controller == null) return;
      controller.publish(
        this,
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
