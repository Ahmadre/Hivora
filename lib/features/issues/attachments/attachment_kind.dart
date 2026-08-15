import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';

/// Visual + semantic metadata for an attachment "kind", mirroring `KIND_META`
/// in the web design (`view_attachments.jsx`). Colours are sRGB approximations
/// of the reference oklch values.
class AttachmentKindMeta {
  const AttachmentKindMeta(this.icon, this.color);
  final IconData icon;
  final Color color;
}

const Map<String, AttachmentKindMeta> _kindMeta = {
  'image': AttachmentKindMeta(LucideIcons.image, Color(0xFF4F74B8)),
  'pdf': AttachmentKindMeta(LucideIcons.fileText, Color(0xFFC1503C)),
  'doc': AttachmentKindMeta(LucideIcons.fileText, Color(0xFF5566A8)),
  'sheet': AttachmentKindMeta(LucideIcons.table, Color(0xFF3E9168)),
  'zip': AttachmentKindMeta(LucideIcons.folderArchive, Color(0xFFB07F38)),
  'figma': AttachmentKindMeta(LucideIcons.paintbrush, Color(0xFF9A57BE)),
  'video': AttachmentKindMeta(LucideIcons.film, Color(0xFFBE5479)),
  'file': AttachmentKindMeta(LucideIcons.file, Color(0xFF7B7E88)),
};

AttachmentKindMeta kindMeta(String kind) =>
    _kindMeta[kind] ?? _kindMeta['file']!;

bool kindIsImage(String kind) => kind == 'image';

bool kindIsPdf(String kind) => kind == 'pdf';

/// Whether the server can render a thumbnail for this kind: pictures, and PDFs
/// (of which it rasterizes the first page). Everything else — Office documents,
/// archives, plain text — has no page to draw and keeps its file-type glyph, so
/// asking for a preview would only cost a request that answers 404.
bool kindHasPreview(String kind) => kindIsImage(kind) || kindIsPdf(kind);

/// Largest text file we fetch and render inline. Bigger files fall back to the
/// type card so a huge blob is never pulled into memory just for a preview.
const int kMaxTextPreviewBytes = 2 * 1024 * 1024;

/// Largest *unknown* file we're willing to download just to find out whether it
/// is text (see [AttachmentPreviewKind.maybeText]). Much tighter than
/// [kMaxTextPreviewBytes]: this budget is spent on a guess, not on a request the
/// file type already justified.
const int kMaxTextSniffBytes = 512 * 1024;

/// Extensions we can render inline as plain text. Deliberately broad — the
/// viewer renders every one of them as *inert plain text* (never as markup, a
/// document or a script), so listing a type here only ever means "show the
/// characters", and a superset costs nothing while covering the code, config
/// and log files people actually attach.
const Set<String> kTextPreviewExtensions = {
  // plain text, logs, docs
  'txt', 'text', 'log', 'out', 'err', 'md', 'markdown', 'mdx', 'rst', 'adoc',
  'tex', 'bib', 'srt', 'vtt', 'diff', 'patch', 'readme', 'license',
  // structured data
  'json', 'jsonc', 'json5', 'geojson', 'ndjson', 'jsonl', 'csv', 'tsv', 'xml',
  'plist', 'yaml', 'yml', 'toml', 'ini', 'cfg', 'conf', 'config', 'properties',
  'env', 'lock', 'sum', 'graphql', 'gql', 'proto', 'sql', 'ipynb',
  // web
  'html', 'htm', 'xhtml', 'css', 'scss', 'sass', 'less', 'vue', 'svelte',
  // code
  'dart', 'js', 'mjs', 'cjs', 'ts', 'tsx', 'jsx', 'java', 'kt', 'kts', 'swift',
  'm', 'mm', 'c', 'h', 'cc', 'cpp', 'hpp', 'cs', 'go', 'rs', 'rb', 'py', 'pyi',
  'php', 'pl', 'lua', 'r', 'scala', 'groovy', 'gradle', 'sh', 'bash', 'zsh',
  'fish', 'ps1', 'bat', 'cmd', 'mk', 'cmake', 'tf', 'tfvars', 'hcl', 'nix',
  'dockerfile', 'makefile', 'gitignore', 'gitattributes', 'editorconfig',
};

/// `application/…` types that are text despite not saying `text/`.
const Set<String> _kTextApplicationMimes = {
  'application/json',
  'application/ld+json',
  'application/xml',
  'application/xhtml+xml',
  'application/javascript',
  'application/x-javascript',
  'application/x-sh',
  'application/x-yaml',
  'application/yaml',
  'application/toml',
  'application/csv',
  'application/sql',
  'application/x-ndjson',
};

/// The file name's lowercase extension, or the whole (lowercased) name for
/// extensionless files like `Dockerfile` / `Makefile` — which is exactly how
/// [kTextPreviewExtensions] lists them.
String fileExtension(String name) {
  final base = name.split('/').last.split(r'\').last.toLowerCase();
  final dot = base.lastIndexOf('.');
  if (dot <= 0 || dot == base.length - 1) return base;
  return base.substring(dot + 1);
}

/// Whether [name]/[mime] is previewable as plain text inline. Switches on MIME
/// first (covers `text/*`, the JSON/XML families and their `+json` / `+xml`
/// suffixes), then falls back to the extension — the declared type is often
/// just `application/octet-stream` for anything the OS has no mapping for.
bool isTextPreviewable(String name, [String? mime]) {
  final m = mime?.toLowerCase().split(';').first.trim();
  if (m != null && m.isNotEmpty) {
    if (m.startsWith('text/')) return true;
    if (_kTextApplicationMimes.contains(m)) return true;
    if (m.startsWith('application/') &&
        (m.endsWith('+json') || m.endsWith('+xml'))) {
      return true;
    }
  }
  return kTextPreviewExtensions.contains(fileExtension(name));
}

/// How an attachment is shown on the viewer's stage.
enum AttachmentPreviewKind {
  image,
  pdf,

  /// A type we know is text — rendered in the text viewer.
  text,

  /// A type we don't recognise, small enough to fetch and look at: rendered as
  /// text when the bytes actually *are* text, and as the type card when they
  /// aren't. This is what makes extensionless files (`Dockerfile`, `LICENSE`)
  /// and anything the OS typed as `application/octet-stream` readable.
  maybeText,

  /// Nothing to render inline — the type card explains why.
  none,
}

/// Picks the stage renderer for an attachment. [size] is the file size in
/// bytes; text previews are capped so one large attachment can't stall the app.
AttachmentPreviewKind previewKindFor({
  required String kind,
  required String name,
  required int size,
  String? mime,
}) {
  if (kindIsImage(kind)) return AttachmentPreviewKind.image;
  if (kindIsPdf(kind)) return AttachmentPreviewKind.pdf;
  if (isTextPreviewable(name, mime)) {
    return size <= kMaxTextPreviewBytes
        ? AttachmentPreviewKind.text
        : AttachmentPreviewKind.none;
  }
  // Unknown type: worth a look, but only a small one.
  if (kind == 'file' && size > 0 && size <= kMaxTextSniffBytes) {
    return AttachmentPreviewKind.maybeText;
  }
  return AttachmentPreviewKind.none;
}

/// Whether [bytes] look like text rather than a binary blob — the check behind
/// [AttachmentPreviewKind.maybeText]. Mirrors what `file(1)` and Git do: a NUL
/// byte means binary, and so does a high share of other control characters.
/// Only the head of the file is probed, so the cost is independent of its size.
bool looksLikeText(Uint8List bytes) {
  if (bytes.isEmpty) return false;
  final probe = bytes.length > 4096 ? 4096 : bytes.length;
  var control = 0;
  for (var i = 0; i < probe; i++) {
    final b = bytes[i];
    if (b == 0) return false;
    // Everything outside tab/LF/CR/FF and the printable range.
    if (b < 0x09 || (b > 0x0D && b < 0x20) || b == 0x7F) control++;
  }
  return control / probe < 0.05;
}

/// Mirrors `kindFromName()`: switch on MIME first, then file extension.
String kindFromName(String name, [String? mime]) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  if ((mime != null && mime.startsWith('image/')) ||
      const [
        'png',
        'jpg',
        'jpeg',
        'gif',
        'webp',
        'svg',
        'heic',
      ].contains(ext)) {
    return 'image';
  }
  if ((mime != null && mime.startsWith('video/')) ||
      const ['mp4', 'mov', 'webm', 'avi'].contains(ext)) {
    return 'video';
  }
  if (ext == 'pdf') return 'pdf';
  if (const ['doc', 'docx', 'rtf', 'txt', 'md', 'pages'].contains(ext)) {
    return 'doc';
  }
  if (const ['xls', 'xlsx', 'csv', 'numbers'].contains(ext)) return 'sheet';
  if (const ['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) return 'zip';
  if (const ['fig', 'sketch', 'xd'].contains(ext)) return 'figma';
  return 'file';
}

/// The short tag shown on the thumbnail: the extension for images, else the kind.
String kindTag(String kind, String name) {
  if (kind == 'image') {
    return name.contains('.') ? name.split('.').last : 'img';
  }
  return kind;
}

/// Human-readable size, mirroring `fmtSize()` (B / KB / MB).
String formatBytes(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) {
    return '${(b / 1024).toStringAsFixed(b < 10240 ? 1 : 0)} KB';
  }
  return '${(b / 1048576).toStringAsFixed(b < 10485760 ? 1 : 0)} MB';
}

/// Localized compact relative age, e.g. "now", "5m ago", "3d ago" — mirrors the
/// design's "Xd ago" sublabel via the app's i18n so the German build reads
/// "vor 3 T." instead of a hardcoded English fragment.
String relativeAgeLabel(BuildContext context, DateTime when) {
  final d = DateTime.now().difference(when);
  String t(String key, [int? n]) => context.t(
    'issues.attachments.$key',
    variables: n == null ? const {} : {'n': n},
  );
  if (d.inSeconds < 45) return t('ageNow');
  if (d.inMinutes < 60) return t('ageMinutes', d.inMinutes);
  if (d.inHours < 24) return t('ageHours', d.inHours);
  if (d.inDays < 7) return t('ageDays', d.inDays);
  if (d.inDays < 30) return t('ageWeeks', (d.inDays / 7).floor());
  if (d.inDays < 365) return t('ageMonths', (d.inDays / 30).floor());
  return t('ageYears', (d.inDays / 365).floor());
}

/// Extensions that are clearly executable / scriptable. Rejected client-side
/// with a friendly message; the server whitelist of MIME types is the real
/// gate (these never appear in it), this just avoids a wasted round-trip.
const Set<String> kBlockedExtensions = {
  'exe',
  'msi',
  'bat',
  'cmd',
  'com',
  'scr',
  'pif',
  'cpl',
  'dll',
  'sys',
  'sh',
  'bash',
  'zsh',
  'ksh',
  'run',
  'bin',
  'app',
  'command',
  'js',
  'jse',
  'vbs',
  'vbe',
  'wsf',
  'wsh',
  'ps1',
  'psm1',
  'hta',
  'jar',
  'apk',
  'deb',
  'rpm',
  'dmg',
  'pkg',
  'reg',
  'lnk',
  'gadget',
  'inf',
  'ade',
  'adp',
  'mst',
};

bool isBlockedFileName(String name) {
  if (!name.contains('.')) return false;
  return kBlockedExtensions.contains(name.split('.').last.toLowerCase());
}
