@TestOn('vm')
library;

import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/util/file_pick.dart';

/// The picker seam.
///
/// Linux is the reason it exists: `file_picker` has no plugin there, only a
/// pure-Dart shell-out to zenity/qarma/kdialog, and inside a snap none of those
/// is on `$PATH` — the dialog never opened and nothing said why. What can be
/// checked here without a desktop is the part that decides *which* picker runs,
/// the filter it hands GTK, and the fact that a file handed over by the XDG
/// document portal — which arrives under a path the user never saw — still
/// uploads under the name they picked.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('defaultFilePickBackend', () {
    test('Linux gets the portal-capable picker', () {
      expect(
        defaultFilePickBackend(isWeb: false, platform: TargetPlatform.linux),
        isA<FileSelectorBackend>(),
      );
    });

    test('web wins over the platform it happens to run on', () {
      // Flutter web in a browser on a Linux desktop reports
      // TargetPlatform.linux. There is no GTK there, so the order of these two
      // checks is load-bearing rather than stylistic.
      expect(
        defaultFilePickBackend(isWeb: true, platform: TargetPlatform.linux),
        isA<FilePickerPluginBackend>(),
      );
    });

    test('every other platform keeps file_picker', () {
      for (final platform in const [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.fuchsia,
      ]) {
        expect(
          defaultFilePickBackend(isWeb: false, platform: platform),
          isA<FilePickerPluginBackend>(),
          reason: '$platform must not change picker',
        );
      }
    });
  });

  group('galleryIsAFileDialog', () {
    test('Linux has no photo library, only a file dialog', () {
      // image_picker_linux forwards ImageSource.gallery to file_selector_linux
      // with an English 'Images' filter and no confirm-button text. The
      // composer asks this so its "Galerie" row takes the seam instead and the
      // dialog speaks the app's language.
      expect(
        galleryIsAFileDialog(isWeb: false, platform: TargetPlatform.linux),
        isTrue,
      );
    });

    test('platforms with a real gallery keep image_picker', () {
      for (final platform in const [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.fuchsia,
      ]) {
        expect(
          galleryIsAFileDialog(isWeb: false, platform: platform),
          isFalse,
          reason: '$platform must keep the native gallery',
        );
      }
    });

    test('web is a browser, not a GTK desktop', () {
      expect(
        galleryIsAFileDialog(isWeb: true, platform: TargetPlatform.linux),
        isFalse,
      );
    });
  });

  group('imageTypeGroup', () {
    test('names itself with the label the caller translated', () {
      expect(imageTypeGroup('Bilder').label, 'Bilder');
    });

    test('actually filters — an empty group would show everything', () {
      // XTypeGroup.allowsAny is true when every list is empty, and GTK would
      // then draw a filter labelled "Images" that lets any file through. It is
      // one deletion away at all times.
      expect(imageTypeGroup('x').allowsAny, isFalse);
    });

    test('lists extensions lower-case, the way GTK globs them', () {
      // file_selector_linux turns each entry into the pattern `*.<ext>`, which
      // GtkFileFilter then matches case-sensitively — an upper-case entry here
      // would match only the shouting half of the world's file names.
      for (final ext in imageTypeGroup('x').extensions!) {
        expect(ext, equals(ext.toLowerCase()));
      }
    });

    test('offers WebP, which the dialog it replaces did not', () {
      // The zenity filter was `*.bmp *.gif *.jpeg *.jpg *.png` — a WebP the
      // server accepts was simply not selectable.
      expect(imageTypeGroup('x').extensions, contains('webp'));
      expect(imageTypeGroup('x').mimeTypes, contains('image/webp'));
    });

    test('carries MIME types too, so case is not a filter', () {
      // GtkFileFilter patterns match case-sensitively, so `*.jpg` alone hides
      // `HOLIDAY.JPG`; the MIME half is what catches it.
      final group = imageTypeGroup('x');
      expect(group.mimeTypes, isNotEmpty);
      expect(group.mimeTypes!.every((m) => m.startsWith('image/')), isTrue);
    });

    test('does not offer SVG, which the server rejects', () {
      final group = imageTypeGroup('x');
      expect(group.extensions, isNot(contains('svg')));
      expect(group.mimeTypes, isNot(contains('image/svg+xml')));
    });
  });

  group('describeChosenFile', () {
    late Directory temp;

    setUp(() => temp = Directory.systemTemp.createTempSync('hinata_pick'));
    tearDown(() => temp.deleteSync(recursive: true));

    test('keeps the name the user picked out of a portal path', () async {
      // What the FileChooser portal hands back is not the path the user
      // browsed: the file is re-exposed through the document portal's FUSE
      // mount as /run/user/<uid>/doc/<hash>/<name>. The directory is
      // unrecognisable, the name is not — and the name is the only part the
      // upload uses.
      final docDir = Directory('${temp.path}/doc/1a2b3c4d')
        ..createSync(recursive: true);
      final file = File('${docDir.path}/Quartalsbericht Q3.pdf')
        ..writeAsBytesSync(List.filled(2048, 7));

      final picked = await describeChosenFile(XFile(file.path), false);

      expect(picked.name, 'Quartalsbericht Q3.pdf');
      expect(picked.path, file.path);
      expect(picked.size, 2048);
      expect(picked.bytes, isNull);
    });

    test('reads the bytes only when asked, and then trusts them', () async {
      final file = File('${temp.path}/note.png')
        ..writeAsBytesSync(List.filled(64, 1));

      final withData = await describeChosenFile(XFile(file.path), true);
      expect(withData.bytes, hasLength(64));
      expect(withData.size, 64);

      final without = await describeChosenFile(XFile(file.path), false);
      expect(without.bytes, isNull);
      expect(without.size, 64);
    });

    test('a file that is gone reports size 0 instead of throwing', () async {
      // Same answer file_picker gives for an unreadable path. The upload then
      // fails on its own terms, with a message about the upload — rather than
      // the whole pick collapsing into "couldn't open the file dialog".
      final picked = await describeChosenFile(
        XFile('${temp.path}/never-existed.bin'),
        false,
      );
      expect(picked.size, 0);
      expect(picked.name, 'never-existed.bin');
    });

    test('but a file that is gone and was asked for by value throws', () async {
      // The other half of the same decision: an unreadable size is a guess we
      // can do without, an unreadable *body* is the upload itself. Swallowing
      // it would post an empty file and call it a success.
      await expectLater(
        describeChosenFile(XFile('${temp.path}/never-existed.bin'), true),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('FileSelectorBackend', () {
    const labels = FilePickLabels(images: 'Bilder', confirm: 'Öffnen');

    test('a cancelled single pick is an empty list, not an error', () async {
      final selector = _RecordingSelector(single: null);
      final picked = await FileSelectorBackend(selector).pick(
        kind: FilePickKind.any,
        allowMultiple: false,
        withData: false,
        labels: labels,
      );
      expect(picked, isEmpty);
    });

    test('a cancelled multi pick is an empty list too', () async {
      final selector = _RecordingSelector(multiple: const []);
      final picked = await FileSelectorBackend(selector).pick(
        kind: FilePickKind.any,
        allowMultiple: true,
        withData: false,
        labels: labels,
      );
      expect(picked, isEmpty);
      expect(selector.openedMultiple, isTrue);
    });

    test('allowMultiple decides which dialog opens', () async {
      final one = _RecordingSelector(single: null);
      await FileSelectorBackend(one).pick(
        kind: FilePickKind.any,
        allowMultiple: false,
        withData: false,
        labels: labels,
      );
      expect(one.openedMultiple, isFalse);
    });

    test('"any" filters nothing — null, never an empty filter list', () async {
      // An empty list of type groups is a dropdown with no entries, which is
      // not the same thing as no filtering at all.
      final selector = _RecordingSelector(single: null);
      await FileSelectorBackend(selector).pick(
        kind: FilePickKind.any,
        allowMultiple: false,
        withData: false,
        labels: labels,
      );
      expect(selector.groups, isNull);
    });

    test('an image pick sends exactly one, translated, filter', () async {
      final selector = _RecordingSelector(single: null);
      await FileSelectorBackend(selector).pick(
        kind: FilePickKind.image,
        allowMultiple: false,
        withData: false,
        labels: labels,
      );
      expect(selector.groups, hasLength(1));
      expect(selector.groups!.single.label, 'Bilder');
    });

    test('the accept button is ours, not the GTK English default', () async {
      final selector = _RecordingSelector(single: null);
      await FileSelectorBackend(selector).pick(
        kind: FilePickKind.any,
        allowMultiple: false,
        withData: false,
        labels: labels,
      );
      expect(selector.confirmButtonText, 'Öffnen');
    });
  });

  group('pickFilesToUpload', () {
    tearDown(() => debugFilePickBackend = null);

    testWidgets('forwards the request and hands the choice back', (
      tester,
    ) async {
      final backend = _RecordingBackend([
        const ChosenFile(name: 'a.png', size: 3, path: '/tmp/a.png'),
      ]);
      debugFilePickBackend = backend;

      late List<ChosenFile> picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await pickFilesToUpload(
                  context,
                  kind: FilePickKind.image,
                  allowMultiple: true,
                  withData: true,
                );
              },
              child: const Text('pick'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('pick'));
      await tester.pumpAndSettle();

      expect(backend.kind, FilePickKind.image);
      expect(backend.allowMultiple, isTrue);
      expect(backend.withData, isTrue);
      expect(picked.single.name, 'a.png');
    });

    testWidgets('labels come from the translation layer', (tester) async {
      // Not asserting the rendered words — there is no i18n bundle in a widget
      // test, so `context.t` echoes the key. What matters structurally is that
      // both labels went through it rather than being written into the picker.
      final backend = _RecordingBackend(const []);
      debugFilePickBackend = backend;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => pickFilesToUpload(context),
              child: const Text('pick'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('pick'));
      await tester.pumpAndSettle();

      expect(backend.labels!.images, isNotEmpty);
      expect(backend.labels!.confirm, isNotEmpty);
    });
  });
}

/// A [FileSelectorPlatform] that opens nothing and remembers what it was asked.
///
/// `extends`, not `implements`: the base class hands out the platform-interface
/// token, and every method this test does not care about keeps its default
/// "not implemented" body.
class _RecordingSelector extends FileSelectorPlatform {
  _RecordingSelector({this.single, this.multiple = const []});

  final XFile? single;
  final List<XFile> multiple;

  List<XTypeGroup>? groups;
  String? confirmButtonText;
  bool openedMultiple = false;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    groups = acceptedTypeGroups;
    this.confirmButtonText = confirmButtonText;
    openedMultiple = false;
    return single;
  }

  @override
  Future<List<XFile>> openFiles({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    groups = acceptedTypeGroups;
    this.confirmButtonText = confirmButtonText;
    openedMultiple = true;
    return multiple;
  }
}

/// A backend that opens nothing, for testing the seam's own wiring.
class _RecordingBackend implements FilePickBackend {
  _RecordingBackend(this.result);

  final List<ChosenFile> result;

  FilePickKind? kind;
  bool? allowMultiple;
  bool? withData;
  FilePickLabels? labels;

  @override
  Future<List<ChosenFile>> pick({
    required FilePickKind kind,
    required bool allowMultiple,
    required bool withData,
    required FilePickLabels labels,
  }) async {
    this.kind = kind;
    this.allowMultiple = allowMultiple;
    this.withData = withData;
    this.labels = labels;
    return result;
  }
}
