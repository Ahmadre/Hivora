import 'package:flutter/foundation.dart'
    show TargetPlatform, Uint8List, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';

/// Draws a PDF's annotations into its pages on Apple platforms.
///
/// Every platform the app rasterizes PDFs on paints annotations — pdfium under
/// Windows and Linux, `PdfRenderer` on Android, pdf.js in the browser — except
/// Apple, where Core Graphics renders the page's content stream and nothing
/// else. An AcroForm field *is* an annotation, so a filled-in form arrived in
/// the attachment viewer as a blank sheet on iOS and macOS (HIN-58). The runner
/// redraws such a document through PDFKit; the *why* and the limits live there,
/// in `ios/Runner/HinataPdfChannel.swift`.
///
/// Everything here degrades to the untouched input rather than throwing: a
/// document that cannot be flattened must still render the way it did before.
class PdfAnnotations {
  const PdfAnnotations._();

  static const MethodChannel _channel = MethodChannel('hinata/pdf');

  /// Above this, the document is handed to the rasterizer as it is.
  ///
  /// The runner enforces the same ceiling — this one only keeps the app from
  /// copying tens of megabytes across the channel to be told so. Both sides
  /// have to hold on their own: the native side sees documents this one cannot
  /// measure (page count), and this one runs in builds whose runner is older.
  static const int _maxBytes = 32 * 1024 * 1024;

  /// Only Apple rasterizes without annotations, and only there is the runner
  /// listening. `kIsWeb` is the load-bearing half of this: a browser on a Mac
  /// reports [TargetPlatform.macOS], and the web build has no runner at all —
  /// it would spend a `MissingPluginException` per PDF to find that out.
  static bool get _isApple =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  /// Returns [bytes] with every annotation painted into the page content.
  ///
  /// Hands back the input unchanged when there is nothing to gain (no
  /// annotations that paint, an encrypted document, a platform that renders
  /// them anyway) or when the redraw fails — the native side answers `null` for
  /// that case rather than copying an identical document back over the channel.
  static Future<Uint8List> flatten(Uint8List bytes) async {
    if (!_isApple || bytes.isEmpty || bytes.lengthInBytes > _maxBytes) {
      return bytes;
    }
    try {
      final flattened = await _channel.invokeMethod<Uint8List>(
        'flattenAnnotations',
        bytes,
      );
      if (flattened == null || flattened.isEmpty) return bytes;
      return flattened;
    } on MissingPluginException {
      // No runner on the other end — a widget test, or a build that predates
      // the channel. The document still renders, just without its annotations.
      return bytes;
    } on PlatformException catch (e) {
      debugPrint('PDF annotation flattening failed: ${e.code} ${e.message}');
      return bytes;
    }
  }
}
