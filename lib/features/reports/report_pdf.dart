import 'dart:typed_data';

import 'package:flutter/material.dart' show Color;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// A single labelled bar row inside a distribution section.
typedef PdfDatum = ({String label, int value, String display, Color color});

/// One distribution block (e.g. "Issues by state").
typedef PdfSection = ({String title, List<PdfDatum> rows});

/// Everything needed to render the report document.
///
/// String fields here arrive pre-localized from the caller (a [BuildContext]
/// isn't available inside this pure pdf-widgets module), except
/// [pageFooterTemplate], which carries literal `{page}`/`{pages}` tokens
/// substituted at render time since the page count isn't known until then.
class ReportPdfData {
  ReportPdfData({
    required this.orgName,
    required this.projectName,
    required this.generatedAt,
    required this.generatedAtLabel,
    required this.totalIssues,
    required this.sections,
    required this.burndown,
    required this.burndownRemaining,
    required this.pdfTitleLabel,
    required this.totalIssuesLabel,
    required this.openLast30DaysLabel,
    required this.breakdownsLabel,
    required this.burndownTitleLabel,
    required this.openRemainingLabel,
    required this.noDataLabel,
    required this.axis30dLabel,
    required this.axisTodayLabel,
    required this.pageFooterTemplate,
    this.logoBytes,
  });

  final String orgName;

  /// Organization logo as ready-to-embed raster bytes (PNG/JPEG). SVG logos are
  /// rasterized before this point. Rendered in the header when present;
  /// otherwise the Hinata wordmark + hex mark is shown.
  final Uint8List? logoBytes;
  final String projectName;
  final DateTime generatedAt;

  /// Locale-formatted `"Generated <date>"` label for the header.
  final String generatedAtLabel;
  final int totalIssues;
  final List<PdfSection> sections;
  // (dayIndex, remaining, ideal) — empty when no trend data is available.
  final List<({int day, double remaining, double ideal})> burndown;
  final int burndownRemaining;

  final String pdfTitleLabel;
  final String totalIssuesLabel;
  final String openLast30DaysLabel;
  final String breakdownsLabel;
  final String burndownTitleLabel;
  final String openRemainingLabel;
  final String noDataLabel;
  final String axis30dLabel;
  final String axisTodayLabel;
  final String pageFooterTemplate;
}

PdfColor _c(Color c) => PdfColor.fromInt(c.toARGB32());

/// The Hinata hex signet (pointy-top hexagon + centre bar), amber stroke.
/// Tiny and simple, so it always renders in the PDF SVG engine — used as the
/// branding fallback when no org logo is configured/available.
const _hinataMarkSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120">'
    '<g fill="none" stroke="#D9A032" stroke-width="11" '
    'stroke-linecap="round" stroke-linejoin="round">'
    '<path d="M60 14 99.8 37v46L60 106 20.2 83V37Z"/>'
    '<path d="M20.2 60h79.6"/></g></svg>';

const _navy = PdfColor.fromInt(0xFF2D2B55);
const _ink = PdfColor.fromInt(0xFF23223F);
const _inkSoft = PdfColor.fromInt(0xFF6B6A85);
const _inkFaint = PdfColor.fromInt(0xFF9A99B0);
const _accentStrong = PdfColor.fromInt(0xFFB9831F);
const _canvas2 = PdfColor.fromInt(0xFFEFEEE8);
const _hairline = PdfColor.fromInt(0xFFE7E5DE);

/// Builds the report PDF and hands it to the platform (browser download on
/// web, share sheet on mobile/desktop) via the printing plugin.
Future<void> shareReportPdf(ReportPdfData data) async {
  final doc = await _buildDocument(data);
  final stamp = data.generatedAt.toIso8601String().substring(0, 10);
  final safeProject = _slug(data.projectName);
  // The document is issued by the organization — its masthead already carries
  // their logo, so the filename and the PDF metadata beneath it should not
  // still say ours.
  final safeOrg = _slug(data.orgName);
  final prefix = safeOrg.isEmpty ? 'report' : '$safeOrg-report';
  await Printing.sharePdf(
    bytes: await doc.save(),
    filename: '$prefix-$safeProject-$stamp.pdf',
  );
}

/// Filesystem- and PDF-metadata-safe form of an arbitrary display name.
String _slug(String value) => value
    .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

Future<pw.Document> _buildDocument(ReportPdfData data) async {
  final org = data.orgName.trim().isEmpty ? 'Hinata' : data.orgName.trim();
  final doc = pw.Document(
    title: '$org · ${data.projectName}',
    author: org,
    creator: 'Hinata',
  );

  final logo = data.logoBytes == null
      ? null
      : pw.Image(pw.MemoryImage(data.logoBytes!), fit: pw.BoxFit.contain);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 40),
      build: (context) => [
        _header(data, logo),
        pw.SizedBox(height: 22),
        _summaryRow(data),
        pw.SizedBox(height: 22),
        if (data.burndown.length >= 2) ...[
          _burndownSection(data),
          pw.SizedBox(height: 22),
        ],
        ...data.sections.map((s) => _distributionSection(s, data.noDataLabel)),
      ],
      footer: (context) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 10),
        child: pw.Text(
          data.pageFooterTemplate
              .replaceAll('{page}', '${context.pageNumber}')
              .replaceAll('{pages}', '${context.pagesCount}'),
          style: const pw.TextStyle(fontSize: 9, color: _inkFaint),
        ),
      ),
    ),
  );
  return doc;
}

pw.Widget _header(ReportPdfData data, pw.Widget? logo) {
  // The org logo is rendered inside the navy band, in the same top-left slot
  // the Hinata wordmark fallback occupies.
  return pw.Container(
    padding: const pw.EdgeInsets.all(20),
    decoration: const pw.BoxDecoration(
      color: _navy,
      borderRadius: pw.BorderRadius.all(pw.Radius.circular(12)),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (logo != null)
                pw.ConstrainedBox(
                  constraints: const pw.BoxConstraints(
                    maxHeight: 36,
                    maxWidth: 240,
                  ),
                  child: pw.FittedBox(
                    fit: pw.BoxFit.contain,
                    alignment: pw.Alignment.centerLeft,
                    child: logo,
                  ),
                )
              else
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.SizedBox(
                      width: 26,
                      height: 26,
                      child: pw.SvgImage(svg: _hinataMarkSvg),
                    ),
                    pw.SizedBox(width: 9),
                    pw.Text(
                      'hinata',
                      style: const pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 19,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              pw.SizedBox(height: 10),
              pw.Text(
                data.pdfTitleLabel,
                style: const pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                data.projectName,
                style: const pw.TextStyle(
                  color: PdfColor.fromInt(0xFFC9C7E0),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              data.orgName,
              style: const pw.TextStyle(color: PdfColors.white, fontSize: 11),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              data.generatedAtLabel,
              style: const pw.TextStyle(
                color: PdfColor.fromInt(0xFF807EA0),
                fontSize: 9,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

pw.Widget _summaryRow(ReportPdfData data) {
  pw.Widget stat(String value, String label) => pw.Expanded(
    child: pw.Container(
      padding: const pw.EdgeInsets.all(16),
      margin: const pw.EdgeInsets.only(right: 12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _hairline),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            value,
            style: const pw.TextStyle(
              fontSize: 26,
              fontWeight: pw.FontWeight.bold,
              color: _ink,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 10, color: _inkSoft),
          ),
        ],
      ),
    ),
  );

  return pw.Row(
    children: [
      stat('${data.totalIssues}', data.totalIssuesLabel),
      stat('${data.burndownRemaining}', data.openLast30DaysLabel),
      stat('${data.sections.length}', data.breakdownsLabel),
    ],
  );
}

pw.Widget _sectionTitle(String title) => pw.Padding(
  padding: const pw.EdgeInsets.only(bottom: 10),
  child: pw.Text(
    title,
    style: const pw.TextStyle(
      fontSize: 14,
      fontWeight: pw.FontWeight.bold,
      color: _ink,
    ),
  ),
);

pw.Widget _burndownSection(ReportPdfData data) {
  final maxY = data.burndown
      .map((p) => p.remaining > p.ideal ? p.remaining : p.ideal)
      .fold<double>(1, (m, v) => v > m ? v : m);
  final lastDay = (data.burndown.length - 1).toDouble();

  return pw.Container(
    padding: const pw.EdgeInsets.all(16),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: _hairline),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              data.burndownTitleLabel,
              style: const pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                color: _ink,
              ),
            ),
            pw.Text(
              data.openRemainingLabel,
              style: const pw.TextStyle(fontSize: 10, color: _inkSoft),
            ),
          ],
        ),
        pw.SizedBox(height: 14),
        pw.SizedBox(
          height: 200,
          child: pw.Chart(
            grid: pw.CartesianGrid(
              xAxis: pw.FixedAxis(
                [0, lastDay],
                divisions: false,
                buildLabel: (v) => pw.Text(
                  v == 0 ? data.axis30dLabel : data.axisTodayLabel,
                  style: const pw.TextStyle(fontSize: 8, color: _inkFaint),
                ),
              ),
              yAxis: pw.FixedAxis(
                [0, (maxY / 2).roundToDouble(), maxY.ceilToDouble()],
                divisions: true,
                divisionsColor: _hairline,
                textStyle: const pw.TextStyle(fontSize: 8, color: _inkFaint),
              ),
            ),
            datasets: [
              pw.LineDataSet(
                legend: 'Ideal',
                drawSurface: false,
                drawPoints: false,
                isCurved: false,
                lineWidth: 1.2,
                color: _inkFaint,
                data: [
                  for (final p in data.burndown)
                    pw.PointChartValue(p.day.toDouble(), p.ideal),
                ],
              ),
              pw.LineDataSet(
                legend: 'Remaining',
                drawSurface: false,
                drawPoints: true,
                pointSize: 2.5,
                pointColor: _accentStrong,
                isCurved: false,
                lineWidth: 2.4,
                color: _accentStrong,
                data: [
                  for (final p in data.burndown)
                    pw.PointChartValue(p.day.toDouble(), p.remaining),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

pw.Widget _distributionSection(PdfSection section, String noDataLabel) {
  final max = section.rows.isEmpty
      ? 1
      : section.rows.map((r) => r.value).reduce((a, b) => a > b ? a : b);
  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 18),
    padding: const pw.EdgeInsets.all(16),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: _hairline),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle(section.title),
        if (section.rows.isEmpty)
          pw.Text(
            noDataLabel,
            style: const pw.TextStyle(fontSize: 10, color: _inkFaint),
          )
        else
          ...section.rows.map((r) => _barRow(r, max)),
      ],
    ),
  );
}

pw.Widget _barRow(PdfDatum d, int max) {
  final frac = (max == 0 ? 0.0 : d.value / max).clamp(0.0, 1.0);
  final filled = (frac * 1000).round();
  final rest = 1000 - filled;
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 5),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.SizedBox(
          width: 130,
          child: pw.Text(
            d.label,
            maxLines: 1,
            overflow: pw.TextOverflow.clip,
            style: const pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: _ink,
            ),
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: pw.Container(
            height: 8,
            decoration: const pw.BoxDecoration(
              color: _canvas2,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Row(
              children: [
                if (filled > 0)
                  pw.Expanded(
                    flex: filled,
                    child: pw.Container(
                      decoration: pw.BoxDecoration(
                        color: _c(d.color),
                        borderRadius: const pw.BorderRadius.all(
                          pw.Radius.circular(4),
                        ),
                      ),
                    ),
                  ),
                if (rest > 0) pw.Expanded(flex: rest, child: pw.SizedBox()),
              ],
            ),
          ),
        ),
        pw.SizedBox(width: 10),
        pw.SizedBox(
          width: 60,
          child: pw.Text(
            d.display,
            textAlign: pw.TextAlign.right,
            style: const pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: _ink,
            ),
          ),
        ),
      ],
    ),
  );
}
