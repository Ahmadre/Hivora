import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../blocs/app_config_bloc.dart';
import 'org_logo_store.dart';

/// The organization's logo where the product's own mark used to be — the rail
/// header, the sign-in hero, the admin console, the consent card.
///
/// ### Why the API is shaped like this
///
/// There is deliberately **no `size`** and **no `color`**.
///
/// [HexMark], the mark this replaces, is a square [CustomPaint] taking one
/// `size`. An organization's logo is neither: it is a raster or vector of
/// whatever aspect ratio its designer chose, commonly a 6:1 wordmark. Offering a
/// square `size` here would reproduce, at every call site, exactly the bug this
/// widget exists to avoid — so the geometry is stated as a fixed [height] and a
/// hard [maxWidth], and the picture is fitted inside it. The box owns the
/// layout; the image never does.
///
/// A `color` would be worse. Twelve of the app's [HexMark] call sites tint the
/// mark to sit on their ground — and a tint is meaningless on a logo that
/// arrives with its own colours. Surfaces that genuinely need a tinted glyph
/// (watermarks, empty states, 18px list glyphs) therefore keep [HexMark]; that
/// is a decision, not an omission.
///
/// ### Behaviour
///
/// [fallback] is returned **verbatim** whenever there is no logo — not
/// configured, not loaded yet, failed, or no [OrgLogoStore] in scope (widget
/// tests, previews). So a surface adopting this never changes shape on an
/// instance without a logo, and the mark is never a reason for a blank frame or
/// a spinner. When the logo does arrive it cross-fades in, which is why the
/// fallback has to be the same size the logo will be.
class OrgLogo extends StatelessWidget {
  const OrgLogo({
    super.key,
    required this.height,
    required this.maxWidth,
    required this.fallback,
    this.alignment = Alignment.centerLeft,
    this.semanticLabel,
  });

  /// The one fixed dimension. The logo is scaled to it and centred in [maxWidth].
  final double height;

  /// Hard cap on the width a wide wordmark may claim.
  final double maxWidth;

  /// Shown until (and unless) a logo is available. Usually a `HexMark`.
  final Widget fallback;

  /// How the picture sits inside its box when it is narrower than [maxWidth].
  final Alignment alignment;

  /// Read out instead of the picture; defaults to the organization's name.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    OrgLogoStore? store;
    try {
      store = context.watch<OrgLogoStore>();
    } catch (_) {
      // Nothing branded to show and nothing to fetch with — the plain mark is
      // the correct answer, not an exception on a lookup that is decoration.
      return fallback;
    }

    final meta = context.select<AppConfigBloc, ({String? logo, String? name})>(
      (bloc) => (logo: bloc.state.meta?.logoUrl, name: bloc.state.meta?.organizationName),
    );
    // Idempotent and cheap; the store ignores a key it already has or is
    // already fetching, so calling it from build is the simplest correct place.
    store.ensure(meta.logo);

    final state = store.state;
    final picture = _picture(state, meta.name);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      // Both branches carry a key, and they differ. Without that, AnimatedSwitcher
      // cannot tell the outgoing child from the incoming one and drops the
      // fallback the moment the logo arrives — which is a visible collapse to
      // zero width and back in the middle of the chrome.
      child: picture == null
          ? KeyedSubtree(key: const ValueKey('org-logo-fallback'), child: fallback)
          : SizedBox(
              key: const ValueKey('org-logo-picture'),
              height: height,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: FittedBox(
                  fit: BoxFit.contain,
                  alignment: alignment,
                  child: picture,
                ),
              ),
            ),
    );
  }

  Widget? _picture(OrgLogoState state, String? organizationName) {
    final label = semanticLabel ?? organizationName;
    final svg = state.svg;
    if (svg != null) {
      return SvgPicture.string(
        svg,
        height: height,
        fit: BoxFit.contain,
        semanticsLabel: label,
        // A logo that fails to parse must read as "no logo", not as an error
        // box in the middle of the chrome.
        placeholderBuilder: (_) => const SizedBox.shrink(),
      );
    }
    final image = state.image;
    if (image == null) return null;
    return Image(
      image: image,
      height: height,
      fit: BoxFit.contain,
      semanticLabel: label,
      // Both failure paths collapse to nothing so the AnimatedSwitcher keeps
      // showing the fallback rather than swapping it for a broken box.
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
      gaplessPlayback: true,
    );
  }
}

/// The name to put in front of a user where the product used to be named: the
/// organization this instance belongs to, falling back to the product.
///
/// Not every surface can show a picture — a 12px palette footer, a sentence, a
/// PDF's metadata — and on those the *name* carries the same identity the logo
/// does elsewhere. Returns `'Hinata'` on an instance that has not been set up
/// (or in a widget test with no [AppConfigBloc] in scope), which is the right
/// answer there rather than an empty string.
String orgOrProductName(BuildContext context) {
  try {
    final name = context
        .select<AppConfigBloc, String?>((b) => b.state.meta?.organizationName)
        ?.trim();
    return (name == null || name.isEmpty) ? 'Hinata' : name;
  } catch (_) {
    return 'Hinata';
  }
}
