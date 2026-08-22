import CoreGraphics
import Foundation
import PDFKit

#if canImport(FlutterMacOS)
  import FlutterMacOS
#else
  import Flutter
#endif

/// Bakes a PDF's annotations into its pages, because the Apple rasterizer will
/// not draw them.
///
/// The `printing` package rasterizes PDFs on the platform side, and every
/// backend it uses paints annotations — pdfium with `FPDF_ANNOT` on Windows and
/// Linux, pdf.js in the browser. Apple is the exception: `PrintJob.rasterPdf`
/// draws the page with `CGContext.drawPDFPage`, and Core Graphics deliberately
/// renders the content stream only. Annotations — among them every AcroForm
/// widget, that is the boxes of a form *and the values typed into them* — are
/// the host application's job there.
///
/// PDFKit is that host application's toolbox and does draw them. So rather than
/// rasterizing differently, this hands the rasterizer a different document:
/// every page redrawn through PDFKit into a fresh PDF with the annotations part
/// of the page content. The result is still vector, so raster resolution and
/// everything the viewer does above it stay exactly as they were.
///
/// This file is kept byte-identical between `ios/Runner` and `macos/Runner`:
/// the two are separate Xcode projects and cannot share a source file, but
/// nothing in here is platform-specific, so the copies must not drift.
enum HinataPdfChannel {
  private static let channelName = "hinata/pdf"
  private static let flattenMethod = "flattenAnnotations"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == flattenMethod else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let data = (call.arguments as? FlutterStandardTypedData)?.data else {
        result(
          FlutterError(
            code: "invalid-argument",
            message: "\(flattenMethod) expects the PDF bytes",
            details: nil))
        return
      }
      // Parsing and redrawing a document is not platform-thread work: the
      // caller is awaiting a Future and the viewer is showing its loading
      // state, but the UI still has to animate while this runs.
      DispatchQueue.global(qos: .userInitiated).async {
        let flattened = flatten(data)
        DispatchQueue.main.async {
          // `nil` means "nothing to do here" — Dart then keeps the bytes it
          // already holds instead of paying for a copy of the same document.
          result(flattened.map { FlutterStandardTypedData(bytes: $0) })
        }
      }
    }
  }

  /// The document redrawn with its annotations, or `nil` when it does not need
  /// (or cannot survive) the treatment.
  private static func flatten(_ data: Data) -> Data? {
    guard let document = PDFDocument(data: data), document.pageCount > 0 else { return nil }
    // An encrypted document we cannot open draws nothing at all; handing back
    // a stack of blank pages would be worse than the missing annotations.
    guard !document.isLocked else { return nil }
    guard hasAnnotations(document) else { return nil }

    let output = NSMutableData()
    guard let consumer = CGDataConsumer(data: output as CFMutableData),
      var documentBox = mediaBox(of: document.page(at: 0)),
      let context = CGContext(consumer: consumer, mediaBox: &documentBox, nil)
    else { return nil }

    for index in 0..<document.pageCount {
      // A page we cannot open or size would come out missing or misplaced, and
      // a document one page short is a worse bug than an unpainted annotation.
      guard let page = document.page(at: index), var pageBox = mediaBox(of: page) else {
        context.closePDF()
        return nil
      }
      let pageInfo: [String: Any] = [
        kCGPDFContextMediaBox as String: NSData(
          bytes: &pageBox, length: MemoryLayout<CGRect>.size)
      ]
      context.beginPDFPage(pageInfo as CFDictionary)
      // No transform of our own: `draw(with:to:)` already turns the page
      // upright and puts the box origin at zero. That also straightens pages
      // whose media box starts somewhere else — which the Core Graphics
      // rasterizer, reading only the box's *size*, renders shifted today.
      page.draw(with: .mediaBox, to: context)
      context.endPDFPage()
    }
    context.closePDF()
    return output.length > 0 ? output as Data : nil
  }

  /// The box one flattened page needs: the media box turned upright, because
  /// `draw(with:to:)` hands the page over the way a reader sees it while the
  /// `/Rotate` entry itself does not survive into the new document.
  private static func mediaBox(of page: PDFPage?) -> CGRect? {
    guard let page else { return nil }
    let bounds = page.bounds(for: .mediaBox)
    guard bounds.width.isFinite, bounds.height.isFinite,
      bounds.width >= 1, bounds.height >= 1
    else { return nil }
    let rotation = ((page.rotation % 360) + 360) % 360
    let upright =
      (rotation == 90 || rotation == 270)
      ? CGSize(width: bounds.height, height: bounds.width)
      : bounds.size
    return CGRect(origin: .zero, size: upright)
  }

  /// Whether redrawing the document can add anything. Most attachments — a
  /// scan, an invoice, an exported report — carry no annotations at all, and
  /// those pay for this scan and nothing else.
  private static func hasAnnotations(_ document: PDFDocument) -> Bool {
    for index in 0..<document.pageCount {
      if let page = document.page(at: index), !page.annotations.isEmpty { return true }
    }
    return false
  }
}
