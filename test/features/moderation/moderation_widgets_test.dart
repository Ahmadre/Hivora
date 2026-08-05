import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/features/moderation/content_refused_dialog.dart';

/// The refusal dialog is the one screen in the product a person only ever sees
/// at a bad moment, so it has to survive every width and it has to say the
/// server's own reason rather than a generic apology.
///
/// Widget tests here render i18n *keys* rather than translations (the bundles
/// are not loaded in a test binding), so nothing asserts on label text — only on
/// structure and on the one string that is deliberately not a key: the server's
/// statement of reasons, which arrives already localized and is shown verbatim.
void main() {
  const reason =
      'Your content was not saved because it appears to contain hate speech '
      'or a slur. This was an automated check; contact an administrator to '
      'have it reviewed by a person.';

  Widget host(double width, {String message = reason}) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => showContentRefusedDialog(context, message),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );

  group('isContentRefusal', () {
    test('is true for 422 and false for every other status', () {
      expect(isContentRefusal(ApiFailure('x', statusCode: 422)), isTrue);

      for (final status in <int?>[null, 400, 401, 403, 404, 409, 413, 500, 502]) {
        expect(
          isContentRefusal(ApiFailure('x', statusCode: status)),
          isFalse,
          reason: '$status must fall through to the generic error path',
        );
      }
    });
  });

  group('handleContentRefusal', () {
    /// Driven from a tap rather than from `build`: the helper opens a route, and
    /// pushing one during a build is an error in its own right — which would
    /// make the test fail for a reason that has nothing to do with the contract
    /// under test.
    Widget trigger(ApiFailure failure, void Function(bool) record) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => record(handleContentRefusal(context, failure)),
            child: const Text('go'),
          ),
        ),
      ),
    );

    testWidgets('claims a 422 so the caller skips its generic error path', (
      tester,
    ) async {
      bool? handled;
      await tester.pumpWidget(
        trigger(ApiFailure(reason, statusCode: 422), (v) => handled = v),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(handled, isTrue);
      expect(find.textContaining('hate speech'), findsOneWidget);
    });

    testWidgets('leaves an ordinary failure to the caller', (tester) async {
      bool? handled;
      await tester.pumpWidget(
        trigger(ApiFailure('boom', statusCode: 500), (v) => handled = v),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(handled, isFalse);
      // Nothing was shown — a 500 belongs in the caller's toast, not in a policy
      // dialog that would tell someone their content broke a rule when it did not.
      expect(find.textContaining('boom'), findsNothing);
    });
  });

  group('the refusal dialog', () {
    testWidgets('shows the server statement of reasons verbatim', (
      tester,
    ) async {
      await tester.pumpWidget(host(420));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.textContaining('hate speech'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    /// A refusal is not a place to discover a layout bug — it already arrives
    /// when someone is annoyed, and on a phone in a modal over a keyboard.
    for (final width in <double>[280, 320, 390, 600, 900]) {
      testWidgets('lays out without overflow at ${width}px', (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(host(width));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    }

    /// The server bounds its own messages, but a proxy or a transport fallback
    /// can put something much longer in the same field, and a dialog that
    /// overflows on it is a dialog nobody can dismiss.
    testWidgets('survives an unreasonably long reason', (tester) async {
      await tester.pumpWidget(host(320, message: 'Sehr langer Grund. ' * 60));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('survives an empty reason', (tester) async {
      await tester.pumpWidget(host(360, message: ''));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in dark mode too', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showContentRefusedDialog(context, reason),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
