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
/// A tint cannot make glass amber. `glassColor` colours what the shader
/// refracts, and over the app's near-black canvas an amber tint at any alpha
/// short of opaque comes out as muddy brown with a glyph that disappears into
/// it — measured, not assumed. So the amber is a ground *under* the glass and
/// this is the glass over it: a light, low-alpha frost that keeps the specular
/// highlight and the refraction while letting the colour through.
const kAmberGlassFrost = LiquidGlassSettings(
  thickness: _thickness,
  blur: _blur,
  chromaticAberration: _chromaticAberration,
  lightIntensity: _lightIntensity,
  refractiveIndex: _refractiveIndex,
  saturation: _saturation,
  ambientStrength: _ambientStrength,
  lightAngle: _lightAngle,
  glassColor: Color(0x24FFFFFF),
);

/// The honey-amber ground a primary action's glass floats on. Same three stops
/// as the composer's send button, so the app's two amber circles are one thing.
const kAmberGround = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFE7B24A), AppColors.accent, AppColors.accentStrong],
);

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
      settings: amber ? kAmberGlassFrost : navGlass(dark),
      iconColor: amber
          ? kOnAmber
          : (dark ? AppColors.inkDark : AppColors.inkLight),
      glowColor: AppColors.accent,
      // Keep the tactile press-scale but damp the liquid drag-follow so an
      // isolated button doesn't over-stretch on tap.
      stretch: 0.15,
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
                gradient: kAmberGround,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.45),
                    blurRadius: 14,
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
