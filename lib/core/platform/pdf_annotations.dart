import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';

/// Draws a PDF's annotations into its pages on Apple platforms.
///
/// The `printing` package rasterizes PDFs natively, and every backend it uses
/// paints annotations — pdfium with `FPDF_ANNOT` on Windows and Linux, pdf.js
/// in the browser. Apple is the exception: its `rasterPdf` draws the page with
/// `CGContext.drawPDFPage`, and Core Graphics deliberately paints the content
/// stream only. Annotations are left to the host application.
///
/// That is not a detail for form documents. An AcroForm field *is* an
/// annotation: its box, its border and — the part anyone notices — the value
/// typed into it. A filled-in form therefore arrived in the attachment viewer
/// as a blank sheet on iOS and macOS while the same file rendered completely on
/// the web.
///
/// PDFKit, the framework built for showing PDFs, does draw them. So instead of
/// rasterizing differently, the runner hands `printing` a different document:
/// every page redrawn through PDFKit with its annotations baked into the page
/// content. It stays vector, so the raster resolution, the DPI maths and the
/// viewer above them are untouched — only the missing ink appears.
///
/// Everything here degrades to the untouched input rather than throwing: a
/// document that cannot be flattened must still render the way it did before.
class PdfAnnotations {
  const PdfAnnotations._();

  static const MethodChannel _channel = MethodChannel('hinata/pdf');

  /// Only Apple rasterizes without annotations, and only there is the runner
  /// listening. Everywhere else this is a plain pass-through, so callers can
  /// stay platform-agnostic.
  static bool get _isApple =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  /// Returns [bytes] with every annotation painted into the page content.
  ///
  /// Hands back the input unchanged when there is nothing to gain (no
  /// annotations, an encrypted document, a platform that renders them anyway)
  /// or when the redraw fails — the native side answers `null` for that case
  /// rather than copying an identical document back over the channel.
  static Future<Uint8List> flatten(Uint8List bytes) async {
    if (!_isApple || bytes.isEmpty) return bytes;
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
