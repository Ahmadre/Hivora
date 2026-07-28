import 'package:flutter/material.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

/// Persisted theme-mode selection (hydrated across restarts).
/// Defaults to [ThemeMode.system] so the app follows the OS light/dark setting
/// until the user picks an explicit mode in Settings.
class ThemeCubit extends HydratedCubit<ThemeMode> {
  ThemeCubit() : super(ThemeMode.system);

  void setMode(ThemeMode mode) => emit(mode);

  @override
  ThemeMode? fromJson(Map<String, dynamic> json) => switch (json['mode']) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    'system' => ThemeMode.system,
    _ => null,
  };

  @override
  Map<String, dynamic>? toJson(ThemeMode state) => {'mode': state.name};
}
