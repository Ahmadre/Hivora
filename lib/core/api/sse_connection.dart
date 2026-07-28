import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;

import 'sse.dart';

/// A resilient Server-Sent Events consumer shared by every live view in the app
/// (comments, attachments, issue links, account sign-out).
///
/// It opens a stream via [open], parses frames to [onEvent], and keeps itself
/// honest about liveness. The failure that silently breaks SSE on mobile and
/// behind proxies is a *half-open* socket: the peer is gone but the OS never
/// reports the connection closed, so `onDone`/`onError` never fire and the
/// client waits forever on a dead stream — the view simply stops updating until
/// a manual reload. To defeat that, every received byte — including the server's
/// periodic heartbeat comments, which [parseSse] filters out — resets an idle
/// watchdog; if nothing arrives within [idleTimeout] the connection is treated
/// as dead and cycled with capped exponential backoff.
///
/// On every reconnect *after the first*, [onReconnect] fires so callers can
/// reconcile whatever changed while the stream was down. The first connect
/// deliberately does NOT fire it — the view's initial load already has fresh
/// data, so re-fetching on open would just double the work.
class SseConnection {
  SseConnection({
    required Future<Stream<List<int>>> Function(CancelToken cancelToken) open,
    required void Function(SseEvent event) onEvent,
    void Function()? onReconnect,
    Duration idleTimeout = const Duration(seconds: 45),
  }) : _open = open,
       _onEvent = onEvent,
       _onReconnect = onReconnect,
       _idleTimeout = idleTimeout;

  final Future<Stream<List<int>>> Function(CancelToken) _open;
  final void Function(SseEvent) _onEvent;
  final void Function()? _onReconnect;
  final Duration _idleTimeout;

  CancelToken? _cancel;
  StreamSubscription<SseEvent>? _sub;
  Timer? _reconnectTimer;
  Timer? _watchdog;
  int _attempts = 0;
  bool _connectedOnce = false;
  bool _running = false;

  /// Opens the stream and begins consuming (no-op if already running).
  void start() {
    if (_running) return;
    _running = true;
    _connect();
  }

  /// Tears the connection down and cancels any pending reconnect. The instance
  /// can be [start]ed again (e.g. the account stream across sign-in sessions).
  void stop() {
    _running = false;
    _watchdog?.cancel();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _sub?.cancel();
    _sub = null;
    _cancel?.cancel();
    _cancel = null;
    _attempts = 0;
    _connectedOnce = false;
  }

  Future<void> _connect() async {
    if (!_running) return;
    // Cancel any prior token before overwriting it so a reconnect can never
    // orphan a half-opened streamed GET that still holds a connection slot.
    _cancel?.cancel();
    _cancel = CancelToken();
    try {
      final bytes = await _open(_cancel!);
      // Stopped WHILE opening → tear the just-opened connection down instead of
      // subscribing (a leaked SSE connection holds a server slot open).
      if (!_running) {
        _cancel?.cancel();
        return;
      }
      _attempts = 0;
      final reconnected = _connectedOnce;
      _connectedOnce = true;
      // Reset the watchdog on every RAW chunk (heartbeat comments included) so
      // a quiet-but-alive stream is never mistaken for a dead one.
      final live = bytes.map((chunk) {
        _resetWatchdog();
        return chunk;
      });
      _sub = parseSse(live).listen(
        _onEvent,
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
        cancelOnError: true,
      );
      _resetWatchdog();
      if (reconnected) _onReconnect?.call();
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _resetWatchdog() {
    _watchdog?.cancel();
    if (!_running) return;
    _watchdog = Timer(_idleTimeout, _scheduleReconnect);
  }

  void _scheduleReconnect() {
    _watchdog?.cancel();
    _sub?.cancel();
    _sub = null;
    if (!_running) return;
    _reconnectTimer?.cancel();
    // Exponential backoff (3s → 30s cap) so a persistently failing stream
    // (e.g. offline, or SSE not streamable) doesn't hammer the server.
    final secs = (3 * (1 << _attempts)).clamp(3, 30);
    _attempts = (_attempts + 1).clamp(0, 4);
    _reconnectTimer = Timer(Duration(seconds: secs), _connect);
  }
}
