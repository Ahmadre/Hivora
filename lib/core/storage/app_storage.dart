import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/server_profile.dart';
import 'secret_store_environment.dart';

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
  AppStorage(this._prefs, this._secure, {SecretStoreEnvironment? secretStore})
    : secretStore = secretStore ?? detectSecretStoreEnvironment();

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

  /// What this system's secret store *is*, so a failure can be explained with
  /// the fix that actually applies here rather than a generic apology. Resolved
  /// once at construction; the environment it reads cannot change under a
  /// running process. Injectable for tests.
  final SecretStoreEnvironment secretStore;

  /// Per-server token caches (keyed by server URL), populated from secure
  /// storage at [create] so [accessToken]/[refreshToken] can stay synchronous.
  final Map<String, String> _accessCache = {};
  final Map<String, String> _refreshCache = {};

  bool _sessionIsMemoryOnly = false;

  /// How the store refused, the last time it did. Null while it has not.
  SecretStoreFailure? _secretStoreFailure;

  /// True when the tokens could not be read from or written to secure storage,
  /// so the session lives only as long as this process.
  ///
  /// Linux is the platform where this actually happens: its secure storage is
  /// the Secret Service, which means a running keyring (GNOME Keyring,
  /// KWallet). Three systems fail it. A desktop without a keyring at all — a
  /// minimal window manager, a container, a login that never unlocked one. A
  /// strictly confined snap, where the keyring is running perfectly well on the
  /// session bus but the sandbox is not allowed to talk to it until
  /// `password-manager-service` is connected, which snapd deliberately does not
  /// do on its own. And either of those with a keyring that is simply *locked*
  /// at boot. In all three libsecret *throws* rather than answering null, so
  /// every call site here is guarded and this flag is what is left.
  ///
  /// The app keeps working; only persistence is lost. Nothing is written
  /// anywhere else as a consolation — see [setTokens] for why. What to tell the
  /// user is [secretStoreNotice], which needs both halves: [secretStore] for
  /// the system, and the thrown error for whether the store was *unreachable*
  /// or merely locked.
  bool get sessionIsMemoryOnly => _sessionIsMemoryOnly;

  /// The sentence to show — and the command to offer — for the failure that set
  /// [sessionIsMemoryOnly]. Null while the store is fine.
  ///
  /// Both inputs matter, and the second one is why this is not simply a
  /// property of [secretStore]. A snap whose interface *is* connected, on a
  /// machine whose login keyring is locked at boot, would otherwise be told it
  /// "isn't allowed to use this system's password store yet" and handed a
  /// `snap connect` line for a permission that is already granted — sending the
  /// user to App Center to look at a switch that is already on, at the exact
  /// moment the message was meant to help.
  SecretStoreNotice? get secretStoreNotice {
    final failure = _secretStoreFailure;
    return failure == null ? null : secretStore.noticeFor(failure);
  }

  /// Records a refusal: the session is memory-only from here, and this is how
  /// the store said so.
  void _noteSecretStoreFailure(Object error) {
    _sessionIsMemoryOnly = true;
    _secretStoreFailure = classifySecretStoreFailure(error);
  }

  static Future<AppStorage> create() async {
    // flutter_secure_storage 10.x defaults to strong encryption on every
    // platform (Android: RSA-OAEP key + AES-GCM storage; iOS/macOS: Keychain),
    // so no per-platform options are needed — the deprecated Android
    // encryptedSharedPreferences flag is intentionally not set.
    const secure = FlutterSecureStorage();
    final storage = AppStorage(await SharedPreferences.getInstance(), secure);
    await storage.restore();
    return storage;
  }

  /// The boot sequence: legacy migrations, then the token cache.
  ///
  /// Split out of [create] so a test can drive it against an injected
  /// [secretStore] and a secure store that throws. Every step swallows a
  /// secret store that cannot be reached — nothing in here may throw, because
  /// `main` awaits it before `runApp` and an exception would mean a Linux
  /// desktop with no keyring never reaches its own login screen.
  ///
  /// **No availability probe, and that is deliberate.** An earlier version
  /// asked the store a throwaway question at launch so a snap user could be
  /// told to run `snap connect` *before* spending a sign-in on it. Look at what
  /// a read costs on Linux: `flutter_secure_storage_linux` runs a "warmup"
  /// before every lookup and, if the default collection is locked, calls
  /// `secret_service_unlock_sync` — which raises the desktop's keyring-password
  /// dialog. Inside an *unconnected* snap that is harmless (the bus name is
  /// denied, nothing can prompt), but a snap with the permission granted is an
  /// ordinary Secret Service client: on a machine that autologs in, with the
  /// login keyring still locked, the probe put a password box on screen the
  /// instant the app opened — every launch, for users whose setup is perfectly
  /// correct. That is a recurring interruption for people who did nothing
  /// wrong, traded against one wasted sign-in for people who need to connect an
  /// interface once. The reads below already ask the question for everyone who
  /// has signed in before, and [setTokens] answers it for everyone else at the
  /// moment it becomes true — with the error in hand, which is also the only
  /// way to know *why* it failed.
  Future<void> restore() async {
    await _migrateToMultiServer();
    await _migrateTokensToSecureStorage();
    await _loadTokenCache();
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
  ///
  /// The secure-storage deletes are best-effort for the same reason
  /// [clearTokens]'s are: on a system with no reachable secret store they
  /// throw, and an exception escaping here would abort the removal *after* the
  /// server list had already been rewritten — leaving the app pointed at a
  /// server it no longer lists. The caches above are what this run actually
  /// forgets.
  Future<void> removeServer(String url) async {
    await _saveServers(servers.where((s) => s.url != url).toList());
    _accessCache.remove(url);
    _refreshCache.remove(url);
    await _deleteQuietly(_accessKey(url));
    await _deleteQuietly(_refreshKey(url));
    if (serverUrl == url) await _prefs.remove(_kServerUrl);
  }

  /// Deletes [key] from secure storage, swallowing a store that cannot be
  /// reached. A store this cannot reach is a store that never held the token.
  Future<void> _deleteQuietly(String key) async {
    try {
      await _secure.delete(key: key);
    } catch (_) {
      // Deliberately silent — see the callers.
    }
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

  /// Stores this server's tokens.
  ///
  /// **The fallback is memory and only memory.** When secure storage refuses,
  /// the tokens stay in [_accessCache]/[_refreshCache] — process memory, gone
  /// when the app quits — and are written nowhere else. Not to
  /// SharedPreferences, not to a file under the app's data directory, not to a
  /// "temporary" anything. The trade-off is deliberate and it is the right way
  /// round: the cost of refusing to degrade is that the user signs in again
  /// after a restart, once, with a toast that says why. The cost of degrading
  /// would be a long-lived refresh token sitting in plaintext on exactly the
  /// systems that just told us they have nowhere safe to put it — a container,
  /// a shared login, a sandbox with no keyring — where anything that can read
  /// the user's home directory could then act as them until it expires.
  ///
  /// That is a statement about *this* method, and it holds for every token this
  /// app has ever created. The one plaintext token that can exist on disk is a
  /// copy an older, pre-secure-storage build wrote before it was upgraded;
  /// [_migrateTokensToSecureStorage] deletes it the moment the store will take
  /// it, and [_migrateToMultiServer] never adds one on a system where the store
  /// works.
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
      _secretStoreFailure = null;
    } catch (error) {
      // Non-fatal: keep the in-memory session, and remember that it is only
      // that — and how the store said so, because "nothing answered" and "the
      // keyring is locked" have different fixes and this is where a first-run
      // user (nothing saved yet, so nothing has failed yet) first finds out.
      _noteSecretStoreFailure(error);
    }
  }

  /// Drops this server's tokens: out of the in-memory caches first, then out of
  /// secure storage.
  ///
  /// Best-effort on the storage side, and deliberately so. The desktop that
  /// cannot *write* a token (see [sessionIsMemoryOnly]) cannot delete one
  /// either, and this used to throw straight out of the sign-out handler —
  /// past the `emit(unauthenticated)` that follows it, leaving the user in the
  /// authenticated shell with a session that had already been dropped from
  /// memory and every request failing. Each key is deleted on its own so a
  /// failure on the first cannot skip the second.
  Future<void> clearTokens() async {
    final url = serverUrl;
    if (url == null) return;
    _accessCache.remove(url);
    _refreshCache.remove(url);
    for (final key in [_accessKey(url), _refreshKey(url)]) {
      // Clearing the caches above is what signs this run out.
      await _deleteQuietly(key);
    }
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
      } catch (error) {
        // Secure storage unavailable for this server — treat as signed out, and
        // remember why. This is the half of the problem the user actually meets:
        // the tokens were written on a previous run, the keyring is there but
        // locked at boot, and the app simply asks for the password again. The
        // warning that goes with the flag is the only thing that connects the
        // two — and the error is what keeps that warning from advising a snap
        // permission to someone whose keyring is merely locked.
        _noteSecretStoreFailure(error);
      }
    }
  }

  /// One-time migration of any plaintext per-server tokens still living in
  /// SharedPreferences (from a build before secure storage) into secure storage,
  /// wiping the plaintext copies afterwards.
  ///
  /// Retried on every launch for as long as one is left, because the reason it
  /// could not run — no keyring, a locked one, a snap plug nobody has connected
  /// yet — is exactly the kind of thing a user fixes between two launches.
  Future<void> _migrateTokensToSecureStorage() async {
    for (final server in servers) {
      await _liftPlaintextToken(_accessKey(server.url));
      await _liftPlaintextToken(_refreshKey(server.url));
    }
  }

  /// Moves one leftover plaintext token out of SharedPreferences into the
  /// secret store, under the same [key].
  ///
  /// The prefs copy is removed only once the store has taken it, never before.
  /// If secure storage is unavailable the plaintext copy stays exactly where it
  /// already was rather than being dropped: it is a copy an *older build of
  /// this app* wrote, on a platform that had a working store at the time, and
  /// deleting it would sign the user out of a session that a keyring unlocked
  /// tomorrow would have kept. This is not the plaintext fallback [setTokens]
  /// refuses to make — nothing here ever creates a token in prefs, it only ends
  /// one that is already there.
  Future<void> _liftPlaintextToken(String key) async {
    final value = _prefs.getString(key);
    if (value == null) return;
    try {
      await _secure.write(key: key, value: value);
      await _prefs.remove(key);
    } catch (error) {
      // The store just refused a write, so this session will not survive a
      // restart either — the same conclusion [setTokens] draws, reached one
      // step earlier for a user who is upgrading rather than signing in.
      _noteSecretStoreFailure(error);
    }
  }

  /// One-time upgrade from the single-server layout (a lone `server_url` plus
  /// global `access_token`/`refresh_token`) to the multi-server layout: seed the
  /// server list from the existing URL and move its tokens to the per-server
  /// keys. Runs once — the presence of [_kServers] marks it done.
  ///
  /// The tokens go straight into the secret store. They used to be parked in the
  /// per-server *prefs* keys for [_migrateTokensToSecureStorage] to lift a
  /// moment later, which meant that on a perfectly healthy desktop this run
  /// wrote a refresh token into plaintext — briefly, but really, and a crash or
  /// a kill in the window between the two left it there for good. Only when the
  /// store refuses does a prefs copy survive this method, and then it is a
  /// re-keying of one that is already sitting in that same file under the old
  /// name, not a new one.
  Future<void> _migrateToMultiServer() async {
    if (_prefs.containsKey(_kServers)) return;
    final url = _prefs.getString(_kServerUrl);
    final list = <ServerProfile>[];
    if (url != null && url.isNotEmpty) {
      list.add(ServerProfile(url: url));
      await _rehomeLegacyToken(_kAccessToken, _accessKey(url));
      await _rehomeLegacyToken(_kRefreshToken, _refreshKey(url));
    }
    await _prefs.remove(_kAccessToken);
    await _prefs.remove(_kRefreshToken);
    await _saveServers(list);
  }

  /// Moves the one global pre-multi-server token at [legacyKey] to [key]: into
  /// the secret store if it will take it, and only otherwise into the
  /// per-server prefs key, where [_migrateTokensToSecureStorage] retries it on
  /// every later launch. Re-keyed rather than left under the global name so the
  /// token stays attached to the server that issued it — by the time the store
  /// comes back, the current server can be a different one.
  Future<void> _rehomeLegacyToken(String legacyKey, String key) async {
    final value = _prefs.getString(legacyKey);
    if (value == null) return;
    try {
      await _secure.write(key: key, value: value);
    } catch (error) {
      _noteSecretStoreFailure(error);
      await _prefs.setString(key, value);
    }
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
