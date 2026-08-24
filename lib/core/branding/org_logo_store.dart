import 'dart:async';
import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../api/api_client.dart';
import '../repositories/meta_repository.dart';

/// What is known about the organization's logo right now.
///
/// [image] and [svg] are mutually exclusive and both null until a logo has been
/// fetched successfully — every consumer treats "nothing yet" and "no logo"
/// identically, which is what makes the loading path and the fallback path the
/// same code, and keeps a logo from ever blocking first paint.
class OrgLogoState extends Equatable {
  const OrgLogoState({this.key, this.image, this.svg});

  /// `<server base url>|<logoUrl>` of whatever produced [image] / [svg], or
  /// null when no logo is configured.
  ///
  /// Scoped to the server and not just the URL, because the app is
  /// multi-server: keying on the URL alone would keep showing the previous
  /// organization's mark after a switch, since every instance answers at the
  /// same relative `/api/v1/meta/logo` path.
  final String? key;

  /// The decoded logo for raster payloads, ready to hand to an [Image].
  final ImageProvider? image;

  /// The raw SVG source for vector payloads (an external URL can be one).
  final String? svg;

  bool get hasLogo => image != null || svg != null;

  @override
  List<Object?> get props => [key, image, svg];
}

/// The single source of truth for the organization's logo bytes.
///
/// Every surface that shows the mark goes through here rather than fetching for
/// itself, for three reasons that only get worse as the logo spreads:
///
///  * **One request.** On native there is no HTTP cache in front of dio, so N
///    surfaces rendering the logo would mean N downloads. Concurrent callers
///    share one in-flight future; later ones get the cached result.
///  * **One decode.** A fresh `Uint8List` per fetch is a *new* [MemoryImage] as
///    far as Flutter's [ImageCache] is concerned — its identity is the buffer —
///    so re-fetching would fill the cache with duplicates of one picture. One
///    buffer here means one cache entry everywhere.
///  * **One failure mode.** The bytes come from a server the *user* typed in,
///    which may answer with anything at all. Deciding once what is renderable,
///    and capping what is accepted, keeps that judgement out of 20 call sites.
///
/// Fetching always goes through [MetaRepository.organizationLogo], i.e. the
/// server-side `/api/v1/meta/logo` proxy, and never through `meta.logoUrl`
/// directly: for an upload that value is a relative path with no host, and for
/// an external URL it is cross-origin — which the API's
/// `Cross-Origin-Resource-Policy: same-origin` would block for a plain
/// `Image.network` on web.
class OrgLogoStore extends Cubit<OrgLogoState> {
  OrgLogoStore({required MetaRepository meta, required ApiClient api})
    : _meta = meta,
      _api = api,
      super(const OrgLogoState());

  final MetaRepository _meta;
  final ApiClient _api;

  /// Height the logo is decoded at. Generous for a retina hero lockup, small
  /// enough that a careless 4000px upload does not sit in the image cache at
  /// full resolution on a phone.
  static const int decodeHeight = 512;

  /// Width bound, sized from the widest call site (the sign-in hero draws at
  /// most 190 logical px, so ~570 at 3x) with room to spare.
  ///
  /// Bounding the height alone is not enough: a wordmark is wide and short, so a
  /// 5000x400 source passes a height-only cap untouched and decodes at 5000px —
  /// 8 MB of pixels for a mark that is painted 190 px wide.
  static const int decodeWidth = 1024;

  /// A logo is branding, not a payload. Refusing oversized bytes here rather
  /// than at the decoder keeps a hostile or merely careless instance from
  /// parking megabytes in the image cache.
  static const int maxBytes = 4 * 1024 * 1024;

  /// The key of the newest requested logo — the only one whose result may be
  /// emitted. It is also what makes this single-flight: a second [ensure] for a
  /// key that is already wanted returns without starting a second fetch.
  String? _wanted;

  /// Ensures the logo for [logoUrl] on the current server is loaded.
  ///
  /// Idempotent and cheap, and it never emits synchronously, so it is safe to
  /// call from `build` — which is the only place that reliably knows the
  /// current server's meta.
  void ensure(String? logoUrl) {
    final key = _keyFor(logoUrl);
    if (key == null) {
      _wanted = null;
      // Server switched to an instance without a logo: drop the old one rather
      // than leave another organization's mark in the chrome.
      if (state.key != null || state.hasLogo) _emitLater(const OrgLogoState());
      return;
    }
    if (key == _wanted) return;
    _wanted = key;
    _load(key);
  }

  /// Forces a re-fetch of the configured logo.
  ///
  /// Needed after an admin saves: an *uploaded* logo answers with a fresh `?v=`
  /// token so its key changes on its own, but an external URL can change what it
  /// serves without changing its address.
  Future<void> refresh(String? logoUrl) {
    final key = _keyFor(logoUrl);
    _wanted = key;
    if (key == null) {
      _emitLater(const OrgLogoState());
      return Future.value();
    }
    return _load(key, bustCache: true);
  }

  String? _keyFor(String? logoUrl) {
    final url = logoUrl?.trim();
    if (url == null || url.isEmpty) return null;
    return '${_api.baseUrl}|$url';
  }

  Future<void> _load(String key, {bool bustCache = false}) async {
    try {
      final asset = await _meta.organizationLogo(
        cacheBust: bustCache ? DateTime.now().millisecondsSinceEpoch : null,
      );
      if (_wanted != key) return; // a newer request won the race
      if (asset == null) {
        _emitNow(OrgLogoState(key: key));
        return;
      }
      if (asset.bytes.length > maxBytes) {
        if (kDebugMode) {
          debugPrint('[branding] logo is ${asset.bytes.length} bytes — ignored');
        }
        _emitNow(OrgLogoState(key: key));
        return;
      }
      if (asset.isSvg) {
        _emitNow(
          OrgLogoState(key: key, svg: utf8.decode(asset.bytes, allowMalformed: true)),
        );
        return;
      }
      _emitNow(
        OrgLogoState(
          key: key,
          // ResizeImage, not a bare MemoryImage: it has value equality, so the
          // one instance handed to every surface is one ImageCache entry — and
          // it bounds what a 4000px source costs in memory.
          image: ResizeImage(
            MemoryImage(Uint8List.fromList(asset.bytes)),
            width: decodeWidth,
            height: decodeHeight,
            allowUpscaling: false,
            // `fit` with both bounds set: the picture is scaled to sit inside
            // the box, so neither axis can run away with an arbitrary aspect
            // ratio.
            policy: ResizeImagePolicy.fit,
          ),
        ),
      );
    } catch (error) {
      if (kDebugMode) debugPrint('[branding] logo could not be loaded: $error');
      if (_wanted != key) return;
      // Clear the key as well as the bytes. Keeping it would mark this logo as
      // "already handled", so a fetch that failed because the user was in a
      // tunnel — or the server was restarting — would never be tried again for
      // the life of the app. The next `ensure` from any surface retries instead.
      _wanted = null;
      _emitNow(const OrgLogoState());
    }
  }

  void _emitNow(OrgLogoState next) {
    if (!isClosed) emit(next);
  }

  /// Emits after the current synchronous work, so a call from `build` cannot
  /// mark the tree dirty while it is being built.
  void _emitLater(OrgLogoState next) {
    scheduleMicrotask(() {
      if (!isClosed) emit(next);
    });
  }
}
