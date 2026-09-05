import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../api/api_client.dart';
import '../theme/app_colors.dart';
import 'preview_image.dart' show FadeInOver, blurHashProviderFor;
import 'user_pronouns.dart';

/// Process-wide cache of fetched avatar bytes, keyed by the (cache-busted)
/// avatar URL. `null` marks a URL that failed / 404'd so we don't refetch it on
/// every rebuild. Because avatar URLs carry a `?v=` token that changes on each
/// upload, a new picture is always a new key (no stale image).
///
/// A plain map literal is a `LinkedHashMap`, so key order is insertion order and
/// `keys.first` is the oldest entry — that lets [_avatarCachePut] evict LRU.
final Map<String, Uint8List?> _avatarBytesCache = {};
final Map<String, Future<void>> _avatarInFlight = {};

/// Soft cap on the *bytes* retained in [_avatarBytesCache]. Avatars themselves
/// are tiny, but this same cache also backs attachment image thumbnails —
/// whole-file bytes, multi-MB each — so without a bound it would grow for the
/// app's entire lifetime (an accumulating leak). Least-recently-used entries
/// are evicted once the cap is exceeded.
const int _kAvatarCacheMaxBytes = 32 * 1024 * 1024;
int _avatarCacheBytes = 0;

/// Stores [bytes] for [path] as most-recently-used, then evicts the oldest
/// entries until the cache is back under [_kAvatarCacheMaxBytes].
void _avatarCachePut(String path, Uint8List? bytes) {
  final prev = _avatarBytesCache.remove(path);
  if (prev != null) _avatarCacheBytes -= prev.lengthInBytes;
  _avatarBytesCache[path] = bytes;
  if (bytes != null) _avatarCacheBytes += bytes.lengthInBytes;
  while (_avatarCacheBytes > _kAvatarCacheMaxBytes &&
      _avatarBytesCache.length > 1) {
    final oldest = _avatarBytesCache.keys.first;
    if (oldest == path) break; // never evict the entry we just stored
    final removed = _avatarBytesCache.remove(oldest);
    if (removed != null) _avatarCacheBytes -= removed.lengthInBytes;
  }
}

/// Circular avatar with deterministic pastel background and initials fallback.
///
/// Server avatar URLs are loaded through the authenticated [ApiClient] (XHR) and
/// rendered from bytes via [Image.memory] — *not* [NetworkImage]. This is the
/// same approach the org-logo uses and it is what makes avatars actually show
/// on Flutter **web**: a cross-origin `<img>` drawn by CanvasKit taints the
/// canvas without CORS headers and silently fails, whereas decoded bytes render
/// everywhere. It also transparently carries the bearer token + the
/// ngrok-skip header, so it works behind auth and tunnels too.
class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.radius = 18,
    this.pronouns,
  });

  final String name;
  final String? imageUrl;
  final double radius;

  /// The person's pronouns, shown on hover as "Name · they/them". See
  /// [HiveAvatar.pronouns] for when to pass this and when to leave it null.
  final String? pronouns;

  @override
  Widget build(BuildContext context) {
    final said = normalizePronouns(pronouns);
    if (said == null) return _avatar(context);
    return Tooltip(
      message: personTooltip(name: name, pronouns: said)!,
      waitDuration: const Duration(milliseconds: 400),
      child: _avatar(context),
    );
  }

  Widget _avatar(BuildContext context) {
    final url = imageUrl;
    if (url == null || url.isEmpty) return _circle(null);

    // External absolute images (not our API) keep the plain network path.
    if (url.startsWith('http') && !url.contains('/api/v1/users/')) {
      return _circle(NetworkImage(url));
    }

    ApiClient? api;
    try {
      api = context.read<ApiClient>();
    } catch (_) {
      // No ApiClient in scope (e.g. widget tests) — show initials.
      return _circle(null);
    }
    return ApiImageAvatar(
      key: ValueKey(url),
      path: url,
      api: api,
      placeholder: _circle(blurHashProviderFor(url)),
      builder: _circle,
    );
  }

  Widget _circle(ImageProvider? image) => CircleAvatar(
    radius: radius,
    backgroundColor: AppColors.pastelFor(name.hashCode.abs()),
    // Decode at (roughly) the on-screen pixel size, not the source's full
    // resolution: a 512px upload rendered in a 28-36px circle otherwise
    // wastes decode time and GPU texture memory — costly in avatar-dense
    // lists (member strips, notifications, boards). 3x covers the densest
    // screens; ResizeImage is a no-op when the source is already smaller.
    foregroundImage: image == null
        ? null
        : ResizeImage(
            image,
            width: (radius * 2 * 3).round(),
            height: (radius * 2 * 3).round(),
          ),
    child: Text(
      _initials(name),
      style: TextStyle(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w700,
        fontSize: radius * 0.8,
      ),
    ),
  );

  String _initials(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }
}

/// Loads avatar bytes for [path] (relative to the API base) once, caches them,
/// and renders them with [Image.memory]; shows [placeholder] while loading or
/// on failure.
class ApiImageAvatar extends StatefulWidget {
  const ApiImageAvatar({
    super.key,
    required this.path,
    required this.api,
    required this.placeholder,
    required this.builder,
  });

  final String path;
  final ApiClient api;
  final Widget placeholder;
  final Widget Function(ImageProvider? image) builder;

  @override
  State<ApiImageAvatar> createState() => ApiImageAvatarState();
}

class ApiImageAvatarState extends State<ApiImageAvatar> {
  Uint8List? _bytes;

  /// Whether the picture was already there on the first build.
  ///
  /// A cached avatar is not "arriving", it is simply present, and fading it in
  /// on every rebuild would make scrolling a list of people flicker.
  bool _immediate = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final path = widget.path;
    if (_avatarBytesCache.containsKey(path)) {
      final cached = _avatarBytesCache[path];
      // Bump recency so an image that's still on screen isn't the first thing
      // evicted when the cache is under memory pressure.
      if (cached != null) _avatarCachePut(path, cached);
      _bytes = cached;
      _immediate = true;
      return;
    }
    // Coalesce concurrent loads of the same URL (e.g. avatar shown twice).
    final pending = _avatarInFlight[path] ??= _fetch(path);
    await pending;
    if (mounted) setState(() => _bytes = _avatarBytesCache[path]);
  }

  Future<void> _fetch(String path) async {
    try {
      final result = await widget.api.getBytes(path);
      _avatarCachePut(
        path,
        result == null ? null : Uint8List.fromList(result.bytes),
      );
    } catch (_) {
      _avatarCachePut(path, null);
    } finally {
      _avatarInFlight.remove(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) return widget.placeholder;
    final image = widget.builder(MemoryImage(bytes));
    if (_immediate) return image;
    // The picture arrived just now: fade it in over whatever stood in for it —
    // the BlurHash, or the initials. The decode of the resized image costs a
    // frame or two after this, and lands while the new layer is still at a few
    // percent opacity, so it is not visible as a step.
    return FadeInOver(under: widget.placeholder, child: image);
  }
}

/// Overlapping avatar stack like the member group in the design header.
class AvatarStack extends StatelessWidget {
  const AvatarStack({
    super.key,
    required this.names,
    this.max = 3,
    this.radius = 14,
  });

  final List<String> names;
  final int max;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final visible = names.take(max).toList();
    final overflow = names.length - visible.length;
    return SizedBox(
      height: radius * 2,
      width: visible.isEmpty
          ? 0
          : radius * 2 +
                (visible.length - 1 + (overflow > 0 ? 1 : 0)) * radius * 1.2,
      child: Stack(
        children: [
          for (var i = 0; i < visible.length; i++)
            Positioned(
              left: i * radius * 1.2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: AppAvatar(name: visible[i], radius: radius),
              ),
            ),
          if (overflow > 0)
            Positioned(
              left: visible.length * radius * 1.2,
              child: CircleAvatar(
                radius: radius,
                backgroundColor: AppColors.navy,
                child: Text(
                  '+$overflow',
                  style: TextStyle(color: Colors.white, fontSize: radius * 0.7),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
