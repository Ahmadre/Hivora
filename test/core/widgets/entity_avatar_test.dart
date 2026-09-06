import 'package:flutter/material.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart' show BlurHashImage;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/team_models.dart';
import 'package:hinata/core/widgets/entity_avatar.dart';
import 'package:hinata/core/widgets/entity_avatar_editor.dart';
import 'package:hinata/features/teams/team_widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Teams and projects can carry a picture (HIN-32), and the way it reaches the
/// screen is that their *existing* glyphs learned about it — so every list,
/// card and picker picked it up at once. The contract these tests hold down is
/// that the glyph is unchanged whenever there is no picture to show, including
/// the awkward cases: an entity that has a URL but no reachable API client, and
/// a fetch that fails.
void main() {
  /// A distinct URL per test: the avatar byte cache is process-wide, so two
  /// tests sharing a URL would share its (possibly failed) result.
  var seq = 0;
  String url({String? blurHash}) {
    seq++;
    final bh = blurHash == null
        ? ''
        : '&bh=${Uri.encodeQueryComponent(blurHash)}';
    return '/api/v1/teams/t$seq/avatar?v=$seq$bh';
  }

  Widget host(Widget child, {ApiClient? api}) {
    final body = Center(child: child);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: api == null
            ? body
            : RepositoryProvider<ApiClient>.value(value: api, child: body),
      ),
    );
  }

  const glyphKey = Key('glyph');
  const glyph = SizedBox(key: glyphKey, width: 44, height: 44);

  Finder imageOf<T extends ImageProvider>() => find.byWidgetPredicate(
    (w) =>
        w is Image &&
        w.image is ResizeImage &&
        (w.image as ResizeImage).imageProvider is T,
  );

  group('EntityAvatar', () {
    testWidgets('without a URL it is exactly the glyph', (tester) async {
      await tester.pumpWidget(
        host(
          const EntityAvatar(
            avatarUrl: null,
            size: 44,
            radius: 13,
            fallback: glyph,
          ),
        ),
      );

      expect(find.byKey(glyphKey), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('an empty URL is treated as no picture', (tester) async {
      await tester.pumpWidget(
        host(
          const EntityAvatar(
            avatarUrl: '',
            size: 44,
            radius: 13,
            fallback: glyph,
          ),
        ),
      );

      expect(find.byKey(glyphKey), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    /// An authenticated picture cannot be fetched without the API client, and a
    /// missing provider must never be an exception — widget tests and previews
    /// build these glyphs outside the app's provider tree all the time.
    testWidgets('falls back to the glyph when no ApiClient is in scope', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          EntityAvatar(avatarUrl: url(), size: 44, radius: 13, fallback: glyph),
        ),
      );

      expect(find.byKey(glyphKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the BlurHash the URL carries while loading', (
      tester,
    ) async {
      // The canonical example hash from blurha.sh.
      final path = url(blurHash: 'LEHV6nWB2yk8pyo0adR*.7kCMdnj');
      await tester.pumpWidget(
        host(
          EntityAvatar(avatarUrl: path, size: 44, radius: 13, fallback: glyph),
          api: _StubApiClient(),
        ),
      );
      await tester.pump();

      expect(imageOf<BlurHashImage>(), findsOneWidget);
      expect(find.byKey(glyphKey), findsNothing);
    });

    /// No `bh=` means there is nothing to blur, so the glyph — not an empty
    /// square — stands in until the bytes land.
    testWidgets('without a BlurHash the glyph stands in while loading', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          EntityAvatar(avatarUrl: url(), size: 44, radius: 13, fallback: glyph),
          api: _StubApiClient(),
        ),
      );
      await tester.pump();

      expect(find.byKey(glyphKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failed fetch ends on the glyph, not a hole', (tester) async {
      await tester.pumpWidget(
        host(
          EntityAvatar(avatarUrl: url(), size: 44, radius: 13, fallback: glyph),
          api: _StubApiClient(),
        ),
      );
      // Two pumps: one for the failed fetch to resolve, one for the rebuild.
      await tester.pump();
      await tester.pump();

      expect(find.byKey(glyphKey), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });
  });

  group('TeamGlyph', () {
    Team team({String? avatarUrl}) => Team.fromJson({
      'id': 't1',
      'key': 'CORE',
      'name': 'Core Platform',
      'icon': 'rocket',
      'colorHue': 250,
      'avatarUrl': ?avatarUrl,
    });

    testWidgets('is the tinted icon square when there is no picture', (
      tester,
    ) async {
      await tester.pumpWidget(host(TeamGlyph(team: team())));

      expect(find.byIcon(LucideIcons.rocket), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      // Same footprint as before: nothing downstream has to re-measure.
      expect(tester.getSize(find.byType(TeamGlyph)), const Size(44, 44));
    });

    testWidgets('keeps the icon when the picture cannot be fetched', (
      tester,
    ) async {
      await tester.pumpWidget(host(TeamGlyph(team: team(avatarUrl: url()))));

      expect(find.byIcon(LucideIcons.rocket), findsOneWidget);
      expect(tester.getSize(find.byType(TeamGlyph)), const Size(44, 44));
    });

    testWidgets('honours an explicit size', (tester) async {
      await tester.pumpWidget(
        host(TeamGlyph(team: team(), size: 56, radius: 16)),
      );

      expect(tester.getSize(find.byType(TeamGlyph)), const Size(56, 56));
    });
  });

  group('ProjectKeyGlyph', () {
    testWidgets('is the mono key square when there is no picture', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const ProjectKeyGlyph(label: 'HIN', color: Colors.indigo)),
      );

      expect(find.text('HIN'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(tester.getSize(find.byType(ProjectKeyGlyph)), const Size(36, 36));
    });

    testWidgets('keeps the key when the picture cannot be fetched', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          ProjectKeyGlyph(label: 'HIN', color: Colors.indigo, avatarUrl: url()),
        ),
      );

      expect(find.text('HIN'), findsOneWidget);
      expect(tester.getSize(find.byType(ProjectKeyGlyph)), const Size(36, 36));
    });
  });

  /// The picture fields frame their fallback, so a fallback must not size or
  /// offset itself. This is the contract the project create dialog broke: its
  /// glyph carried a 22-pixel top margin from an older layout, the field's
  /// 52×52 box absorbed it, and every new project's picture tile shipped as a
  /// 52×30 pill. Asserting the *constraints* rather than the rendered size is
  /// what catches it — with the margin, the outer box still measured 52×52 and
  /// only the painted interior was short.
  group('a fallback is framed by the field, not by itself', () {
    testWidgets('PendingAvatarField hands its fallback a tight square', (
      tester,
    ) async {
      late BoxConstraints given;
      await tester.pumpWidget(
        host(
          PendingAvatarField(
            picked: null,
            size: 52,
            radius: 15,
            strings: EntityAvatarStrings.project,
            onPicked: (_) {},
            fallback: LayoutBuilder(
              builder: (_, constraints) {
                given = constraints;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(given, BoxConstraints.tight(const Size(52, 52)));
    });

  });
}

/// An API client whose image fetches always come back empty — enough to drive
/// [EntityAvatar] through "loading" and "failed" without any network.
class _StubApiClient implements ApiClient {
  @override
  Future<({List<int> bytes, String contentType})?> getBytes(
    String path,
  ) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
