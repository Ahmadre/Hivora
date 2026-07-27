import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config/runtime_config.dart';
import '../repositories/meta_repository.dart';
import '../models/core_models.dart';
import '../models/server_profile.dart';
import '../storage/app_storage.dart';

/// Connection lifecycle: pick server -> verify -> (setup) -> ready.
/// Also enforces the server's minimum app version on every start.
sealed class AppConfigEvent extends Equatable {
  const AppConfigEvent();

  @override
  List<Object?> get props => [];
}

class AppConfigStarted extends AppConfigEvent {
  const AppConfigStarted();
}

class ServerUrlSubmitted extends AppConfigEvent {
  const ServerUrlSubmitted(this.url);

  final String url;

  @override
  List<Object?> get props => [url];
}

class SetupFinished extends AppConfigEvent {
  const SetupFinished();
}

enum AppConfigStatus {
  initial,
  connecting,
  needsServerUrl,
  needsSetup,
  updateRequired,
  ready,
}

class AppConfigState extends Equatable {
  const AppConfigState({
    this.status = AppConfigStatus.initial,
    this.meta,
    this.appVersion = '1.0.0',
    this.errorKey,
  });

  final AppConfigStatus status;
  final ServerMeta? meta;
  final String appVersion;
  final String? errorKey;

  AppConfigState copyWith({
    AppConfigStatus? status,
    ServerMeta? meta,
    String? appVersion,
    String? errorKey,
  }) => AppConfigState(
    status: status ?? this.status,
    meta: meta ?? this.meta,
    appVersion: appVersion ?? this.appVersion,
    errorKey: errorKey,
  );

  @override
  List<Object?> get props => [status, meta, appVersion, errorKey];
}

class AppConfigBloc extends Bloc<AppConfigEvent, AppConfigState> {
  AppConfigBloc({required this.repository, required this.storage})
    : super(const AppConfigState()) {
    on<AppConfigStarted>(_onStarted, transformer: restartable());
    on<ServerUrlSubmitted>(_onServerUrlSubmitted, transformer: droppable());
    on<SetupFinished>(_onSetupFinished);
  }

  final MetaRepository repository;
  final AppStorage storage;

  /// The default server URL that actually applies on this platform.
  ///
  /// No-baked-backend rule: the shipped image/app bakes **no** backend. The hosted
  /// web build resolves its default at *runtime* from `window.hinataDefaultServer`
  /// (injected by `config.js`, which the Docker entrypoint regenerates from the
  /// `HINATA_DEFAULT_SERVER` container env) — so the operator sets the backend
  /// purely at deployment, not at build time. Empty ⇒ show /connect.
  ///
  /// The native store apps (iOS/Android/macOS) must **never** pin a backend, so
  /// we additionally gate to the web build here as defense-in-depth: even if a
  /// native platform ever exposed a value, a fresh install still asks for the
  /// server URL on first launch.
  static String get _effectiveDefaultServer =>
      kIsWeb ? runtimeDefaultServer : '';

  Future<void> _onStarted(
    AppConfigStarted event,
    Emitter<AppConfigState> emit,
  ) async {
    final info = await PackageInfo.fromPlatform();
    final version = info.version;
    if (storage.serverUrl == null) {
      if (_effectiveDefaultServer.isEmpty) {
        emit(
          state.copyWith(
            status: AppConfigStatus.needsServerUrl,
            appVersion: version,
          ),
        );
        return;
      }
      await storage.setServerUrl(_effectiveDefaultServer);
    }
    emit(
      state.copyWith(status: AppConfigStatus.connecting, appVersion: version),
    );
    await _verify(emit);
  }

  Future<void> _onServerUrlSubmitted(
    ServerUrlSubmitted event,
    Emitter<AppConfigState> emit,
  ) async {
    var url = event.url.trim();
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !(uri.isScheme('https') || uri.isScheme('http')) ||
        uri.host.isEmpty) {
      emit(state.copyWith(errorKey: 'connect.invalidUrl'));
      return;
    }
    emit(state.copyWith(status: AppConfigStatus.connecting));
    await storage.setServerUrl(url);
    await _verify(emit);
  }

  Future<void> _onSetupFinished(
    SetupFinished event,
    Emitter<AppConfigState> emit,
  ) async {
    await _verify(emit);
  }

  Future<void> _verify(Emitter<AppConfigState> emit) async {
    try {
      final meta = await repository.meta();
      // Remember a friendly label for this server (its organization name) so the
      // multi-server switcher can show "Acme" rather than a bare host.
      final url = storage.serverUrl;
      if (url != null) {
        await storage.upsertServer(
          ServerProfile(url: url, label: meta.organizationName),
        );
      }
      if (isVersionBelow(state.appVersion, meta.minAppVersion)) {
        emit(
          state.copyWith(status: AppConfigStatus.updateRequired, meta: meta),
        );
      } else if (!meta.setupCompleted) {
        emit(state.copyWith(status: AppConfigStatus.needsSetup, meta: meta));
      } else {
        emit(state.copyWith(status: AppConfigStatus.ready, meta: meta));
      }
    } catch (_) {
      emit(
        state.copyWith(
          status: AppConfigStatus.needsServerUrl,
          errorKey: 'connect.failed',
        ),
      );
    }
  }
}
