import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/blocs/app_config_bloc.dart';
import 'package:hinata/core/branding/org_logo.dart';
import 'package:hinata/core/branding/org_logo_store.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/repositories/meta_repository.dart';
import 'package:hinata/core/storage/app_storage.dart';

/// The organization logo replaces the Hinata mark across the app's chrome
/// (HIN-59). Two properties make that safe to do in a dozen places, and both are
/// invisible until they break, so they are pinned here:
///
///  * **one fetch, however many surfaces** — the logo is chrome, so it is on
///    screen many times at once, and on native there is no HTTP cache to save
///    us;
///  * **the fallback is returned verbatim** — an instance with no logo, a failed
///    fetch, and a widget test with nothing wired must all render exactly what
///    the surface rendered before this feature existed.
void main() {
  const fallbackKey = Key('fallback-mark');
  const fallback = SizedBox(key: fallbackKey, width: 26, height: 26);

  /// A 1x1 transparent PNG — the smallest thing that is really an image.
  final pngBytes = Uint8List.fromList(const [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
    0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
    0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ]);

  /// An 8:1 PNG — the shape that breaks every slot sized for a square signet.
  final wideWordmarkBytes = _pngOf(800, 100);

  const svgSource =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
      '<rect width="10" height="10" fill="#0af"/></svg>';

  ServerMeta meta({String? organizationName, String? logoUrl}) => ServerMeta(
    serverVersion: '1',
    minAppVersion: '1',
    setupCompleted: true,
    organizationName: organizationName,
    logoUrl: logoUrl,
  );

  group('OrgLogoStore', () {
    test('does nothing at all when no logo is configured', () async {
      final repo = _FakeMetaRepository();
      final store = OrgLogoStore(meta: repo, api: _StubApiClient());
      addTearDown(store.close);

      store.ensure(null);
      store.ensure('   ');
      await pumpEventQueue();

      expect(repo.calls, 0);
      expect(store.state.hasLogo, isFalse);
    });

    test('fetches once however many surfaces ask for the same logo', () async {
      final repo = _FakeMetaRepository(bytes: pngBytes);
      final store = OrgLogoStore(meta: repo, api: _StubApiClient());
      addTearDown(store.close);

      // Ten surfaces mounting in one frame, before any of them has completed.
      for (var i = 0; i < 10; i++) {
        store.ensure('/api/v1/meta/logo?v=1');
      }
      repo.releaseAll();
      await pumpEventQueue();

      expect(repo.calls, 1);
      expect(store.state.image, isNotNull);

      // And an eleventh arriving after the fact does not fetch again.
      store.ensure('/api/v1/meta/logo?v=1');
      await pumpEventQueue();
      expect(repo.calls, 1);
    });

    test('re-fetches when the logo changes, keyed per server', () async {
      final repo = _FakeMetaRepository(bytes: pngBytes);
      final api = _StubApiClient();
      final store = OrgLogoStore(meta: repo, api: api);
      addTearDown(store.close);

      store.ensure('/api/v1/meta/logo?v=1');
      repo.releaseAll();
      await pumpEventQueue();

      // A re-upload answers with a new token — a new key, so new bytes.
      store.ensure('/api/v1/meta/logo?v=2');
      repo.releaseAll();
      await pumpEventQueue();
      expect(repo.calls, 2);

      // The same relative path on a *different* server is a different logo.
      // Without the server in the key the previous organization's mark would
      // survive the switch, which is a branding leak, not a stale cache.
      api.baseUrlValue = 'https://other.example';
      store.ensure('/api/v1/meta/logo?v=2');
      repo.releaseAll();
      await pumpEventQueue();
      expect(repo.calls, 3);
    });

    test('drops the mark when switching to a server without a logo', () async {
      final repo = _FakeMetaRepository(bytes: pngBytes);
      final store = OrgLogoStore(meta: repo, api: _StubApiClient());
      addTearDown(store.close);

      store.ensure('/api/v1/meta/logo?v=1');
      repo.releaseAll();
      await pumpEventQueue();
      expect(store.state.hasLogo, isTrue);

      store.ensure(null);
      await pumpEventQueue();
      expect(store.state.hasLogo, isFalse);
    });

    test('keeps an SVG payload as source rather than as bytes', () async {
      final repo = _FakeMetaRepository(
        bytes: Uint8List.fromList(svgSource.codeUnits),
        isSvg: true,
      );
      final store = OrgLogoStore(meta: repo, api: _StubApiClient());
      addTearDown(store.close);

      store.ensure('https://example.com/logo.svg');
      repo.releaseAll();
      await pumpEventQueue();

      expect(store.state.svg, contains('<svg'));
      expect(store.state.image, isNull);
    });

    test('ignores an oversized payload instead of decoding it', () async {
      final repo = _FakeMetaRepository(
        bytes: Uint8List(OrgLogoStore.maxBytes + 1),
      );
      final store = OrgLogoStore(meta: repo, api: _StubApiClient());
      addTearDown(store.close);

      store.ensure('https://hostile.example/logo.png');
      repo.releaseAll();
      await pumpEventQueue();

      expect(store.state.hasLogo, isFalse);
      // The key is still recorded, so it is not retried on every rebuild.
      expect(store.state.key, isNotNull);
    });

    test('survives a throwing repository', () async {
      final repo = _FakeMetaRepository(throws: true);
      final store = OrgLogoStore(meta: repo, api: _StubApiClient());
      addTearDown(store.close);

      store.ensure('https://unreachable.example/logo.png');
      repo.releaseAll();
      await pumpEventQueue();

      expect(store.state.hasLogo, isFalse);
    });
  });

  group('OrgLogo', () {
    /// Mounts [child] over a store and a config bloc, and hands both back so the
    /// test can drive them.
    Future<_Harness> mount(
      WidgetTester tester, {
      required ServerMeta serverMeta,
      _FakeMetaRepository? repository,
      Widget child = const OrgLogo(
        height: 26,
        maxWidth: 92,
        fallback: fallback,
      ),
    }) async {
      final repo = repository ?? _FakeMetaRepository();
      final store = OrgLogoStore(meta: repo, api: _StubApiClient());
      final config = _StubAppConfig(serverMeta);
      addTearDown(() {
        store.close();
        config.close();
      });
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<OrgLogoStore>.value(value: store),
            BlocProvider<AppConfigBloc>.value(value: config),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Align(alignment: Alignment.topLeft, child: child),
            ),
          ),
        ),
      );
      return _Harness(repo, store);
    }

    testWidgets('renders the fallback verbatim with no store in scope', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: OrgLogo(height: 26, maxWidth: 180, fallback: fallback),
        ),
      );

      expect(find.byKey(fallbackKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders the fallback while nothing is configured', (
      tester,
    ) async {
      final harness = await mount(tester, serverMeta: meta());
      await tester.pump();

      expect(find.byKey(fallbackKey), findsOneWidget);
      expect(harness.repository.calls, 0);
    });

    testWidgets('swaps in the logo, bounded by the box it was given', (
      tester,
    ) async {
      final harness = await mount(
        tester,
        serverMeta: meta(
          organizationName: 'AStA der Hochschule Niederrhein',
          logoUrl: '/api/v1/meta/logo?v=1',
        ),
        repository: _FakeMetaRepository(bytes: pngBytes),
      );
      await tester.pump();
      harness.repository.releaseAll();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(Image), findsOneWidget);
      // The box owns the geometry, not the picture: an arbitrary aspect ratio
      // must not be able to push past what the call site allowed.
      final box = tester.widget<ConstrainedBox>(
        find
            .ancestor(
              of: find.byType(FittedBox),
              matching: find.byType(ConstrainedBox),
            )
            .first,
      );
      expect(box.constraints.maxWidth, 92);
      final sized = tester.widget<SizedBox>(
        find
            .ancestor(
              of: find.byType(FittedBox),
              matching: find.byType(SizedBox),
            )
            .first,
      );
      expect(sized.height, 26);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failed fetch ends on the fallback, not a hole', (
      tester,
    ) async {
      final harness = await mount(
        tester,
        serverMeta: meta(logoUrl: '/api/v1/meta/logo?v=1'),
        repository: _FakeMetaRepository(throws: true),
      );
      await tester.pump();
      harness.repository.releaseAll();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(fallbackKey), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
    });

    /// The compact app bar is the tightest slot the logo lands in: `GlassAppBar`
    /// lays its leading out with loose constraints and then centres the title in
    /// `width - 2 * max(leading, actions)`. A logo that ignored its bound would
    /// therefore take from the title twice over, and shove it off its own centre,
    /// on the narrowest phone we support.
    testWidgets('a wide wordmark stays inside its bound on a 320px phone', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = await mount(
        tester,
        serverMeta: meta(logoUrl: '/api/v1/meta/logo?v=1'),
        repository: _FakeMetaRepository(bytes: wideWordmarkBytes),
        // The compact app bar's own numbers.
        child: const OrgLogo(height: 24, maxWidth: 72, fallback: fallback),
      );
      await tester.pump();
      harness.repository.releaseAll();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final rendered = tester.getSize(find.byType(FittedBox).first);
      expect(rendered.width, lessThanOrEqualTo(72));
      expect(rendered.height, lessThanOrEqualTo(24));
      expect(tester.takeException(), isNull);
    });

    testWidgets('takes the vector path for an SVG logo', (tester) async {
      final harness = await mount(
        tester,
        serverMeta: meta(logoUrl: 'https://example.com/logo.svg'),
        repository: _FakeMetaRepository(
          bytes: Uint8List.fromList(svgSource.codeUnits),
          isSvg: true,
        ),
      );
      await tester.pump();
      harness.repository.releaseAll();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(harness.store.state.svg, isNotNull);
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('orgOrProductName', () {
    Future<String> nameFor(WidgetTester tester, ServerMeta serverMeta) async {
      late String seen;
      final config = _StubAppConfig(serverMeta);
      // Discard the future rather than returning it: an awaited tear-down inside
      // testWidgets' fake-async zone waits on a clock that nothing is advancing
      // any more, and the test hangs until its ten-minute timeout.
      addTearDown(() {
        config.close();
      });
      await tester.pumpWidget(
        BlocProvider<AppConfigBloc>.value(
          value: config,
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                seen = orgOrProductName(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      return seen;
    }

    testWidgets('prefers the organization', (tester) async {
      expect(await nameFor(tester, meta(organizationName: 'AStA')), 'AStA');
    });

    testWidgets('falls back to the product on a blank name', (tester) async {
      expect(await nameFor(tester, meta(organizationName: '   ')), 'Hinata');
    });

    testWidgets('answers with the product when nothing is wired', (
      tester,
    ) async {
      late String seen;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              seen = orgOrProductName(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(seen, 'Hinata');
    });
  });
}

/// A flat opaque [w]x[h] PNG, encoded by hand.
///
/// Built rather than fixtured because the size is the point: the bound this
/// guards is only exercised by a picture whose aspect ratio would overflow the
/// slot if the box did not own the geometry, and a checked-in asset would hide
/// that number from the test that depends on it.
Uint8List _pngOf(int w, int h) {
  final raw = BytesBuilder();
  for (var y = 0; y < h; y++) {
    raw.addByte(0); // filter: none
    for (var x = 0; x < w; x++) {
      raw.add(const [0x23, 0x22, 0x3F, 0xFF]); // opaque ink
    }
  }
  final png = BytesBuilder()
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

  void chunk(String type, List<int> data) {
    png.add(_be32(data.length));
    final body = <int>[...type.codeUnits, ...data];
    png.add(body);
    png.add(_be32(_crc32(body)));
  }

  chunk('IHDR', [
    ..._be32(w), ..._be32(h),
    8, // bit depth
    6, // colour type: RGBA
    0, 0, 0,
  ]);
  chunk('IDAT', ZLibEncoder().convert(raw.takeBytes()));
  chunk('IEND', const []);
  return Uint8List.fromList(png.takeBytes());
}

List<int> _be32(int v) => [
  (v >> 24) & 0xFF,
  (v >> 16) & 0xFF,
  (v >> 8) & 0xFF,
  v & 0xFF,
];

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}

class _Harness {
  _Harness(this.repository, this.store);

  final _FakeMetaRepository repository;
  final OrgLogoStore store;
}

/// Counts calls and hands control of *when* each one completes to the test, so
/// "ten surfaces mounted before any fetch finished" is a real race rather than a
/// sequence that happens to work.
class _FakeMetaRepository implements MetaRepository {
  _FakeMetaRepository({this.bytes, this.isSvg = false, this.throws = false});

  final Uint8List? bytes;
  final bool isSvg;
  final bool throws;

  int calls = 0;
  final List<Completer<void>> _gates = [];

  @override
  Future<({List<int> bytes, bool isSvg})?> organizationLogo({
    int? cacheBust,
  }) async {
    calls++;
    final gate = Completer<void>();
    _gates.add(gate);
    await gate.future;
    if (throws) throw StateError('unreachable');
    if (bytes == null) return null;
    return (bytes: bytes!, isSvg: isSvg);
  }

  /// Releases every pending fetch.
  ///
  /// Deliberately synchronous: inside `testWidgets` the clock is fake, so
  /// awaiting a `Future.delayed` here would hang forever. The caller decides how
  /// to let the continuations run — `pumpEventQueue()` in a plain test,
  /// `tester.pump()` in a widget test.
  void releaseAll() {
    for (final gate in _gates) {
      if (!gate.isCompleted) gate.complete();
    }
    _gates.clear();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _StubApiClient implements ApiClient {
  String baseUrlValue = 'https://track.example';

  @override
  String get baseUrl => baseUrlValue;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

/// An [AppConfigBloc] that is only ever asked for its state.
class _StubAppConfig extends AppConfigBloc {
  _StubAppConfig(ServerMeta meta)
    : super(repository: _FakeMetaRepository(), storage: _UnusedStorage()) {
    emit(AppConfigState(status: AppConfigStatus.ready, meta: meta));
  }
}

/// Never touched: the stub emits its state directly and dispatches no event.
class _UnusedStorage implements AppStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
