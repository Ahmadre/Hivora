import 'package:flutter/foundation.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// The device-capability scope every glass surface in the app renders under.
///
/// Without a scope like this, each `quality: GlassQuality.premium` in the app
/// takes the full two-BackdropFilter + fragment-shader pipeline on every device,
/// ungated — including the software renderers and broken shader drivers where it
/// crashes. `GlassThemeHelpers.resolveQuality` caps *every* quality against this
/// scope, an explicit widget-level one included ("premium" means "premium if the
/// device can take it"), so what is configured here is what the app can reach.
///
/// **Premium is allowed, and earned.** The package decides per device, in three
/// phases, and each one is a thing this config used to do worse by hand:
///
///  1. a static probe forces [GlassQuality.minimal] on software renderers and
///     broken shader drivers, and caps the web at standard — the crash cases,
///     handled before a frame is drawn;
///  2. a warm-up benchmark over the first ~180 frames measures P75 raster time
///     and settles the device: under 20 ms it earns premium, 20–28 ms standard,
///     above that minimal;
///  3. runtime hysteresis degrades after 3 bad windows and recovers only after
///     10 good ones with an 8-second cooldown — deliberately 3× faster to fall
///     than to climb, so a device that cannot hold premium drops once and stays
///     down rather than oscillating.
///
/// This used to say `maxQuality: standard`, which was too blunt. It was set out
/// of a worry about oscillation that phase 3's asymmetry already answers, and it
/// cost every capable device the quality it had measurably earned.
///
/// [GlassAdaptiveScopeConfig.initialQuality] is deliberately **not** set: it
/// overrides the benchmark and skips phase 2 entirely, which is how the cap
/// above ended up deciding on hardware it had never measured. Left null, the
/// package seeds the safe cold-start quality itself — premium on Apple, standard
/// on Android, where a premium frame 1 on a GLES-only device is the ANR risk —
/// and then measures.
// ignore: experimental_member_use
const GlassAdaptiveScopeConfig kGlassCeiling = GlassAdaptiveScopeConfig(
  maxQuality: GlassQuality.premium,
  minQuality: GlassQuality.minimal,
  allowStepUp: true,
  targetFrameMs: 16,
  onQualityChanged: _logQualityChange,
);

/// Says out loud what tier a device settled on, in debug builds only.
///
/// The whole design above is a decision made on the device, at runtime, that is
/// otherwise invisible — the first question anyone asks about it is "so what did
/// *my* phone get?", and until now nothing answered.
void _logQualityChange(GlassQuality from, GlassQuality to) {
  if (kDebugMode) debugPrint('[glass] quality ${from.name} → ${to.name}');
}
