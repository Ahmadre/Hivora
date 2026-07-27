import 'dart:ui';

import 'package:flutter/widgets.dart' show basicLocaleListResolution;
import 'package:hydrated_bloc/hydrated_bloc.dart';

import '../i18n/i18n.dart';

/// Persisted locale selection (hydrated across restarts).
///
/// On the very first launch there is nothing persisted yet, so the cubit seeds
/// itself with the language the OS / browser prefers ([PlatformDispatcher.locales],
/// which maps to the device languages on native and `navigator.languages` on the
/// web). Once the user makes an explicit choice in Settings that choice is
/// persisted and wins on every later launch (HydratedCubit restores it over this
/// seed).
///
/// We deliberately keep the effective locale in this cubit — rather than letting
/// [MaterialApp] resolve it from the device via a [localeResolutionCallback] —
/// because it is the single source of truth for both the UI language *and* the
/// API client's `Accept-Language` header, and it must honour the user's persisted
/// choice. Passing a non-null `locale:` to [MaterialApp] makes Flutter resolve
/// against that value alone (the device locales never reach the callbacks), so
/// the detection has to happen here. We run it through [basicLocaleListResolution]
/// — Flutter's own algorithm, the one those callbacks fall back to — so device
/// languages are matched exactly as the framework would (script/region aware,
/// falling back to the first supported locale).
class LocaleCubit extends HydratedCubit<Locale> {
  LocaleCubit() : super(deviceLocale());

  /// Best match of the user's preferred device/browser languages against the
  /// ones we ship translations for, via Flutter's own resolution algorithm.
  static Locale deviceLocale() => basicLocaleListResolution(
    PlatformDispatcher.instance.locales,
    I18n.supportedLocales,
  );

  void setLocale(String code) => emit(Locale(code));

  @override
  Locale? fromJson(Map<String, dynamic> json) =>
      json['code'] is String ? Locale(json['code'] as String) : null;

  @override
  Map<String, dynamic>? toJson(Locale state) => {'code': state.languageCode};
}
