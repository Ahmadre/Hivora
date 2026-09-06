/// The docked comment composer and the keyboard it is allowed to sit above.
///
/// The dock hides itself while the keyboard belongs to another field in the
/// sheet — a sub-task, a linked issue, the inline title edit — because Wolt
/// lifts the sticky bar for any focused field and the composer has no business
/// riding above a keyboard it did not raise.
///
/// The rule is right; what it asked was wrong. It asked the single-line field's
/// [FocusNode], and format mode swaps that field out for the rich editor. So the
/// editor's own keyboard read as somebody else's, and the dock unmounted itself
/// the instant that keyboard arrived — the editor flashed up and vanished. From
/// a cold start (nothing focused) that is the entire interaction: `+` → "Text
/// formatting".
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/features/issues/comments/composer_keyboard_gate.dart';
import 'package:hinata/features/issues/comments/glass_comment_composer.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  late TextEditingController controller;
  late FocusNode fieldFocus;
  late FocusNode strangerFocus;

  setUp(() {
    controller = TextEditingController();
    fieldFocus = FocusNode();
    strangerFocus = FocusNode();
  });

  tearDown(() {
    controller.dispose();
    fieldFocus.dispose();
    strangerFocus.dispose();
  });

  /// A phone, which is where the dock hides from keyboards at all — a desktop
  /// has no software keyboard and never trips the rule.
  void phone(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
  }

  /// The sheet: some other field, and the composer in its bottom dock.
  Widget host() => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: Column(
        children: [
          // Stands in for the sub-task / linked-issue / title inputs.
          TextField(focusNode: strangerFocus),
          const Spacer(),
          ComposerKeyboardGate(
            child: GlassCommentComposer(
              controller: controller,
              focusNode: fieldFocus,
              onSubmitText: (_) {},
              onSendVoice: (_) {},
              onAttach: (_) {},
            ),
          ),
        ],
      ),
    ),
  );

  /// Raises or lowers the software keyboard for the whole view, which is where
  /// the gate reads it from — a `MediaQuery` would not do, the sheet's Scaffold
  /// strips the bottom inset out of that subtree.
  void keyboard(WidgetTester tester, {required bool up}) {
    tester.view.viewInsets = up
        ? const FakeViewPadding(bottom: 336)
        : FakeViewPadding.zero;
    addTearDown(tester.view.reset);
  }

  final composer = find.byType(GlassCommentComposer);
  final plusButton = find.byIcon(LucideIcons.plus);

  /// `+` → "Text formatting". The label renders as its key here: a widget test
  /// mounts no translations.
  Future<void> openFormatting(WidgetTester tester) async {
    await tester.tap(plusButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('comments.actionFormat'));
    await tester.pumpAndSettle();
  }

  testWidgets('a keyboard the composer did not raise takes the dock away', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(host());

    strangerFocus.requestFocus();
    keyboard(tester, up: true);
    await tester.pumpAndSettle();

    expect(composer, findsNothing);
  });

  testWidgets('the dock comes back when that keyboard goes down', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(host());
    strangerFocus.requestFocus();
    keyboard(tester, up: true);
    await tester.pumpAndSettle();

    strangerFocus.unfocus();
    keyboard(tester, up: false);
    await tester.pumpAndSettle();

    expect(composer, findsOneWidget);
  });

  testWidgets('the composer keeps the keyboard its own field raised', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(host());

    fieldFocus.requestFocus();
    keyboard(tester, up: true);
    await tester.pumpAndSettle();

    expect(composer, findsOneWidget);
  });

  // The reported bug, in the order it was reported: nothing focused, keyboard
  // down, straight into formatting from the "+" menu.
  testWidgets('formatting opened from a cold start survives its own keyboard', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(host());
    expect(fieldFocus.hasFocus, isFalse, reason: 'cold start: nothing focused');

    await openFormatting(tester);
    // The editor asks for focus a frame later, and the keyboard follows it.
    keyboard(tester, up: true);
    await tester.pumpAndSettle();

    expect(
      composer,
      findsOneWidget,
      reason: 'the editor raised this keyboard; the dock must not evict itself',
    );
    // The single-line field is gone in format mode — which is exactly why
    // asking *it* whether the keyboard is ours gave the wrong answer.
    expect(fieldFocus.hasFocus, isFalse);
  });

  testWidgets('and formatting opened from a warm start survives too', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(host());
    fieldFocus.requestFocus();
    keyboard(tester, up: true);
    await tester.pumpAndSettle();

    await openFormatting(tester);
    await tester.pumpAndSettle();

    expect(composer, findsOneWidget);
  });
}
