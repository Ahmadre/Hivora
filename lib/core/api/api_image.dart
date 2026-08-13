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
/// With [previewPath] the provider loads *progressively*: the small server-side
/// thumbnail is decoded and shown first, then replaced by the original once it
/// arrives. A document full of pictures therefore paints in a fraction of the
/// bytes instead of holding empty boxes until every original has downloaded.
///
/// Decoded frames land in Flutter's own [ImageCache] under this key, so the
/// same media shown twice — a document and its preview — is fetched once.
@immutable
class ApiImage extends ImageProvider<ApiImage> {
  /// Loads [path] (app-relative, leading slash) through [api].
  const ApiImage(
    this.path, {
    required this.api,
    this.previewPath,
    this.scale = 1.0,
  });

  /// The path on the current server, e.g. `/api/v1/media/<uuid>`.
  final String path;

  /// Optional path of a small preview of the same picture, shown first.
  final String? previewPath;

  /// The client whose base URL and bearer token the request is made with.
  final ApiClient api;

  /// Pixel density of the decoded image.
  final double scale;

  @override
  Future<ApiImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<ApiImage>(this);

  @override
  ImageStreamCompleter loadImage(ApiImage key, ImageDecoderCallback decode) {
    if (key.previewPath == null) {
      return MultiFrameImageStreamCompleter(
        codec: _load(key, key.path, decode),
        scale: key.scale,
        debugLabel: key.path,
        informationCollector: () => [
          ErrorDescription('Media path: ${key.path}'),
        ],
      );
    }
    return _ProgressiveImageStreamCompleter(key, decode);
  }

  Future<ui.Codec> _load(
    ApiImage key,
    String path,
    ImageDecoderCallback decode,
  ) async {
    final result = await key.api.getBytes(path);
    final bytes = result?.bytes;
    if (bytes == null || bytes.isEmpty) {
      // Evict, or a transient 502 is remembered as "this image is broken" for
      // as long as the app runs.
      await Future<void>.microtask(() => imageCache.evict(key));
      throw StateError('media $path could not be loaded');
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
          '[media] $path: ${bytes.length} bytes of '
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
      other.previewPath == previewPath &&
      identical(other.api, api) &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(path, previewPath, api, scale);

  @override
  String toString() => 'ApiImage("$path")';
}

/// Emits the thumbnail as a first frame and the original as a second one.
///
/// Multiple frames are exactly what an [ImageStreamCompleter] is for (it is how
/// animated images work), so no widget has to know that two requests happened —
/// the picture simply sharpens. A failing preview is skipped in silence; only a
/// failing original is an error, because only then is there nothing to show.
class _ProgressiveImageStreamCompleter extends ImageStreamCompleter {
  _ProgressiveImageStreamCompleter(this._key, this._decode) {
    _load();
  }

  final ApiImage _key;
  final ImageDecoderCallback _decode;

  Future<void> _load() async {
    try {
      final preview = await _frame(_key.previewPath!);
      // Guard against the (unlikely) case where the original wins the race.
      if (preview != null && !_settled) {
        setImage(ImageInfo(image: preview, scale: _key.scale));
      }
    } catch (_) {
      // A preview is an optimisation; its absence is not worth reporting.
    }
    try {
      final full = await _frame(_key.path);
      if (full == null) {
        throw StateError('media ${_key.path} could not be loaded');
      }
      _settled = true;
      setImage(ImageInfo(image: full, scale: _key.scale));
    } catch (error, stack) {
      await Future<void>.microtask(() => imageCache.evict(_key));
      reportError(
        context: ErrorDescription('resolving an ApiImage'),
        exception: error,
        stack: stack,
        informationCollector: () => [
          ErrorDescription('Media path: ${_key.path}'),
        ],
        silent: true,
      );
    }
  }

  bool _settled = false;

  /// Fetches + decodes one frame, or null when the endpoint returned nothing.
  Future<ui.Image?> _frame(String path) async {
    final result = await _key.api.getBytes(path);
    final bytes = result?.bytes;
    if (bytes == null || bytes.isEmpty) return null;
    final buffer = await ui.ImmutableBuffer.fromUint8List(
      bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
    );
    final codec = await _decode(buffer);
    final frame = await codec.getNextFrame();
    return frame.image;
  }
}
