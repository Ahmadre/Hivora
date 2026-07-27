/// The glass dropdown, and the one thing about it that is not visual.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/widgets/glass_popup_menu.dart';

void main() {
  Future<void> pumpMenu(
    WidgetTester tester, {
    required ValueChanged<bool> onOpenChanged,
    required ValueChanged<String> onSelected,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: GlassPopupMenu<String>(
              value: 'eins',
              onSelected: onSelected,
              onOpenChanged: onOpenChanged,
              items: const [
                GlassMenuItem<String>(value: 'eins', label: 'Eins'),
                GlassMenuItem<String>(value: 'zwei', label: 'Zwei'),
              ],
              child: const Text('trigger'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('reports when it is open, and when it is not', (tester) async {
    // What this is for: an anchor that shares the screen with something
    // floating of its own — the editor's selection overlay points at the same
    // words the menu opens over — and nothing else can know when to step
    // aside.
    final events = <bool>[];
    await pumpMenu(tester, onOpenChanged: events.add, onSelected: (_) {});

    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();
    expect(events, [true]);

    await tester.tap(find.text('Zwei'));
    await tester.pumpAndSettle();
    expect(events, [true, false]);
  });

  testWidgets('reports the close even when nothing was chosen', (tester) async {
    // Dismissed on the barrier. Whatever stepped aside has to be told to come
    // back, or it never returns.
    final events = <bool>[];
    var picked = 0;
    await pumpMenu(
      tester,
      onOpenChanged: events.add,
      onSelected: (_) => picked++,
    );

    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(events, [true, false]);
    expect(picked, 0);
  });
}
