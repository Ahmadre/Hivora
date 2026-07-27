/// The read-only renderer, against the same corpus the wire contract uses.
///
/// The contract test proves a stored document *opens*. This proves it reaches
/// the screen: every fixture renders without an overflow, an exception or a
/// failed layout, at the narrowest width the app ever uses.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/lexical/hinata_document.dart';

void main() {
  /// A phone in portrait — the width where a table or a long code line
  /// overflows first.
  const narrow = Size(320, 900);

  Future<void> pumpDoc(
    WidgetTester tester,
    String doc, {
    Size size = narrow,
    double fontSize = 15,
    SmartLinkTapped? onTapSmartLink,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HinataDocument(
              doc: doc,
              fontSize: fontSize,
              onTapSmartLink: onTapSmartLink,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String fixture(String name) =>
      File('test/fixtures/richtext/$name.json').readAsStringSync();

  final names =
      Directory('test/fixtures/richtext')
          .listSync()
          .whereType<File>()
          .map((file) => file.uri.pathSegments.last.replaceAll('.json', ''))
          .toList()
        ..sort();

  group('every stored document renders', () {
    for (final name in names) {
      testWidgets('$name renders on a narrow screen without overflowing', (
        tester,
      ) async {
        await pumpDoc(tester, fixture(name));

        // takeException() returns the overflow assertion when a RenderFlex or a
        // paragraph runs past its constraints, which is exactly the failure
        // that would otherwise only be visible on a device.
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('the surfaces size independently', () {
    testWidgets('a comment renders at its smaller body size', (tester) async {
      await pumpDoc(tester, fixture('paragraph'), fontSize: 13.5);

      expect(tester.takeException(), isNull);
      expect(find.byType(HinataDocument), findsOneWidget);
    });
  });

  group('degrading rather than failing', () {
    testWidgets('an unreadable document renders nothing', (tester) async {
      // A broken article must not take its page down with it.
      await pumpDoc(tester, '{ not json at all');

      expect(tester.takeException(), isNull);
    });

    testWidgets('a document of an unknown node type renders nothing', (
      tester,
    ) async {
      await pumpDoc(
        tester,
        '{"root":{"type":"root","version":1,"format":"","indent":0,'
        '"direction":null,"children":[{"type":"somethingNew","version":1}]}}',
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty document renders nothing', (tester) async {
      await pumpDoc(tester, '');

      expect(tester.takeException(), isNull);
      expect(find.byType(HinataDocument), findsOneWidget);
    });
  });

  group('smart links are tappable', () {
    testWidgets('tapping a chip reports its kind and target', (tester) async {
      final taps = <String>[];
      await pumpDoc(
        tester,
        fixture('smart-links'),
        onTapSmartLink: (kind, targetId) => taps.add('${kind.wire}:$targetId'),
      );

      // The issue chip carries a readable label, so it is findable by it —
      // and a label is what the reader sees, which is the point of storing one.
      await tester.tap(find.text('HIN-5'));
      await tester.pump();

      expect(taps, ['issue:HIN-5']);
    });
  });
}
