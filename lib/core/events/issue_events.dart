import 'dart:async';

/// App-wide broadcast for issue changes (create / update / delete).
///
/// Screens that render issues — the issues list, the board, the dashboard —
/// can never be reached by a page-local reload when the change originates from
/// *global* chrome such as the nav-rail "new issue" button: that chrome holds
/// no handle to the currently-visible page's cubit. This lightweight broadcast
/// decouples the two: the origin of a change calls [notifyChanged], and every
/// mounted screen subscribed to [changes] re-fetches through its existing
/// reload seam.
///
/// A single app-wide instance ([instance]) is intentional — the stream is a
/// broadcast controller, so it is safe to have many concurrent listeners and it
/// never needs disposing for the app's lifetime. Subscribers must still cancel
/// their own [StreamSubscription] in `dispose`.
class IssueEvents {
  IssueEvents._();

  /// The shared app-wide instance.
  static final IssueEvents instance = IssueEvents._();

  final StreamController<void> _controller = StreamController<void>.broadcast();

  /// Fires whenever an issue is created, updated or deleted anywhere in the app.
  Stream<void> get changes => _controller.stream;

  /// Signal that the set of issues changed so subscribed screens re-fetch.
  void notifyChanged() => _controller.add(null);
}

/// App-wide broadcast for *watch* changes only.
///
/// Deliberately separate from [IssueEvents]: subscribing to an issue changes no
/// field any list renders, so routing it through the general bus would make the
/// board and the issues list re-fetch everything for a switch nobody there can
/// see — under an open glass sheet, whose blur then re-runs over the whole
/// panel. Exactly one surface genuinely changes, the "Watched" list, and this is
/// the wire that reaches it.
class IssueWatchEvents {
  IssueWatchEvents._();

  /// The shared app-wide instance.
  static final IssueWatchEvents instance = IssueWatchEvents._();

  final StreamController<void> _controller = StreamController<void>.broadcast();

  /// Fires whenever the signed-in user subscribed to or unsubscribed from an
  /// issue.
  Stream<void> get changes => _controller.stream;

  /// Signal that the caller's set of watched issues changed.
  void notifyChanged() => _controller.add(null);
}
