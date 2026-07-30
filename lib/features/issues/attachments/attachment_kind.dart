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

/// Extensions we can render inline as plain text in the lightbox. These are a
/// superset of what the server actually accepts (text/plain, text/csv,
/// application/json) so previews keep working if the whitelist grows.
const Set<String> kTextPreviewExtensions = {
  'txt',
  'text',
  'log',
  'md',
  'markdown',
  'json',
  'jsonc',
  'geojson',
  'csv',
  'tsv',
  'xml',
  'yaml',
  'yml',
  'toml',
  'ini',
  'cfg',
  'conf',
  'properties',
  'env',
  'html',
  'htm',
  'css',
};

/// Whether [name]/[mime] is previewable as plain text inline. Switches on MIME
/// first (covers text/* and application/json), then falls back to extension.
bool isTextPreviewable(String name, [String? mime]) {
  if (mime != null &&
      (mime.startsWith('text/') || mime == 'application/json')) {
    return true;
  }
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return kTextPreviewExtensions.contains(ext);
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
