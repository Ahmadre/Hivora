/// The reported bug, on a device with a real keyboard.
///
/// The widget test beside this one fakes `View.viewInsets`, which is enough to
/// pin the rule. This runs the same interaction against the software keyboard
/// itself, because the bug *is* the keyboard: entering format mode from a cold
/// start raises one, and the dock used to read its own keyboard as somebody
/// else's and unmount itself mid-flight.
///
/// Run it on a simulator with the software keyboard on:
///   defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false
///   flutter test integration_test/comment_composer_keyboard_test.dart -d `<id>`
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:hinata/features/issues/comments/composer_keyboard_gate.dart';
import 'package:hinata/features/issues/comments/glass_comment_composer.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('format mode survives the keyboard it raises itself', (
    tester,
  ) async {
    final controller = TextEditingController();
    final fieldFocus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(fieldFocus.dispose);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Column(
            children: [
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
      ),
    );
    await tester.pumpAndSettle();

    // Cold start: nothing focused, no keyboard.
    expect(fieldFocus.hasFocus, isFalse);

    await tester.tap(find.byIcon(LucideIcons.plus));
    await tester.pumpAndSettle();
    await tester.tap(find.text('comments.actionFormat'));
    await tester.pumpAndSettle();

    // Give the real keyboard time to come up and the metrics to land.
    var keyboard = 0.0;
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      keyboard = tester.view.viewInsets.bottom;
      if (keyboard > 0) break;
    }

    expect(
      keyboard,
      greaterThan(0),
      reason:
          'the editor should have raised the software keyboard — with the '
          'hardware keyboard connected the simulator raises none and this '
          'test cannot see the bug at all',
    );
    expect(
      find.byType(GlassCommentComposer),
      findsOneWidget,
      reason: 'the dock must not evict itself over its own keyboard',
    );
  });
}
