/// Owning an editable document from outside the widget tree.
library;

import 'package:flutter/foundation.dart';
import 'package:lexical_editor_flutter/lexical_editor_flutter.dart';

import 'hinata_lexical.dart';

/// Holds an editable document, the way a `TextEditingController` holds a string.
///
/// The hosts of this editor — the knowledge base, an issue sheet, the comment
/// composer — all want the same two things: seed the editor with what the API
/// returned, and read back what to send. A controller gives them that without
/// any of them touching a `LexicalEditor`, and it keeps the "is it dirty yet"
/// question in one place instead of three.
class HinataEditorController extends ChangeNotifier {
  /// Creates a controller, optionally seeded with a stored document.
  HinataEditorController({String? doc}) {
    _editor = createHinataEditor();
    _initial = _load(doc);
    _editor.registerUpdateListener((_) {
      if (_disposed) return;
      notifyListeners();
    });
  }

  late final LexicalEditor _editor;
  late String _initial;
  bool _disposed = false;

  /// The editor the field renders. Hosts rarely need this.
  LexicalEditor get editor => _editor;

  /// The current document as stored JSON — what to send to the API.
  String get doc => _editor.toJsonString();

  /// The document's plain text, for an empty check or a preview.
  String get plainText =>
      _editor.editorState.read(() => $getRoot().getTextContent());

  /// Whether the document holds nothing a reader would see.
  ///
  /// Text only: a document whose sole content is an image is not empty, and
  /// [hasContent] is the check that knows the difference.
  bool get isEmpty => !hasContent;

  /// Whether the document holds anything at all — text, or a node that renders
  /// something on its own such as an image or a divider.
  bool get hasContent => _editor.editorState.read(() {
    final root = $getRoot();
    if (root.getTextContent().trim().isNotEmpty) return true;
    return _anyDecorator(root);
  });

  static bool _anyDecorator(ElementNode element) {
    for (final child in element.children) {
      if (child is DecoratorNode) return true;
      if (child is ElementNode && _anyDecorator(child)) return true;
    }
    return false;
  }

  /// Whether the document differs from what it was seeded with.
  ///
  /// Compares serialized documents rather than a dirty flag: an edit that is
  /// typed and undone should leave the save bar alone, and a flag cannot tell.
  bool get isDirty => doc != _initial;

  /// Replaces the content, and treats the result as the new clean state.
  void load(String? doc) {
    _initial = _load(doc);
    notifyListeners();
  }

  /// Marks the current content as saved, so [isDirty] reads false again.
  void markSaved() {
    _initial = doc;
    notifyListeners();
  }

  String _load(String? doc) {
    if (doc != null && doc.trim().isNotEmpty) {
      try {
        _editor.setEditorState(_editor.parseEditorStateFromString(doc));
        return _editor.toJsonString();
      } on Object {
        // Unreadable: start from an empty document rather than refusing to open
        // the editor at all. The alternative is a page the user cannot use and
        // cannot repair.
      }
    }
    _editor.update(() {
      final root = $getRoot()..clear();
      root.append($createParagraphNode());
    }, discrete: true);
    return _editor.toJsonString();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
