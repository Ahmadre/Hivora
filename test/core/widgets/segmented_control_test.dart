import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:hinata/core/widgets/hive_widgets.dart';

/// On a phone the board header has to fit the view switcher, the group-by
/// button and the filter button on one row, so the switcher drops its labels.
/// Dropping them silently would leave two unexplained icons — the label has to
/// survive as a tooltip.
void main() {
  final items = [
    const SegmentItem(label: 'Board', icon: LucideIcons.squareKanban),
    const SegmentItem(label: 'Timeline', icon: LucideIcons.waypoints),
  ];

  Widget host({required bool iconsOnly}) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: Center(
        child: SegmentedControl(
          items: items,
          selected: 0,
          iconsOnly: iconsOnly,
          onChanged: (_) {},
        ),
      ),
    ),
  );

  testWidgets('icons-only hides the labels but keeps them as tooltips', (
    tester,
  ) async {
    await tester.pumpWidget(host(iconsOnly: true));

    expect(find.text('Board'), findsNothing);
    expect(find.text('Timeline'), findsNothing);
    expect(
      tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((t) => t.message)
          .toList(),
      ['Board', 'Timeline'],
    );
  });

  testWidgets('wide layouts keep the labels and add no tooltip', (
    tester,
  ) async {
    await tester.pumpWidget(host(iconsOnly: false));

    expect(find.text('Board'), findsOneWidget);
    expect(find.text('Timeline'), findsOneWidget);
    // A tooltip repeating a label the user can already read is noise.
    expect(find.byType(Tooltip), findsNothing);
  });
}
