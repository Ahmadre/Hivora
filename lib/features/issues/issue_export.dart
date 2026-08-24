import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// One exported issue, with every field pre-resolved to a display string so the
/// CSV / JSON / PDF builders stay dumb (no model or i18n lookups here).
typedef IssueExportRow = ({
  String id,
  String title,
  String status,
  String priority,
  String assignee,
  String project,
  String type,
  String due,
});

/// A group of rows under an optional heading. When the view isn't grouped the
/// export holds a single group with an empty [title].
typedef IssueExportGroup = ({String title, List<IssueExportRow> rows});

/// Localised chrome strings for the PDF (title, headers, footer). Resolved by
/// the caller (which has a BuildContext) so the export builders stay i18n-free.
typedef IssueExportLabels = ({
  String reportTitle,
  String issuesCount, // already substituted, e.g. "12 issues" / "12 Aufgaben"
  String generatedPrefix,
  String pageLabel,
  String colId,
  String colTitle,
  String colStatus,
  String colPriority,
  String colAssignee,
  String colDue,
});

/// Everything needed to render the issues export in any format.
class IssueExportData {
  IssueExportData({
    required this.orgName,
    required this.scopeLabel,
    required this.generatedAt,
    required this.groups,
    required this.grouped,
    required this.labels,
    required this.locale,
    this.groupByLabel,
    this.filterSummary = const [],
    this.logoBytes,
  });

  /// Active app locale (e.g. 'de', 'en') — used to localize the generated date,
  /// keeping the PDF fully in the user's language like the rest of its chrome.
  final String locale;

  /// Localised chrome strings for the PDF export.
  final IssueExportLabels labels;

  final String orgName;

  /// What the list is scoped to (a project name, or "All projects").
  final String scopeLabel;
  final DateTime generatedAt;

  /// Issue rows bucketed into groups. Always at least one group.
  final List<IssueExportGroup> groups;

  /// Whether grouping is active (drives the extra CSV column + PDF subheaders).
  final bool grouped;

  /// Localised "Group by: X" label, when grouped.
  final String? groupByLabel;

  /// Localised lines describing the active filters / time range, for the header.
  final List<String> filterSummary;

  /// Organization logo as ready-to-embed raster bytes (PNG/JPEG). SVG logos are
  /// rasterized before this point.
  final Uint8List? logoBytes;

  int get totalIssues => groups.fold<int>(0, (sum, g) => sum + g.rows.length);
}

// ─────────────────────────── CSV ──────────────────────────────────────────

String _csvEsc(String s) {
  var v = s;
  // Defuse CSV/spreadsheet formula injection: a cell that starts with =, +, -,
  // @, tab or CR is evaluated as a formula by Excel/LibreOffice. Issue titles,
  // names and project names are user-controlled, so prefix such cells with a
  // single quote to force them to plain text.
  if (v.isNotEmpty && '=+-@\t\r'.contains(v[0])) {
    v = "'$v";
  }
  return (v.contains(',') || v.contains('"') || v.contains('\n'))
      ? '"${v.replaceAll('"', '""')}"'
      : v;
}

String buildIssuesCsv(IssueExportData data) {
  final buf = StringBuffer();
  final header = [
    'id',
    'title',
    'status',
    'priority',
    'assignee',
    'project',
    'type',
    'due',
    if (data.grouped) 'group',
  ];
  buf.writeln(header.join(','));
  for (final group in data.groups) {
    for (final r in group.rows) {
      final cells = [
        r.id,
        r.title,
        r.status,
        r.priority,
        r.assignee,
        r.project,
        r.type,
        r.due,
        if (data.grouped) group.title,
      ];
      buf.writeln(cells.map(_csvEsc).join(','));
    }
  }
  return buf.toString();
}

// ─────────────────────────── JSON ─────────────────────────────────────────

String buildIssuesJson(IssueExportData data) {
  Map<String, dynamic> rowJson(IssueExportRow r, String group) => {
    'id': r.id,
    'title': r.title,
    'status': r.status,
    'priority': r.priority,
    'assignee': r.assignee,
    'project': r.project,
    'type': r.type,
    'due': r.due,
    if (data.grouped) 'group': group,
  };

  final out = {
    'scope': data.scopeLabel,
    'generatedAt': data.generatedAt.toUtc().toIso8601String(),
    'total': data.totalIssues,
    if (data.grouped && data.groupByLabel != null)
      'groupedBy': data.groupByLabel,
    if (data.filterSummary.isNotEmpty) 'filters': data.filterSummary,
    'issues': [
      for (final group in data.groups)
        for (final r in group.rows) rowJson(r, group.title),
    ],
  };
  return const JsonEncoder.withIndent('  ').convert(out);
}

// ─────────────────────────── PDF ──────────────────────────────────────────

const _navy = PdfColor.fromInt(0xFF2D2B55);
const _ink = PdfColor.fromInt(0xFF23223F);
const _inkSoft = PdfColor.fromInt(0xFF6B6A85);
const _inkFaint = PdfColor.fromInt(0xFF9A99B0);
const _canvas2 = PdfColor.fromInt(0xFFEFEEE8);
const _hairline = PdfColor.fromInt(0xFFE7E5DE);

const _hinataMarkSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120">'
    '<g fill="none" stroke="#D9A032" stroke-width="11" '
    'stroke-linecap="round" stroke-linejoin="round">'
    '<path d="M60 14 99.8 37v46L60 106 20.2 83V37Z"/>'
    '<path d="M20.2 60h79.6"/></g></svg>';

/// Builds the issues PDF and hands it to the platform (browser download on web,
/// share sheet on mobile/desktop) via the printing plugin.
Future<void> shareIssuesPdf(IssueExportData data) async {
  final doc = await _buildDocument(data);
  final stamp = data.generatedAt.toIso8601String().substring(0, 10);
  final safeScope = _slug(data.scopeLabel);
  // Issued by the organization, like the report export beside it: the masthead
  // already carries their logo, so the filename and metadata follow.
  final safeOrg = _slug(data.orgName);
  final prefix = safeOrg.isEmpty ? 'issues' : '$safeOrg-issues';
  await Printing.sharePdf(
    bytes: await doc.save(),
    filename: '$prefix-${safeScope.isEmpty ? 'all' : safeScope}-$stamp.pdf',
  );
}

/// Filesystem- and PDF-metadata-safe form of an arbitrary display name.
String _slug(String value) => value
    .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

Future<pw.Document> _buildDocument(IssueExportData data) async {
  final org = data.orgName.trim().isEmpty ? 'Hinata' : data.orgName.trim();
  final doc = pw.Document(
    title: '$org · Issues',
    author: org,
    creator: 'Hinata',
  );
  final df = _fmtDate(data.generatedAt, data.locale);
  final logo = data.logoBytes == null
      ? null
      : pw.Image(pw.MemoryImage(data.logoBytes!), fit: pw.BoxFit.contain);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 40),
      build: (context) => [
        _header(data, df, logo),
        pw.SizedBox(height: 18),
        if (data.filterSummary.isNotEmpty) ...[
          _filterChips(data),
          pw.SizedBox(height: 16),
        ],
        for (final group in data.groups) ..._groupBlock(data, group),
      ],
      footer: (context) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 10),
        child: pw.Text(
          'Hinata · ${data.labels.pageLabel} '
          '${context.pageNumber}/${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 9, color: _inkFaint),
        ),
      ),
    ),
  );
  return doc;
}

pw.Widget _header(IssueExportData data, String generated, pw.Widget? logo) {
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
                data.labels.reportTitle,
                style: const pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                '${data.scopeLabel} · ${data.labels.issuesCount}',
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
              '${data.labels.generatedPrefix} $generated',
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

pw.Widget _filterChips(IssueExportData data) {
  return pw.Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final f in data.filterSummary)
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: const pw.BoxDecoration(
            color: _canvas2,
            borderRadius: pw.BorderRadius.all(pw.Radius.circular(20)),
          ),
          child: pw.Text(
            f,
            style: const pw.TextStyle(fontSize: 9, color: _inkSoft),
          ),
        ),
    ],
  );
}

List<pw.Widget> _groupBlock(IssueExportData data, IssueExportGroup group) {
  return [
    if (data.grouped)
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 4, bottom: 8),
        child: pw.Row(
          children: [
            pw.Text(
              group.title,
              style: const pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: _ink,
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Text(
              '${group.rows.length}',
              style: const pw.TextStyle(fontSize: 11, color: _inkFaint),
            ),
          ],
        ),
      ),
    _table(group.rows, data.labels),
    pw.SizedBox(height: 16),
  ];
}

pw.Widget _table(List<IssueExportRow> rows, IssueExportLabels labels) {
  pw.Widget cell(
    String text, {
    bool header = false,
    pw.TextAlign align = pw.TextAlign.left,
  }) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
    child: pw.Text(
      text,
      textAlign: align,
      maxLines: 2,
      overflow: pw.TextOverflow.clip,
      style: pw.TextStyle(
        fontSize: header ? 8.5 : 9.5,
        fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
        color: header ? _inkSoft : _ink,
        letterSpacing: header ? 0.4 : 0,
      ),
    ),
  );

  const widths = {
    0: pw.FlexColumnWidth(1.2), // ID
    1: pw.FlexColumnWidth(4.2), // Title
    2: pw.FlexColumnWidth(1.8), // Status
    3: pw.FlexColumnWidth(1.4), // Priority
    4: pw.FlexColumnWidth(2.2), // Assignee
    5: pw.FlexColumnWidth(1.1), // Due
  };

  return pw.Table(
    columnWidths: widths,
    border: const pw.TableBorder(
      bottom: pw.BorderSide(color: _hairline, width: 0.6),
      horizontalInside: pw.BorderSide(color: _hairline, width: 0.6),
    ),
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _canvas2),
        children: [
          cell(labels.colId, header: true),
          cell(labels.colTitle, header: true),
          cell(labels.colStatus, header: true),
          cell(labels.colPriority, header: true),
          cell(labels.colAssignee, header: true),
          cell(labels.colDue, header: true, align: pw.TextAlign.right),
        ],
      ),
      for (final r in rows)
        pw.TableRow(
          children: [
            cell(r.id),
            cell(r.title),
            cell(r.status),
            cell(r.priority),
            cell(r.assignee),
            cell(r.due, align: pw.TextAlign.right),
          ],
        ),
    ],
  );
}

String _fmtDate(DateTime d, String locale) {
  // Localized month + 24h time in the app locale (e.g. "19. Juli 2026 · 14:05"
  // in German), instead of a hardcoded English month array.
  final date = DateFormat.yMMMd(locale).format(d);
  final time = DateFormat.Hm(locale).format(d);
  return '$date · $time';
}
