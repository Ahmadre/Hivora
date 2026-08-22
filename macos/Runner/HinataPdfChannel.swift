import CoreGraphics
import Foundation
import PDFKit

#if canImport(FlutterMacOS)
  import FlutterMacOS
#else
  import Flutter
#endif

/// Zeichnet die Annotationen eines PDFs in die Seiten, weil der Apple-Rasterizer
/// das nicht tut.
///
/// Das `printing`-Paket rastert PDFs auf der Plattformseite, und jedes Backend
/// malt dabei die Annotationen mit — pdfium mit `FPDF_ANNOT` unter Windows und
/// Linux, `PdfRenderer` unter Android, pdf.js im Browser. Apple ist die
/// Ausnahme: `PrintJob.rasterPdf` zeichnet die Seite mit
/// `CGContext.drawPDFPage`, und Core Graphics rendert bewusst nur den
/// Content-Stream. Annotationen — darunter jedes AcroForm-Widget, also die
/// Kästen eines Formulars *und die eingetippten Werte* — sind dort Sache der
/// Host-App.
///
/// PDFKit ist der Werkzeugkasten dieser Host-App und zeichnet sie. Statt anders
/// zu rastern bekommt der Rasterizer deshalb ein anderes Dokument: jede Seite
/// durch PDFKit in ein frisches PDF neu gezeichnet, die Annotationen Teil des
/// Seiteninhalts. Das Ergebnis bleibt vektoriell — Auflösung und alles, was der
/// Viewer darüber tut, bleiben unverändert.
///
/// Diese Datei ist in `ios/Runner` und `macos/Runner` byteweise identisch: die
/// beiden Runner sind getrennte Xcode-Projekte und können keine Quelldatei
/// teilen, aber nichts hier ist plattformspezifisch. Ein Test hält die Kopien
/// zusammen (`test/core/platform/pdf_annotations_test.dart`).
enum HinataPdfChannel {
  private static let channelName = "hinata/pdf"
  private static let flattenMethod = "flattenAnnotations"

  /// Obergrenzen, ab denen das Dokument unangetastet bleibt.
  ///
  /// Beide sind nötig, weil `PDFDocument.page(at:)` in PDFKit linear läuft und
  /// die Schleifen hier damit quadratisch werden: 1.000 Seiten kosten 0,05 s,
  /// 20.000 kosten 16,6 s und 100.000 — 14 MB, also unterhalb des Upload-Limits
  /// des Servers — halten den Viewer elf Minuten lang an. Und weil das Neu-
  /// zeichnen alles-oder-nichts ist, stünde davor kein Bild, während `printing`
  /// ohne uns die erste Seite sofort zeigt.
  ///
  /// Oberhalb der Grenzen rendert das Dokument also wie bisher: ohne
  /// Annotationen, aber sofort. Der Preis ist auf 512 Seiten (~0,02 s Scan)
  /// gedeckelt, und die Bytegrenze hat in `PdfAnnotations` ihr Gegenstück, damit
  /// große Dateien gar nicht erst über den Kanal kopiert werden.
  private static let maxBytes = 32 * 1024 * 1024
  private static let maxPages = 512

  /// Die größte Seite, die die PDF-Spezifikation kennt (200 Zoll). Alles
  /// darüber ist kaputt oder böswillig — und der Rasterizer dahinter legt für
  /// eine solche Seite ein Bitmap in Terabyte-Größe an.
  private static let maxPageSide: CGFloat = 14_400

  /// Eine Seite wird zur Zeit neu gezeichnet.
  ///
  /// PDFKit serialisiert intern ohnehin (vier gleichzeitige Durchläufe brauchen
  /// fast die vierfache Zeit), gleichzeitige Läufe kosten also nur Speicher —
  /// gemessen 1,3 GB bei acht Dokumenten, wo eines 195 MB braucht. Durch den
  /// Viewer zu wischen startet aber genau das: einen Lauf pro PDF, an dem man
  /// vorbeikommt. Seriell bleibt der Spitzenbedarf der eines Dokuments.
  private static let queue = DispatchQueue(
    label: "hn.asta.hinata.pdf-flatten", qos: .userInitiated)

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
            message: "\(flattenMethod) erwartet die PDF-Bytes",
            details: nil))
        return
      }
      // Nichts davon gehört auf den Plattform-Thread: der Aufrufer wartet auf
      // ein Future und der Viewer zeigt seinen Ladezustand, aber die Oberfläche
      // muss weiterlaufen.
      queue.async {
        let flattened = flatten(data)
        DispatchQueue.main.async {
          // `nil` heißt „hier gibt es nichts zu tun" — Dart behält dann die
          // Bytes, die es schon hat, statt eine Kopie desselben Dokuments zu
          // bezahlen.
          result(flattened.map { FlutterStandardTypedData(bytes: $0) })
        }
      }
    }
  }

  /// Das neu gezeichnete Dokument, oder `nil`, wenn es die Behandlung nicht
  /// braucht (oder nicht überlebt).
  private static func flatten(_ data: Data) -> Data? {
    guard data.count <= maxBytes else { return nil }
    // Ein verschlüsseltes Dokument, das wir nicht öffnen können, zeichnet gar
    // nichts; ein Stapel leerer Seiten wäre schlimmer als fehlende
    // Annotationen.
    guard let document = PDFDocument(data: data), !document.isLocked else { return nil }
    let count = document.pageCount
    guard count > 0, count <= maxPages else { return nil }

    // Die Seiten einmal einsammeln statt zweimal zu suchen: `page(at:)` läuft
    // linear, also kostet jeder zusätzliche Durchlauf quadratisch.
    var pages: [PDFPage] = []
    pages.reserveCapacity(count)
    for index in 0..<count {
      guard let page = document.page(at: index) else { return nil }
      pages.append(page)
    }
    guard pages.contains(where: hasVisibleAnnotation) else { return nil }

    // Erst alle Seitenmaße prüfen, dann zeichnen. Andersherum würde eine
    // kaputte Seite ganz am Ende die Arbeit aller vorherigen verwerfen.
    var boxes: [CGRect] = []
    boxes.reserveCapacity(count)
    for page in pages {
      guard let box = mediaBox(of: page) else { return nil }
      boxes.append(box)
    }

    let output = NSMutableData()
    var documentBox = boxes[0]
    guard let consumer = CGDataConsumer(data: output as CFMutableData),
      let context = CGContext(consumer: consumer, mediaBox: &documentBox, nil)
    else { return nil }

    for (page, box) in zip(pages, boxes) {
      var pageBox = box
      let pageInfo: [String: Any] = [
        kCGPDFContextMediaBox as String: NSData(
          bytes: &pageBox, length: MemoryLayout<CGRect>.size)
      ]
      context.beginPDFPage(pageInfo as CFDictionary)
      // Keine eigene Transformation: `draw(with:to:)` stellt die Seite bereits
      // aufrecht und legt den Ursprung der Box auf null. Das rückt nebenbei
      // Seiten gerade, deren Media-Box woanders beginnt — die zeichnet der
      // Core-Graphics-Rasterizer, der nur die *Größe* der Box liest, heute
      // verschoben. Nur eben für Dokumente, die hier überhaupt ankommen.
      page.draw(with: .mediaBox, to: context)
      context.endPDFPage()
    }
    context.closePDF()
    return output.length > 0 ? output as Data : nil
  }

  /// Ob auf dieser Seite eine Annotation steht, die überhaupt etwas malt.
  ///
  /// „Hat Annotationen" ist die falsche Frage. Jeder aus Chrome gedruckte
  /// Report trägt `/Link`-Annotationen über seinem Inhaltsverzeichnis, und ein
  /// Link malt nichts — er ist ein Rechteck, auf das man klicken kann. Auf
  /// dieser Frage stand ein 33-seitiger Review-Report zwei Sekunden lang still
  /// und wurde dabei fünfundzwanzigmal so groß (Core Graphics löst die Type-3-
  /// Schriften solcher Dokumente in Pfade auf), um am Ende 0,11 % der Pixel zu
  /// verändern — Kantenglättung.
  ///
  /// Ein Link *kann* einen sichtbaren Rahmen haben, deshalb wird der Typ nicht
  /// pauschal übersprungen. `shouldDisplay` nimmt zusätzlich die als
  /// Hidden/NoView markierten heraus.
  private static func hasVisibleAnnotation(_ page: PDFPage) -> Bool {
    page.annotations.contains { annotation in
      guard annotation.shouldDisplay else { return false }
      switch annotation.type {
      case "Popup": return false
      case "Link": return (annotation.border?.lineWidth ?? 0) > 0
      default: return true
      }
    }
  }

  /// Die Box, die eine neu gezeichnete Seite braucht: die Media-Box aufrecht
  /// gestellt, weil `draw(with:to:)` die Seite so übergibt, wie ein Leser sie
  /// sieht, der `/Rotate`-Eintrag selbst aber nicht ins neue Dokument
  /// hinüberkommt.
  private static func mediaBox(of page: PDFPage) -> CGRect? {
    let bounds = page.bounds(for: .mediaBox)
    guard bounds.width.isFinite, bounds.height.isFinite,
      bounds.width >= 1, bounds.height >= 1,
      bounds.width <= maxPageSide, bounds.height <= maxPageSide
    else { return nil }
    let rotation = ((page.rotation % 360) + 360) % 360
    let upright =
      (rotation == 90 || rotation == 270)
      ? CGSize(width: bounds.height, height: bounds.width)
      : bounds.size
    return CGRect(origin: .zero, size: upright)
  }
}
