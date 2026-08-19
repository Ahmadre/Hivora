part of 'issue_detail_sheet.dart';

// ─────────────────────────── Export ────────────────────────────────────────

/// What the export submenu offers: printing, and the four file formats the
/// server renders.
///
/// Printing is not a fifth format. It fetches the same PDF the PDF entry
/// downloads and hands it to the platform's print dialog, so a printed issue
/// and a saved one can never show different things — they are the same bytes.
enum IssueExportChoice {
  print(null, null),
  pdf('pdf', 'application/pdf'),
  xlsx(
    'xlsx',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  ),
  docx(
    'docx',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  ),
  xml('xml', 'application/xml');

  const IssueExportChoice(this.extension, this.mimeType);

  /// The URL suffix and the file extension; null for [print], which has neither.
  final String? extension;
  final String? mimeType;

  /// The i18n key of the row's label.
  String get labelKey => 'issues.export.$name';
}

/// The icons of the submenu, in its order. Deliberately the same glyphs the
/// issue-list toolbar already uses for its own export menu, so the two menus
/// do not name the same formats with different pictures.
const Map<IssueExportChoice, IconData> _kExportIcons = {
  IssueExportChoice.print: LucideIcons.printer,
  IssueExportChoice.pdf: LucideIcons.fileText,
  IssueExportChoice.xlsx: LucideIcons.table,
  IssueExportChoice.docx: LucideIcons.fileType,
  IssueExportChoice.xml: LucideIcons.braces,
};

/// Opens the export submenu where the "…" menu just stood.
///
/// A second popover rather than a nested menu: [GlassPopupMenu] closes on
/// selection and has no submenu of its own, and this is the same shape the
/// watch row already uses for the one other action that opens something
/// further.
Future<IssueExportChoice?> showIssueExportMenu(
  BuildContext context, {
  required Rect anchorRect,
}) {
  return showGlassOptions<IssueExportChoice>(
    context,
    title: context.t('issues.export.title'),
    anchorRect: anchorRect,
    options: [
      for (final choice in IssueExportChoice.values)
        (
          value: choice,
          child: Row(
            children: [
              Icon(_kExportIcons[choice], size: 16, color: AppColors.inkSoft),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.t(choice.labelKey),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

/// Fetches one rendered export of [issueId] from the server.
///
/// The server owns what an export contains and what it is called; this only
/// asks for a format. A failure arrives as an [ApiFailure] carrying the
/// server's own message — a refusal and a rate limit read differently to the
/// person who pressed the button, and both are better than "something went
/// wrong".
Future<Uint8List> fetchIssueExport(
  ApiClient api,
  String issueId,
  String extension,
) {
  return api.getFileBytes(
    '/api/v1/issues/$issueId/export.$extension',
    // Laying out a document takes longer than answering with a row, and the
    // default receive window is sized for the latter.
    receiveTimeout: const Duration(seconds: 60),
  );
}

/// The download's file name, mirroring what the server puts in
/// `Content-Disposition` — the byte fetch does not surface response headers,
/// and the list export names its files the same way.
String issueExportFileName(Issue issue, String extension) {
  final stem = '${issue.readableId} ${issue.title}'
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final safe = stem.isEmpty ? 'issue' : stem;
  return '${safe.length > 80 ? safe.substring(0, 80).replaceAll(RegExp(r'-+$'), '') : safe}.$extension';
}
