import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, visibleForTesting;
import 'package:flutter_timezone/flutter_timezone.dart';

/// The IANA time zone this device is set to — `Europe/Berlin`, `Asia/Tokyo`.
///
/// It exists for the documents the **server** renders. Everything the app draws
/// itself is already right: `core/util/dates.dart` parses an instant and calls
/// `toLocal()`, which Dart answers from the operating system's own zone
/// database, per instant and daylight saving included. A PDF laid out on the
/// server has none of that context — the process runs with its clock pinned to
/// UTC so stored instants are deterministic, and an HTTP request says which
/// language the reader wants but never where they are. So the app tells it.
///
/// Why a plugin and not `DateTime.now().timeZoneName`: that answers with an
/// abbreviation, and abbreviations are not zones. "CEST" is shared by half of
/// Europe, "CST" by China, Cuba and most of the American midwest, and neither
/// says anything about when this year's transitions fall. A zone id does.
///
/// Read once and remembered. The value can change while the app runs — a phone
/// crossing a border, a laptop waking up elsewhere — and the refresh is left to
/// the next launch on purpose: the cost of being a flight behind is one export
/// stamped in the zone the reader left, and the cost of asking the platform on
/// every export is a channel round trip on a button press.
class ReaderTimeZone {
  ReaderTimeZone._();

  static String? _cached;
  static bool _asked = false;

  /// The zone id, or null when this platform will not say.
  ///
  /// Null is an ordinary answer, not a failure: the server falls back to the
  /// organization's configured zone, which is a deliberate choice by an admin
  /// and a much better document than one stamped in UTC. So every caller may
  /// simply leave the parameter off.
  static Future<String?> resolve() async {
    if (_asked) return _cached;
    _asked = true;
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      final name = zone.identifier.trim();
      _cached = looksLikeZoneId(name) ? name : null;
    } catch (error) {
      // A platform without an implementation, or one that answered with an
      // error. Neither is worth failing a download over, and neither is worth
      // a message to the user: the export still arrives, stamped in the zone
      // the organization configured.
      if (kDebugMode) debugPrint('[export] no device time zone: $error');
      _cached = null;
    }
    return _cached;
  }

  /// Whether [name] is shaped like an IANA id, so a surprising answer from a
  /// platform never reaches the server as a query parameter.
  ///
  /// The server ignores what it cannot parse, so this is belt and braces — but
  /// the value travels in a URL, and a URL is worth being careful with whatever
  /// is at the other end of it. Region/City, or one of the handful of
  /// single-word zones (`UTC`, `EST`, `Zulu`).
  @visibleForTesting
  static bool looksLikeZoneId(String name) {
    if (name.isEmpty || name.length > 64) return false;
    return RegExp(r'^[A-Za-z][A-Za-z0-9+_-]*(/[A-Za-z0-9+_-]+){0,2}$')
        .hasMatch(name);
  }

  /// Forgets the cached answer. Tests only — the value is process-wide.
  static void resetForTest() {
    _cached = null;
    _asked = false;
  }
}
