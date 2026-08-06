import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/features/admin/admin_form_helpers.dart';
import 'package:hinata/features/admin/sections/admin_moderation_section.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// The policy half of the admin **Moderation** section: the two cards that
/// point the server at its out-of-process tiers.
///
/// Two properties are worth a test and neither is visible by reading the form.
///
/// The first is that it fits. These are the widest labels in the panel, every
/// one of them is a translation, and German runs longer than English — while
/// this section is reachable on a phone. Widget tests render i18n *keys*, which
/// are longer again than either language, so a layout that survives here has
/// margin over both; nothing below asserts on label text or on a pixel width,
/// only that no width produces an exception.
///
/// The second is that the secret is never shown. The server declares it
/// `WRITE_ONLY` and does not echo it, and the panel PUTs a blank field as
/// "keep what is stored" — so a box that pre-filled itself from anywhere would
/// be displaying a value that is not the saved one, and an admin correcting it
/// would silently re-sign every notice with a key the recipient cannot verify.
void main() {
  /// A settings document as the server sends it, with both budgets in the
  /// `Duration` form Jackson writes rather than as numbers.
  Map<String, dynamic> settings({
    String imageEndpoint = 'http://hinata-moderation:8081',
    String escalationUrl = 'https://alerts.example.com/hinata',
    bool secretConfigured = true,
    Map<String, dynamic> extra = const {},
  }) => {
    'moderation': {
      'enabled': true,
      'textEnabled': true,
      'imageEnabled': true,
      'blockThreshold': 85,
      'flagThreshold': 55,
      'longFormFlagOnly': true,
      'failOpen': true,
      'imageEndpoint': imageEndpoint,
      'imageTimeout': 'PT1M',
      'escalationUrl': escalationUrl,
      'escalationTimeout': 'PT5S',
      'escalationMaxAttempts': 3,
      'escalationSecretConfigured': secretConfigured,
      ...extra,
    },
  };

  Widget host(Map<String, dynamic> s, ApiClient api) =>
      RepositoryProvider<ApiClient>.value(
        value: api,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(body: AdminModerationSection(settings: s)),
        ),
      );

  /// Renders at a real window width — the section reads its gutters from the
  /// [MediaQuery], so sizing a `SizedBox` around it would test a layout the app
  /// never produces.
  Future<void> pumpAt(
    WidgetTester tester,
    double width, {
    Map<String, dynamic>? draft,
    ApiClient? api,
  }) async {
    tester.view
      ..physicalSize = Size(width, 1400)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(draft ?? settings(), api ?? _StubApi()));
    // Settles the summary read and the two (empty) queue pages without
    // pumpAndSettle, which never returns while the queue's loader is on screen.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('layout', () {
    // 280 is narrower than any phone ships, and deliberately: the panel has
    // already lost a row here once, to two buttons and a Spacer with no flex.
    for (final width in <double>[280, 320, 390, 600, 900]) {
      testWidgets('lays out at ${width}px with no overflow', (tester) async {
        await pumpAt(tester, width);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('lays out at 280px with the fields empty, as a fresh install '
        'sees them', (tester) async {
      // The state the classifier card exists for: the tier reports itself
      // unconfigured and there is nothing in the box to explain why.
      await pumpAt(
        tester,
        280,
        draft: settings(
          imageEndpoint: '',
          escalationUrl: '',
          secretConfigured: false,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byIcon(LucideIcons.scanEye), findsOneWidget);
    });
  });

  group('structure', () {
    testWidgets('shows both cards, each under the line it answers', (
      tester,
    ) async {
      await pumpAt(tester, 390);

      // The classifier card sits under the tier status line, and the webhook
      // card under the locked categories whose hits are what fire it. Asserted
      // by vertical order rather than by label, which is a key here.
      final tierNotice = tester
          .getTopLeft(find.byIcon(LucideIcons.triangleAlert).first)
          .dy;
      final classifier = tester.getTopLeft(find.byIcon(LucideIcons.scanEye)).dy;
      final locked = tester.getTopLeft(find.byIcon(LucideIcons.lock).first).dy;
      final escalation = tester.getTopLeft(find.byIcon(LucideIcons.siren)).dy;

      expect(classifier, greaterThan(tierNotice));
      expect(escalation, greaterThan(locked));
    });

    testWidgets('renders every settable field and no more', (tester) async {
      await pumpAt(tester, 390);

      // endpoint, webhook url, secret
      expect(find.byType(AdminField), findsNWidgets(3));
      // both thresholds, both timeouts, the attempt budget
      expect(find.byType(AdminNumberField), findsNWidgets(5));
    });

    testWidgets('shows a budget the server sent as a Duration, not a default', (
      tester,
    ) async {
      await pumpAt(tester, 390);

      // `PT1M` is what Java writes for a 60-second timeout. Read off the field
      // rather than through the parser, which has its own test: the failure
      // this guards is the panel showing its 5-second default and an admin
      // saving that over a minute they set deliberately.
      final fields = tester
          .widgetList<EditableText>(find.byType(EditableText))
          .map((e) => e.controller.text)
          .toList();
      expect(fields, contains('60'));
    });
  });

  group('the write-only secret', () {
    /// The value the server would never send. Seeded anyway, because the test
    /// has to fail if the field ever starts binding to the map like its
    /// neighbours do — that is the one-line change this guards against.
    const stored = 'a-real-hmac-signing-key-nobody-should-see';

    testWidgets('never displays a stored value', (tester) async {
      await pumpAt(
        tester,
        390,
        draft: settings(extra: const {'escalationSecret': stored}),
      );

      expect(find.textContaining(stored), findsNothing);

      final secrets = tester
          .widgetList<EditableText>(find.byType(EditableText))
          .where((e) => e.obscureText)
          .toList();
      expect(secrets, hasLength(1));
      expect(secrets.single.controller.text, isEmpty);
    });

    testWidgets('left untouched, sends nothing that could overwrite it', (
      tester,
    ) async {
      final draft = settings();
      await pumpAt(tester, 390, draft: draft);

      final moderation = draft['moderation']! as Map<String, dynamic>;
      // Not `''`: the server keeps the stored secret when the key is blank OR
      // absent, but writing an empty string here would also mean this panel
      // decides the value on every save of an unrelated setting.
      expect(moderation.containsKey('escalationSecret'), isFalse);
    });

    // Blank-with-one-stored and blank-with-none look identical in the input
    // itself, so the row beside it is the only thing that tells them apart.
    // Split in two so a regression names which direction broke: the panel
    // claiming a secret it has not got is the dangerous one.
    testWidgets('says so when one is stored', (tester) async {
      await pumpAt(tester, 390);
      expect(find.byIcon(LucideIcons.circleCheck), findsOneWidget);
      expect(find.byIcon(LucideIcons.circleAlert), findsNothing);
    });

    testWidgets('says so when none is', (tester) async {
      await pumpAt(tester, 390, draft: settings(secretConfigured: false));
      expect(find.byIcon(LucideIcons.circleCheck), findsNothing);
      expect(find.byIcon(LucideIcons.circleAlert), findsOneWidget);
    });
  });

  group('the draft it hands to the save bar', () {
    testWidgets('writes an endpoint straight through', (tester) async {
      final draft = settings();
      await pumpAt(tester, 390, draft: draft);

      await tester.enterText(
        find.byType(TextFormField).first,
        'http://nsfw:9000',
      );
      await tester.pump();

      expect(
        (draft['moderation']! as Map<String, dynamic>)['imageEndpoint'],
        'http://nsfw:9000',
      );
    });

    testWidgets('writes a timeout back as the Duration the binder parses', (
      tester,
    ) async {
      final draft = settings();
      await pumpAt(tester, 390, draft: draft);

      // The first number field on screen is the image budget — its card sits
      // above the thresholds. Entered as seconds, saved as ISO-8601: a bare
      // `12` binds to `Duration` as a rejected value, not as twelve seconds.
      await tester.enterText(find.byType(AdminNumberField).first, '12');
      await tester.pump();

      expect(
        (draft['moderation']! as Map<String, dynamic>)['imageTimeout'],
        'PT12S',
      );
    });
  });
}

/// An API that answers the two reads the section makes on open — the tier
/// summary and an empty page for each queue — so the policy form is exercised
/// without a network and without the queue below it throwing first.
///
/// The tier answers `NOT_CONFIGURED` because that is the state the two cards
/// were built for — a server that is running, is told to classify images, and
/// has nowhere to send them.
class _StubApi implements ApiClient {
  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    if (path.endsWith('/summary')) {
      return {
        'openRecords': 0,
        'openReports': 0,
        'open': 0,
        'imageTier': 'NOT_CONFIGURED',
      };
    }
    return {'items': const [], 'total': 0, 'page': 0, 'size': 25};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
