/// Loading an image that lives behind the API's bearer token.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'package:flutter/painting.dart';

import 'api_client.dart';

/// An [ImageProvider] for an app-relative media path — `/api/v1/media/<id>`.
///
/// Uploaded images are stored behind the authenticated media proxy, so their
/// address is a path rather than a URL: it has no host, and fetching it needs
/// the current server's bearer token. A [NetworkImage] can supply neither,
/// which is why an uploaded image used to render as a broken box no matter how
/// well the upload itself went.
///
/// Decoded frames land in Flutter's own [ImageCache] under this key, so the
/// same media shown twice — a document and its preview — is fetched once.
@immutable
class ApiImage extends ImageProvider<ApiImage> {
  /// Loads [path] (app-relative, leading slash) through [api].
  const ApiImage(this.path, {required this.api, this.scale = 1.0});

  /// The path on the current server, e.g. `/api/v1/media/<uuid>`.
  final String path;

  /// The client whose base URL and bearer token the request is made with.
  final ApiClient api;

  /// Pixel density of the decoded image.
  final double scale;

  @override
  Future<ApiImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<ApiImage>(this);

  @override
  ImageStreamCompleter loadImage(ApiImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(
        codec: _load(key, decode),
        scale: key.scale,
        debugLabel: key.path,
        informationCollector: () => [
          ErrorDescription('Media path: ${key.path}'),
        ],
      );

  Future<ui.Codec> _load(ApiImage key, ImageDecoderCallback decode) async {
    final result = await key.api.getBytes(key.path);
    final bytes = result?.bytes;
    if (bytes == null || bytes.isEmpty) {
      // Evict, or a transient 502 is remembered as "this image is broken" for
      // as long as the app runs.
      await Future<void>.microtask(() => imageCache.evict(key));
      throw StateError('media ${key.path} could not be loaded');
    }
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(
        bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
      );
      return await decode(buffer);
    } on Object catch (error) {
      // The bytes arrived and could not be turned into a picture. Said out
      // loud, with what did arrive: a decode failure and a failed request both
      // end as the same grey box, and the difference between them is the
      // difference between a broken upload and a broken request.
      if (kDebugMode) {
        debugPrint(
          '[media] ${key.path}: ${bytes.length} bytes of '
          '"${result?.contentType}" did not decode — $error',
        );
      }
      await Future<void>.microtask(() => imageCache.evict(key));
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ApiImage &&
      other.path == path &&
      identical(other.api, api) &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(path, api, scale);

  @override
  String toString() => 'ApiImage("$path")';
}
