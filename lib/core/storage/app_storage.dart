import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/server_profile.dart';

/// Thin wrapper around SharedPreferences for app-level persistence.
///
/// The app can hold several saved servers and switch between them. The
/// currently selected server lives under [_kServerUrl]; the full list lives
/// under [_kServers], both in SharedPreferences (non-secret).
///
/// Auth tokens (access + refresh) are **scoped per server** (keyed by URL) and
/// persisted in [FlutterSecureStorage] (Keychain on iOS/macOS, EncryptedShared-
/// Preferences on Android) — never plaintext SharedPreferences. They are mirrored
/// into an in-memory cache at startup so the getters stay synchronous for the
/// Dio interceptor / auth hot paths.
class AppStorage {
  AppStorage(this._prefs, this._secure);

  static const _kServerUrl = 'server_url';
  static const _kServers = 'servers.v1';
  static const _kAccessToken = 'access_token';
  static const _kRefreshToken = 'refresh_token';
  static const _kOnboardingDone = 'onboarding_done';
  static const _kConnectHintSeen = 'connect_hint_seen';
  static const _kLocale = 'locale';
  static const _kRecentSearch = 'hinata.recentSearch.v1';
  // v2 holds a list; v1 held a single id under the old key name and is simply
  // left behind — reading a String back as a StringList would throw, and the
  // worst a fresh key costs is that one already-opened notification could be
  // opened once more.
  static const _kOpenedNotifications = 'hinata.openedNotifications.v2';

  /// Maximum number of recent global-search queries kept on device.
  static const recentSearchMax = 6;

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;

  /// Per-server token caches (keyed by server URL), populated from secure
  /// storage at [create] so [accessToken]/[refreshToken] can stay synchronous.
  final Map<String, String> _accessCache = {};
  final Map<String, String> _refreshCache = {};

  bool _sessionIsMemoryOnly = false;

  /// True when the tokens could not be written to secure storage, so the
  /// session lives only as long as this process.
  ///
  /// Linux is the platform where this actually happens: its secure storage is
  /// the Secret Service, which means a running keyring (GNOME Keyring,
  /// KWallet). A desktop without one — a minimal window manager, a container, a
  /// login that never unlocked the keyring — fails every write. The app keeps
  /// working, but the user is signed out again on the next launch, and being
  /// told that once beats discovering it every morning.
  bool get sessionIsMemoryOnly => _sessionIsMemoryOnly;

  static Future<AppStorage> create() async {
    // flutter_secure_storage 10.x defaults to strong encryption on every
    // platform (Android: RSA-OAEP key + AES-GCM storage; iOS/macOS: Keychain),
    // so no per-platform options are needed — the deprecated Android
    // encryptedSharedPreferences flag is intentionally not set.
    const secure = FlutterSecureStorage();
    final storage = AppStorage(await SharedPreferences.getInstance(), secure);
    await storage._migrateToMultiServer();
    await storage._migrateTokensToSecureStorage();
    await storage._loadTokenCache();
    return storage;
  }

  // --- current server --------------------------------------------------------

  /// The URL of the server the app is currently talking to (null on first run).
  String? get serverUrl => _prefs.getString(_kServerUrl);

  /// Selects [url] as the current server (adding it to the saved list if new).
  /// Kept as the historical setter name so existing callers (connect flow,
  /// deep-link handoff) transparently register the server too.
  Future<void> setServerUrl(String url) => setCurrentServer(url);

  Future<void> setCurrentServer(String url) async {
    await upsertServer(ServerProfile(url: url));
    await _prefs.setString(_kServerUrl, url);
  }

  // --- saved servers ---------------------------------------------------------

  /// All servers the user has connected to, in insertion order.
  List<ServerProfile> get servers {
    final raw = _prefs.getString(_kServers);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => ServerProfile.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// Adds [profile], or refreshes the label of an already-saved server. A null
  /// or blank incoming label never clobbers a previously stored one.
  Future<void> upsertServer(ServerProfile profile) async {
    final list = servers.toList();
    final i = list.indexWhere((s) => s.url == profile.url);
    if (i >= 0) {
      final keepLabel = (profile.label?.trim().isNotEmpty ?? false)
          ? profile.label
          : list[i].label;
      list[i] = ServerProfile(url: profile.url, label: keepLabel);
    } else {
      list.add(profile);
    }
    await _saveServers(list);
  }

  /// Forgets a server: drops it from the list and wipes its scoped tokens. If it
  /// was the current server, the current selection is cleared (the caller then
  /// switches elsewhere or routes back to the connect screen).
  Future<void> removeServer(String url) async {
    await _saveServers(servers.where((s) => s.url != url).toList());
    _accessCache.remove(url);
    _refreshCache.remove(url);
    await _secure.delete(key: _accessKey(url));
    await _secure.delete(key: _refreshKey(url));
    if (serverUrl == url) await _prefs.remove(_kServerUrl);
  }

  Future<void> _saveServers(List<ServerProfile> list) => _prefs.setString(
    _kServers,
    jsonEncode(list.map((s) => s.toJson()).toList()),
  );

  // --- tokens (scoped to the current server) ---------------------------------

  String _accessKey(String url) => '$_kAccessToken::$url';
  String _refreshKey(String url) => '$_kRefreshToken::$url';

  String? get accessToken {
    final url = serverUrl;
    return url == null ? null : _accessCache[url];
  }

  String? get refreshToken {
    final url = serverUrl;
    return url == null ? null : _refreshCache[url];
  }

  Future<void> setTokens({
    required String access,
    required String refresh,
  }) async {
    final url = serverUrl;
    if (url == null) return;
    // Cache first so the (synchronous) getters serve the new tokens immediately,
    // even if the secure-storage write is momentarily unavailable on some
    // platform — the session still works this run; worst case is a re-login next
    // launch rather than a crash.
    _accessCache[url] = access;
    _refreshCache[url] = refresh;
    try {
      await _secure.write(key: _accessKey(url), value: access);
      await _secure.write(key: _refreshKey(url), value: refresh);
      _sessionIsMemoryOnly = false;
    } catch (_) {
      // Non-fatal: keep the in-memory session, and remember that it is only
      // that, so the app can say so instead of silently losing the login.
      _sessionIsMemoryOnly = true;
    }
  }

  Future<void> clearTokens() async {
    final url = serverUrl;
    if (url == null) return;
    _accessCache.remove(url);
    _refreshCache.remove(url);
    await _secure.delete(key: _accessKey(url));
    await _secure.delete(key: _refreshKey(url));
  }

  /// Loads every saved server's tokens from secure storage into the in-memory
  /// caches so the synchronous getters can serve them on the hot path.
  Future<void> _loadTokenCache() async {
    for (final server in servers) {
      try {
        final access = await _secure.read(key: _accessKey(server.url));
        final refresh = await _secure.read(key: _refreshKey(server.url));
        if (access != null) _accessCache[server.url] = access;
        if (refresh != null) _refreshCache[server.url] = refresh;
      } catch (_) {
        // Secure storage unavailable for this server — treat as signed out.
      }
    }
  }

  /// One-time migration of any plaintext per-server tokens still living in
  /// SharedPreferences (from a build before secure storage) into secure storage,
  /// wiping the plaintext copies afterwards.
  Future<void> _migrateTokensToSecureStorage() async {
    for (final server in servers) {
      final legacyAccess = _prefs.getString(_accessKey(server.url));
      final legacyRefresh = _prefs.getString(_refreshKey(server.url));
      try {
        if (legacyAccess != null) {
          await _secure.write(key: _accessKey(server.url), value: legacyAccess);
          await _prefs.remove(_accessKey(server.url));
        }
        if (legacyRefresh != null) {
          await _secure.write(
            key: _refreshKey(server.url),
            value: legacyRefresh,
          );
          await _prefs.remove(_refreshKey(server.url));
        }
      } catch (_) {
        // If secure storage is unavailable, leave the plaintext copy in place
        // rather than dropping the user's session; retried next launch.
      }
    }
  }

  /// One-time upgrade from the single-server layout (a lone `server_url` plus
  /// global `access_token`/`refresh_token`) to the multi-server layout: seed the
  /// server list from the existing URL and move its tokens into the per-server
  /// keys. Runs once — the presence of [_kServers] marks it done. (Tokens land in
  /// prefs here and are then lifted into secure storage by
  /// [_migrateTokensToSecureStorage], which runs right after.)
  Future<void> _migrateToMultiServer() async {
    if (_prefs.containsKey(_kServers)) return;
    final url = _prefs.getString(_kServerUrl);
    final list = <ServerProfile>[];
    if (url != null && url.isNotEmpty) {
      list.add(ServerProfile(url: url));
      final access = _prefs.getString(_kAccessToken);
      final refresh = _prefs.getString(_kRefreshToken);
      if (access != null) await _prefs.setString(_accessKey(url), access);
      if (refresh != null) await _prefs.setString(_refreshKey(url), refresh);
    }
    await _prefs.remove(_kAccessToken);
    await _prefs.remove(_kRefreshToken);
    await _saveServers(list);
  }

  // --- misc ------------------------------------------------------------------

  bool get onboardingDone => _prefs.getBool(_kOnboardingDone) ?? false;
  Future<void> setOnboardingDone() => _prefs.setBool(_kOnboardingDone, true);

  // --- Hinata Connect first-login hint (scoped per server) -------------------

  String _connectHintKey(String url) => '$_kConnectHintSeen::$url';

  /// Whether the "get a Connect licence" hint has already been shown for the
  /// current server. Scoped per instance — each self-hosted server an admin
  /// connects to is prompted once. Returns true (suppressed) when no server is
  /// selected yet.
  bool get connectHintSeen {
    final url = serverUrl;
    return url == null ? true : (_prefs.getBool(_connectHintKey(url)) ?? false);
  }

  Future<void> setConnectHintSeen() async {
    final url = serverUrl;
    if (url == null) return;
    await _prefs.setBool(_connectHintKey(url), true);
  }

  String? get locale => _prefs.getString(_kLocale);
  Future<void> setLocale(String code) => _prefs.setString(_kLocale, code);

  /// The ids of notifications whose deep link has already been opened.
  ///
  /// A notification tap that starts the app is handed to it by the OS as the
  /// "launch notification", and on macOS the same one comes back on later
  /// launches the app was never told to make — which reopened a months-old
  /// comment every time the app was started. Recorded before the link is
  /// followed, so a launch link is followed at most once per notification, ever.
  ///
  /// A *list*, not a single id: remembering only the last one meant two
  /// notifications took turns evicting each other, and the stale launch
  /// notification came back the moment any other one had been opened in between.
  /// The window is small on purpose — it only has to outlive how long a
  /// notification can linger in Notification Center, not the install.
  List<String> get openedNotificationIds =>
      _prefs.getStringList(_kOpenedNotifications) ?? const <String>[];

  /// Maximum number of opened-notification ids kept on device.
  static const openedNotificationsMax = 50;

  bool hasOpenedNotification(String id) => openedNotificationIds.contains(id);

  Future<void> rememberOpenedNotification(String id) async {
    final ids = openedNotificationIds.toList()
      ..remove(id)
      ..add(id);
    if (ids.length > openedNotificationsMax) {
      ids.removeRange(0, ids.length - openedNotificationsMax);
    }
    await _prefs.setStringList(_kOpenedNotifications, ids);
  }

  /// Tooling-only: lets the screenshot harness force the boot route via a
  /// pre-seeded pref (no effect in normal use, where the key is absent).
  String? get screenshotRoute => _prefs.getString('screenshot_route');

  /// Tooling-only: the screenshot harness sets this for tablet captures so the
  /// app pins landscape (a simulator/emulator can't be rotated reliably). No
  /// effect in normal use, where the key is absent.
  bool get screenshotLandscape =>
      _prefs.getBool('screenshot_landscape') ?? false;

  /// Recent global-search queries, most-recent first (max [recentSearchMax]).
  List<String> get recentSearches =>
      _prefs.getStringList(_kRecentSearch) ?? const [];

  Future<void> setRecentSearches(List<String> list) =>
      _prefs.setStringList(_kRecentSearch, list.take(recentSearchMax).toList());
}
