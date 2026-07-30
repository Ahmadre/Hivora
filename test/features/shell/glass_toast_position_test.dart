import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/responsive/responsive.dart';
import 'package:hinata/features/sprint/modals/glass_modal.dart';

/// Where the app-wide toast lands.
///
/// On a phone it belongs at the bottom, in thumb's reach. On a desktop-sized
/// window that same corner is far outside where the user is looking and the
/// toast goes unnoticed — so it moves to the top, below whatever chrome the
/// mounted shell published to [ShellInsets] (nothing, on the shell-less auth
/// screens, where it hugs the top instead).
void main() {
  const phone = Size(390, 844);
  // Just past the compact breakpoint (610): enough to take the wide path, small
  // enough that the glass pill's shader work stays cheap in the test renderer.
  const wide = Size(800, 700);
  const message = 'Gespeichert';

  setUp(ShellInsets.reset);
  // Synchronously, so no deferred publish outlives the test.
  tearDown(ShellInsets.reset);

  /// Pumps a bare app at [size] and shows a toast in it, settled.
  Future<GlassToastController> showToast(
    WidgetTester tester, {
    required Size size,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late BuildContext pageContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            pageContext = context;
            return const SizedBox.expand();
          },
        ),
      ),
    );

    final controller = showGlassToast(pageContext, message);
    // Dismissing it explicitly keeps the auto-dismiss timer from outliving the
    // test.
    addTearDown(controller.close);
    // Past the 220ms entrance animation — never pumpAndSettle: the glass
    // surface keeps scheduling frames, so settling only ends at the timeout.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return controller;
  }

  /// Which edge the toast pinned itself to, read off the `Positioned` that
  /// places it in the overlay. Cheaper and more exact than measuring the pill,
  /// whose offset also carries its own padding.
  Positioned anchorOf(WidgetTester tester) => tester.widget<Positioned>(
    find
        .ancestor(of: find.text(message), matching: find.byType(Positioned))
        .last,
  );

  testWidgets('stays at the bottom on a phone', (tester) async {
    await showToast(tester, size: phone);

    // Rendered, not just laid out: proves the anchor really lands down there.
    final toast = tester.getRect(find.text(message));
    expect(phone.height - toast.bottom, lessThan(60));
    expect(anchorOf(tester).top, isNull);
  });

  testWidgets('rides above the floating nav while the shell shows one', (
    tester,
  ) async {
    // What the compact shell publishes for its nav pill: 80px above the safe
    // area. Pages that hide the nav publish 0 and the toast drops back down.
    ShellInsets.publishBottom(Object(), 80);
    await showToast(tester, size: phone);

    expect(anchorOf(tester).bottom, 80 + 16);
  });

  testWidgets('hugs the top when no shell published any chrome', (
    tester,
  ) async {
    await showToast(tester, size: wide);

    final anchor = anchorOf(tester);
    expect(anchor.bottom, isNull);
    expect(anchor.top, 16); // the plain gutter, nothing to clear
  });

  testWidgets('clears the top chrome the mounted shell published', (
    tester,
  ) async {
    // What the wide shell publishes while it is on screen: its floating top bar
    // reaches 72px below the status-bar inset. Published *before* the toast
    // appears — moving it afterwards would relayout and repaint the glass pill
    // mid-test, which the software renderer takes forever to do.
    ShellInsets.publishTop(Object(), 72);
    await showToast(tester, size: wide);

    expect(anchorOf(tester).top, 72 + 16);
  });

  group('ownership', () {
    // Publishing is deferred to the end of the frame (notifying a listener
    // mid-build throws), so these need a frame to run in.
    Future<void> frame(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }

    testWidgets('the shell going away takes its inset with it', (tester) async {
      final shell = Object();
      ShellInsets.publishTop(shell, 72);
      await frame(tester);
      expect(ShellInsets.top.value, 72);

      ShellInsets.publishBottom(shell, 80);
      await frame(tester);
      expect(ShellInsets.bottom.value, 80);

      ShellInsets.withdraw(shell);
      await frame(tester);
      expect(ShellInsets.top.value, 0);
      expect(ShellInsets.bottom.value, 0);
    });

    testWidgets('a departing shell cannot clear its successor s inset', (
      tester,
    ) async {
      // Crossing the breakpoint builds the incoming shell before the outgoing
      // one is disposed, so the withdrawal arrives *after* the new value.
      final outgoing = Object();
      final incoming = Object();
      ShellInsets.publishTop(outgoing, 52);
      await frame(tester);

      ShellInsets.publishTop(incoming, 72);
      ShellInsets.withdraw(outgoing);
      await frame(tester);

      expect(ShellInsets.top.value, 72);
    });

    testWidgets('and cannot clear it by leaving first either', (tester) async {
      final outgoing = Object();
      final incoming = Object();
      ShellInsets.publishTop(outgoing, 52);
      await frame(tester);

      ShellInsets.withdraw(outgoing);
      ShellInsets.publishTop(incoming, 72);
      await frame(tester);

      expect(ShellInsets.top.value, 72);
    });
  });
}
