/// The chrome around an image while it is being edited.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/lexical/hinata_editor.dart';
import 'package:hinata/core/lexical/hinata_editor_controller.dart';
import 'package:hinata/core/lexical/hinata_theme.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:lexical_editor_flutter/lexical_editor_flutter.dart';

void main() {
  test('the drag handles are hinata amber, not the bundle blue', () {
    // The handles are the most visible thing about editing an image, and the
    // package's default is a blue borrowed from nothing in this product.
    const bundleBlue = Color(0xFF3F8AE0);
    final style = hinataImageStyle();

    expect(style.accent, AppColors.accent);
    expect(style.accent, isNot(bundleBlue));
    expect(style.handleFill, AppColors.accentStrong);
    // A 10px dot has to stay findable over a screenshot of anything.
    expect(style.handleShadows, isNotEmpty);
    expect(style.handleRadius, greaterThan(0));
  });

  testWidgets('an editable image is drawn with that chrome', (tester) async {
    // Wired at the seam every authoring surface goes through, so a new host
    // cannot get the blue back by forgetting to pass it.
    tester.view
      ..physicalSize = const Size(900, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = HinataEditorController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HinataEditor(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    controller.editor.dispatchCommand(
      insertImageCommand,
      const ImageAttributes(src: '/api/v1/media/x', altText: 'x'),
    );
    await tester.pumpAndSettle();

    final view = tester.widget<LexicalImageView>(find.byType(LexicalImageView));
    expect(view.style.accent, AppColors.accent);
    expect(view.editable, isTrue);
    // And the box no longer forces a never-resized image to nothing.
    expect(view.width, isNull);
    expect(view.height, isNull);
  });
}
