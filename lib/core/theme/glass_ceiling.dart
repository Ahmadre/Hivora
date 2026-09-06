import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// The device-capability ceiling every glass surface in the app renders under.
///
/// Without a scope like this, each explicit `quality: GlassQuality.premium` in
/// the app takes the full two-BackdropFilter + fragment-shader pipeline on every
/// device — ungated, and crash-prone on some Mali GPUs. `GlassThemeHelpers`
/// clamps every widget-level `quality:` to this scope's effective quality, so
/// capping here caps everything.
///
/// **The cap is [GlassQuality.standard]**: the lightweight single-pass shader,
/// 5-10× cheaper than premium, universally supported, and the path that does not
/// trigger the shader-related production crashes. The adapter may still step
/// *down* to [GlassQuality.minimal] on weak or headless devices and back up when
/// headroom returns; it can never step up past standard.
///
/// It lives here, in one place, because it did not used to: the root wrap said
/// `maxQuality: premium` while its own comment and the test that guards it both
/// said standard, and the test could not catch the drift because it built its
/// own copy of this config under a "keep in sync" comment. Both now read this.
///
/// Raising the cap to premium is a deliberate act with a measurable cost — the
/// glass package's quality adapter recovers from a degradation after roughly
/// half a minute, so a device that cannot hold premium will oscillate rather
/// than settle.
// ignore: experimental_member_use
const GlassAdaptiveScopeConfig kGlassCeiling = GlassAdaptiveScopeConfig(
  initialQuality: GlassQuality.standard,
  maxQuality: GlassQuality.standard,
  minQuality: GlassQuality.minimal,
  allowStepUp: true,
  targetFrameMs: 16,
);
