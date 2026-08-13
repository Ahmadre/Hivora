import 'package:dio/dio.dart';

import '../api/api_client.dart';

/// The API path of an inline image's small server-side preview, or null when
/// [path] is not an inline media path (an external URL, an asset, a data: URI).
///
/// The server derives the thumbnail's storage key from the media id, so this is
/// a pure string transform — no lookup, and it stays valid for images uploaded
/// before thumbnails existed (that endpoint generates the missing one on first
/// view and falls back to the original when it cannot).
String? mediaThumbnailPath(String path) {
  final match = RegExp(
    r'^/api/v1/media/([0-9a-fA-F-]{36})$',
  ).firstMatch(path.trim());
  return match == null ? null : '${match.group(0)}/thumbnail';
}

/// Free-standing media objects (inline Markdown images in issue descriptions,
/// comments, and knowledge-base articles), served through the authenticated
/// media proxy.
class MediaRepository {
  MediaRepository(this._api);

  final ApiClient _api;

  /// Uploads an inline image (issue description/comment or KB article) and
  /// returns its app-relative URL — e.g. `/api/v1/media/<uuid>` — together with
  /// the BlurHash the server computed for it. Not bound to any entity; readable
  /// by any signed-in user, served back through the authenticated media proxy.
  ///
  /// The hash is what lets an editor store a placeholder *in the document*, so
  /// the picture has a blurred stand-in the next time it is opened, before any
  /// request goes out. It is null for a payload the server could not decode.
  Future<({String url, String? blurHash})> uploadMedia(
    MultipartFile file, {
    CancelToken? cancelToken,
  }) async {
    final data =
        await _api.upload('/api/v1/media', file, cancelToken: cancelToken)
            as Map<String, dynamic>;
    return (url: data['url'] as String, blurHash: data['blurHash'] as String?);
  }

  /// Fetches an app-relative media object's bytes (e.g. an inline comment image
  /// at `/api/v1/media/<uuid>`) through the authenticated proxy — used to copy a
  /// comment's image to the clipboard. Returns null for external/absolute URLs.
  Future<({List<int> bytes, String contentType})?> mediaBytes(String url) {
    if (!url.startsWith('/')) return Future.value(null);
    return _api.getBytes(url);
  }
}
