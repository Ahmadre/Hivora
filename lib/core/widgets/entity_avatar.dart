import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../api/api_client.dart';
import 'app_avatar.dart' show ApiImageAvatar;
import 'preview_image.dart' show blurHashProviderFor;

/// The picture of a *thing* — a team, a project — in the rounded-square
/// footprint its glyph already occupies.
///
/// This is the square counterpart to AppAvatar: people are circles with
/// initials, teams and projects are squircles with an icon or a mono key. The
/// two share the loading machinery ([ApiImageAvatar]: one authenticated fetch
/// per URL, a process-wide LRU byte cache, [Image.memory] rather than
/// [NetworkImage] so CanvasKit cannot taint its canvas on the web) but not the
/// shape, so this wraps that widget rather than bending the circular one.
///
/// [fallback] is the glyph that already exists. It is what shows when there is
/// no picture, while one loads without a BlurHash to stand in, and when the
/// fetch fails — an entity is never left as a blank square.
class EntityAvatar extends StatelessWidget {
  const EntityAvatar({
    super.key,
    required this.avatarUrl,
    required this.size,
    required this.radius,
    required this.fallback,
  });

  /// Server-owned avatar URL (`/api/v1/teams/{id}/avatar?v=…&bh=…`), or null.
  final String? avatarUrl;

  /// Edge length of the square, in logical pixels.
  final double size;

  /// Corner radius — matched to the glyph it replaces, so an entity keeps the
  /// same silhouette whether or not it has a picture.
  final double radius;

  /// The tinted icon / mono-key glyph shown when there is no picture.
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl;
    if (url == null || url.isEmpty) return fallback;

    // Defensive: our server always answers with a relative API path, but an
    // absolute URL elsewhere (a CDN, a mirrored asset) is not ours to fetch
    // through the API client.
    if (url.startsWith('http') && !url.contains('/api/v1/')) {
      return _tile(NetworkImage(url));
    }

    ApiClient? api;
    try {
      api = context.read<ApiClient>();
    } catch (_) {
      // No ApiClient in scope (widget tests, previews) — show the glyph rather
      // than throw on a lookup that is only ever an optimisation.
      return fallback;
    }

    final blur = blurHashProviderFor(url);
    return ApiImageAvatar(
      // A fresh upload answers with a new `?v=` token, so the changed URL is a
      // new key: the state is rebuilt and the new picture fetched, with no app
      // restart and without the old one lingering.
      key: ValueKey(url),
      path: url,
      api: api,
      placeholder: blur == null ? fallback : _tile(blur),
      builder: (image) => image == null ? fallback : _tile(image),
    );
  }

  /// The picture, clipped to the glyph's rounded square and cropped to fill it.
  Widget _tile(ImageProvider image) => SizedBox(
    width: size,
    height: size,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image(
        // Decode at (roughly) the on-screen pixel size, not the 512px the
        // server stores: these sit in dense grids and picker lists where the
        // full-resolution decode would cost real texture memory per row. 3x
        // covers the densest screens; ResizeImage clamps when the source is
        // already smaller.
        image: ResizeImage(
          image,
          width: (size * 3).round(),
          height: (size * 3).round(),
        ),
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    ),
  );
}
