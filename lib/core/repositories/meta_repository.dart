import '../api/api_client.dart';
import '../models/core_models.dart';

/// Server metadata, reachability probing, and first-run setup.
class MetaRepository {
  MetaRepository(this._api);

  final ApiClient _api;

  /// The configured backend base URL (e.g. `https://api.example.com`). Used
  /// to derive shareable web links to in-app resources.
  String get apiBaseUrl => _api.baseUrl;

  Future<ServerMeta> meta() async => ServerMeta.fromJson(
    await _api.get('/api/v1/meta') as Map<String, dynamic>,
  );

  /// Reachability test for a *candidate* server [url] the app is not yet bound
  /// to — powers the "add server" connection test and the live status dots in
  /// the server manager. Returns null when the server is unreachable.
  Future<ServerProbe?> probeServer(String url) => _api.probe(url);

  Future<void> completeSetup({
    required String organizationName,
    required String adminEmail,
    required String adminUsername,
    required String adminDisplayName,
    required String adminPassword,
  }) => _api.post(
    '/api/v1/setup',
    body: {
      'organizationName': organizationName,
      'adminEmail': adminEmail,
      'adminUsername': adminUsername,
      'adminDisplayName': adminDisplayName,
      'adminPassword': adminPassword,
    },
  );

  /// Fetches the configured organization logo through the server-side proxy
  /// (`/api/v1/meta/logo`) so it is delivered same-origin (no browser CORS).
  /// Returns the raw bytes plus whether the payload is SVG, or null when no
  /// logo is configured / reachable. Pass [cacheBust] (e.g. an incrementing
  /// token) to force a fresh fetch past the HTTP cache after a re-upload.
  Future<({List<int> bytes, bool isSvg})?> organizationLogo({
    int? cacheBust,
  }) async {
    final path = cacheBust == null
        ? '/api/v1/meta/logo'
        : '/api/v1/meta/logo?v=$cacheBust';
    final result = await _api.getBytes(path);
    if (result == null) return null;
    final head = String.fromCharCodes(result.bytes.take(256)).toLowerCase();
    final isSvg =
        result.contentType.contains('svg') ||
        head.contains('<svg') ||
        head.contains('<?xml');
    return (bytes: result.bytes, isSvg: isSvg);
  }
}
