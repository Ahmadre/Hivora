import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'app_colors.dart';

// Glass presets for the app's floating chrome.
//
// They live in core rather than beside their first user because more than one
// surface has to refract identically to read as the same material — the mobile
// nav is two separate floating elements (the tab pill and the detached search
// button) and the page headers add a third. Values mirror the package's
// `kBottomBarGlassDefaults`.
//
// Everything below shares one optical profile and differs only in [glassColor]:
// the tint is the whole design, and splitting the optics would make two pieces
// of the same chrome look like two materials.

/// The optics every chrome preset here is built on.
const _thickness = 30.0;
const _blur = 3.0;
const _chromaticAberration = 0.3;
const _lightIntensity = 0.6;
const _refractiveIndex = 1.59;
const _saturation = 0.7;
const _ambientStrength = 1.0;

/// 0.75π — the Apple key-light angle the whole app is lit from.
const _lightAngle = 2.356194490192345;

/// Neutral chrome: translucent black in dark (so it doesn't turn milky) and
/// translucent white in light (clean frost).
const kNavGlassDark = LiquidGlassSettings(
  thickness: _thickness,
  blur: _blur,
  chromaticAberration: _chromaticAberration,
  lightIntensity: _lightIntensity,
  refractiveIndex: _refractiveIndex,
  saturation: _saturation,
  ambientStrength: _ambientStrength,
  lightAngle: _lightAngle,
  glassColor: Color(0x4D0A0A0A),
);
const kNavGlassLight = LiquidGlassSettings(
  thickness: _thickness,
  blur: _blur,
  chromaticAberration: _chromaticAberration,
  lightIntensity: _lightIntensity,
  refractiveIndex: _refractiveIndex,
  saturation: _saturation,
  ambientStrength: _ambientStrength,
  lightAngle: _lightAngle,
  glassColor: Color(0x3DFFFFFF),
);

/// The frost that sits *on top of* the amber ground of a primary action.
///
/// It does **not** inherit the chrome optics above, and the reason is the whole
/// point of this preset. Neutral chrome desaturates what it refracts
/// (`saturation: 0.7`) and lays a white veil over it, which is right for a
/// surface whose job is to disappear. Over amber it is exactly wrong: the
/// colour *is* the design, and 30% of it taken away plus a white wash leaves
/// the beige button that shipped in 10.3.2. So: saturation left at 1, and the
/// veil in amber rather than white — a white one dilutes the ground instead of
/// sitting in it.
///
/// **The veil is much heavier over a dark page, and that is not a taste call.**
/// Measured on the running app: the button is only ~64% opaque, so a third of
/// whatever is behind it comes through. Over the light canvas that is free
/// brightness; over the dark one it drags the honey down to 0.72 value where
/// light reads 0.82, which is the "washed out" everyone sees and nobody can
/// name. Brightening the ground cannot fix it — the arithmetic asks for a red
/// channel of 295. What fixes it is making the third that comes through *amber
/// too*, which is this alpha. It lands at RGB(208,154,51) against light's
/// (209,156,54).
LiquidGlassSettings amberFrost(bool dark) => LiquidGlassSettings(
  thickness: _thickness,
  blur: _blur,
  chromaticAberration: _chromaticAberration,
  // The specular rim is a *white* stroke drawn on the shape's outer path with
  // BlendMode.overlay: lightIntensity sets its width, ambientStrength its
  // opacity. What it does depends entirely on what is behind the edge, so the
  // two themes want opposite things from it.
  //
  // Dark: half the rim falls outside the disc, onto a near-black page, where
  // white over dark blooms. It stops being a highlight and becomes a grey reif
  // — measured at saturation 0.14 against a face at 0.75 — that eats the edge
  // and reads as an inner shadow. Narrow and faint is the only way it stays a
  // highlight.
  //
  // Light: the page behind that same edge is nearly as bright as the rim, so
  // there is nothing to bloom against and the full-strength version is what
  // gives the disc its lit edge. Take it away and the button looks unfinished.
  lightIntensity: dark ? 0.45 : 0.9,
  refractiveIndex: _refractiveIndex,
  // Left at 1. Turning it up to claw back what the veil costs looked right in
  // light and blew out in dark — the specular has more headroom to spend over a
  // dark page, and red and green clipped at 255 into a glowing yellow disc with
  // the glyph lost in it.
  saturation: 1,
  ambientStrength: dark ? 0.3 : _ambientStrength,
  lightAngle: _lightAngle,
  glassColor: dark ? const Color(0x59FFBC3B) : const Color(0x1FD9A032),
);

/// The honey-amber ground a primary action's glass floats on. Same three stops
/// as the composer's send button, so the app's two amber circles are one thing.
const kAmberGround = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFE7B24A), AppColors.accent, AppColors.accentStrong],
);

/// The same ground, lifted for a dark page.
///
/// Measured, not eyeballed: the glass renders the identical ground about 22%
/// darker over a dark page than over a light one — the same hue at the same
/// saturation, every channel multiplied by roughly 0.78. Light does not need
/// the lift; dark does, or the primary action sits there dimmer than the page
/// expects it to be.
///
/// These are the light stops with **value raised 20% and saturation left
/// alone** — not paler ambers, which is the obvious way to brighten a colour
/// and the wrong one. The first attempt walked the gradient up to lighter
/// honeys and lost a tenth of the saturation doing it, because a lighter amber
/// simply is a less saturated one. Brightness and saturation are separate axes
/// and only one of them was the problem.
const kAmberGroundDark = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFFFC452), Color(0xFFFFBC3B), Color(0xFFDE9D25)],
);

LinearGradient amberGround(bool dark) => dark ? kAmberGroundDark : kAmberGround;

/// The ink that sits on amber — the same near-black the solid accent button
/// uses for its label, so the glyph reads identically whichever form the button
/// is in.
const kOnAmber = Color(0xFF2A2410);

LiquidGlassSettings navGlass(bool dark) =>
    dark ? kNavGlassDark : kNavGlassLight;

/// A round Liquid Glass button, the shape the app's floating chrome is made of.
///
/// The shape is a superellipse with `radius = size / 2` — a perfect circle — and
/// deliberately not the package's `LiquidOval`. An oval glass surface is clipped
/// with `ClipPath`, which the engine cannot forward to the descendant
/// `BackdropFilter`, so the blur stays a rectangle behind the circle and its
/// vertical edges leak as faint seams beside the button. `ClipRRect`, which the
/// superellipse uses, forwards the clip and kills the halo.
///
/// Pinned to [GlassQuality.standard]: the lightweight shader renders correctly
/// over a scrolling page and on rotation, where the premium pipeline does not.
class GlassCircleButton extends StatelessWidget {
  const GlassCircleButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 46,
    this.iconSize = 20,
    this.amber = false,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;

  /// Honey-amber tint, for a primary action. Neutral chrome otherwise.
  final bool amber;

  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.brightness == Brightness.dark;
    Widget button = GlassButton(
      icon: Icon(icon, size: iconSize),
      onTap: onTap ?? () {},
      enabled: onTap != null,
      width: size,
      height: size,
      iconSize: iconSize,
      shape: LiquidRoundedSuperellipse(borderRadius: size / 2),
      useOwnLayer: true,
      quality: GlassQuality.standard,
      settings: amber ? amberFrost(dark) : navGlass(dark),
      iconColor: amber
          ? kOnAmber
          : (dark ? AppColors.inkDark : AppColors.inkLight),
      glowColor: AppColors.accent,
      // Keep the tactile press-scale but damp the liquid drag-follow so an
      // isolated button doesn't over-stretch on tap.
      stretch: 0.15,
      // A pressed GlassButton lays a flat white sheet over its whole surface —
      // 0.3 opaque in light, 0.14 in dark. On neutral chrome that is the iOS 26
      // lift and it is right. On amber it is a bleach: at 0.3 the honey button
      // turns beige for as long as the finger is down, which is what shipped in
      // 10.3.2 and what a screenshot taken mid-tap shows. An explicit value is
      // used unchanged in both themes, so this is one number: enough lift to
      // answer the touch, not enough to take the colour with it. The press
      // scale and the glow carry the rest of the feedback.
      ambientBaseLight: amber ? 0.10 : null,
    );
    if (amber) {
      button = Stack(
        alignment: Alignment.center,
        children: [
          // The ground the glass refracts. IgnorePointer so the glass keeps the
          // whole gesture — the ground is paint, not a target.
          IgnorePointer(
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: amberGround(dark),
                boxShadow: [
                  BoxShadow(
                    // An amber halo around an amber disc reads as a soft edge,
                    // and over a dark page it is the only thing near it with
                    // any light in it — so it spreads and the button loses its
                    // outline. Over a light page the same glow is invisible.
                    // Hence: barely there in dark, unchanged in light.
                    color: AppColors.accent.withValues(
                      alpha: dark ? 0.16 : 0.45,
                    ),
                    blurRadius: dark ? 9 : 14,
                    spreadRadius: -5,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
            ),
          ),
          button,
        ],
      );
    }
    final label = tooltip;
    return label == null ? button : Tooltip(message: label, child: button);
  }
}
