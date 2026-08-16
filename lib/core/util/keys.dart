/// Project / team key suggestions.
///
/// A key is the short, loud identifier a project or team is known by — it
/// prefixes every issue id (`HIN-42`), so it has to be short, typeable and
/// unique. The server accepts `[A-Z][A-Z0-9]{1,9}`: two to ten characters,
/// starting with a letter.
///
/// Nobody should have to invent one. These helpers derive a key from the name
/// the user just typed, the way people pick them by hand: initials for a
/// multi-word name ("Board Views" → `BV`), the opening letters for a single
/// word ("Hinata" → `HIN`).
library;

/// Longest key the server accepts.
const int kMaxKeyLength = 10;

/// Shortest key the server accepts.
const int kMinKeyLength = 2;

/// Letters that carry meaning in German (and most Latin-script) names but are
/// not in `[A-Z0-9]`. Expanded rather than dropped, so "Öffentlichkeit" starts
/// an `OEF` key instead of an `FFE` one.
const Map<String, String> _transliterations = {
  'Ä': 'AE',
  'Ö': 'OE',
  'Ü': 'UE',
  'ß': 'SS',
  'À': 'A',
  'Á': 'A',
  'Â': 'A',
  'Ã': 'A',
  'Å': 'A',
  'Æ': 'AE',
  'Ç': 'C',
  'È': 'E',
  'É': 'E',
  'Ê': 'E',
  'Ë': 'E',
  'Ì': 'I',
  'Í': 'I',
  'Î': 'I',
  'Ï': 'I',
  'Ñ': 'N',
  'Ò': 'O',
  'Ó': 'O',
  'Ô': 'O',
  'Õ': 'O',
  'Ø': 'O',
  'Ù': 'U',
  'Ú': 'U',
  'Û': 'U',
  'Ý': 'Y',
  'Þ': 'TH',
  'Đ': 'D',
  'Ł': 'L',
  'Š': 'S',
  'Ž': 'Z',
  'Ć': 'C',
  'Č': 'C',
  'Ę': 'E',
  'Ą': 'A',
};

/// The words of [name], uppercased and reduced to `[A-Z0-9]`.
List<String> _words(String name) {
  final buffer = StringBuffer();
  for (final char in name.toUpperCase().split('')) {
    buffer.write(_transliterations[char] ?? char);
  }
  return buffer
      .toString()
      .split(RegExp('[^A-Z0-9]+'))
      .where((w) => w.isNotEmpty)
      .toList();
}

/// Suggests a key for [name], avoiding everything in [taken]
/// (case-insensitive).
///
/// Returns an empty string when [name] holds nothing a key can be built from —
/// the caller should then leave the field alone rather than write a placeholder
/// the server would reject.
String suggestKey(
  String name, {
  Set<String> taken = const {},
  int maxLength = kMaxKeyLength,
}) {
  final base = _base(name, maxLength);
  if (base.isEmpty) return '';
  final used = taken.map((k) => k.toUpperCase()).toSet();
  if (!used.contains(base)) return base;
  // Occupied: hang a number off it, trimming the stem so the key stays legal.
  for (var n = 2; n < 100; n++) {
    final suffix = '$n';
    final stem = base.length + suffix.length > maxLength
        ? base.substring(0, maxLength - suffix.length)
        : base;
    final candidate = '$stem$suffix';
    if (candidate.length >= kMinKeyLength && !used.contains(candidate)) {
      return candidate;
    }
  }
  return '';
}

/// The un-deduplicated suggestion: initials for several words, the opening
/// letters for one.
String _base(String name, int maxLength) {
  final words = _words(name);
  if (words.isEmpty) return '';
  final letters = words.join();

  var candidate = words.length >= 2
      // "Asta Kultur Referat" → AKR. Four initials is already a mouthful.
      ? words.take(4).map((w) => w[0]).join()
      // "Hinata" → HIN.
      : words.first.substring(
          0,
          words.first.length < 3 ? words.first.length : 3,
        );

  // The first character must be a letter, and the whole thing at least two
  // characters long — top it up from the name's own letters before giving up.
  candidate = candidate.replaceFirst(RegExp('^[0-9]+'), '');
  if (candidate.length < kMinKeyLength) {
    final pool = letters.replaceFirst(RegExp('^[0-9]+'), '');
    if (pool.length < kMinKeyLength) return '';
    candidate = pool.substring(0, kMinKeyLength);
  }
  return candidate.length > maxLength
      ? candidate.substring(0, maxLength)
      : candidate;
}

/// Whether [key] is exactly what [name] would have generated — i.e. it is still
/// the automatic key and nobody has made it their own. Callers use this to
/// decide whether a key may keep following the name as it is edited.
bool isGeneratedKey(String key, String name, {int maxLength = kMaxKeyLength}) {
  if (key.isEmpty) return true;
  return key.toUpperCase() == _base(name, maxLength);
}
