import 'package:flutter/material.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart' show BlurHashImage;

import '../theme/app_colors.dart';

/// The BlurHash an avatar URL carries, as an [ImageProvider], or null.
///
/// A person's picture is addressed by a URL that already travels in every
/// response mentioning them — the directory, a board card, a search hit — so
/// the server appends the hash to that URL as `bh=…` instead of adding a field
/// to a dozen DTOs and threading it through every widget that draws a circle.
/// See `AvatarService.withBlurHash` on the server side.
ImageProvider<Object>? blurHashProviderFor(String url) {
  final hash = Uri.tryParse(url)?.queryParameters['bh'];
  if (hash == null || hash.isEmpty) return null;
  return BlurHashImage(hash);
}

/// An image that is never an empty box while it loads.
///
/// Three layers, each taking over from the one below as it becomes available:
///
/// 1. **BlurHash** — a ~30 character string that travels inside the JSON
///    describing the picture, so a blurred version of the *actual* image is
///    painted in the first frame, before a single image byte is requested.
/// 2. **[image]** — the real picture (a thumbnail in a grid, the original in a
///    viewer), faded in over the blur once its first frame decodes.
/// 3. **[fallback]** — what a picture-less tile shows (a file-type glyph, an
///    empty surface); also what remains when there is no hash and no image.
///
/// A decode failure at any layer leaves the one below it visible instead of
/// throwing: a broken image degrades to its blur, a broken hash to [fallback].
///
/// The widget fills its parent, so give it bounded constraints (an
/// [AspectRatio], a [SizedBox], a sized [Stack] cell). It never introduces
/// intrinsic size of its own and therefore cannot overflow its parent.
class HivePreviewImage extends StatelessWidget {
  const HivePreviewImage({
    super.key,
    this.image,
    this.blurHash,
    this.fit = BoxFit.cover,
    this.fallback,
    this.fadeDuration = const Duration(milliseconds: 240),
  });

  /// The real picture. Null while there is nothing to show but the placeholder.
  final ImageProvider? image;

  /// BlurHash of the same picture, or null when the server has none for it.
  final String? blurHash;

  /// How both the blur and the image fill the box. The blur always covers —
  /// a letterboxed blur reads as a rendering bug rather than a placeholder.
  final BoxFit fit;

  /// Drawn beneath everything, for pictures with no hash (and non-pictures).
  final Widget? fallback;

  final Duration fadeDuration;

  @override
  Widget build(BuildContext context) {
    final hash = blurHash;
    final provider = image;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (fallback != null)
          fallback!
        else
          ColoredBox(color: AppColors.canvas2),
        if (hash != null && hash.isNotEmpty)
          Image(
            image: BlurHashImage(hash),
            fit: BoxFit.cover,
            // Nothing to show on a malformed hash — the fallback below stays.
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        if (provider != null)
          Image(
            image: provider,
            fit: fit,
            // Keeps the previous frame while a new provider resolves, so
            // swapping thumbnail → original never flashes the blur again.
            gaplessPlayback: true,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded) return child;
              return AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: fadeDuration,
                curve: Curves.easeOut,
                child: child,
              );
            },
            // A failed load leaves the blur (or the fallback) on screen, which
            // is a far better answer than a broken-image glyph.
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
      ],
    );
  }
}
