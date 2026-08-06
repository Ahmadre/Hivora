/// Shared date/time parsing for API payloads.
///
/// The backend sends every absolute timestamp as ISO-8601 **UTC** (trailing
/// `Z`) and every pure calendar date as `yyyy-MM-dd`. These two helpers encode
/// the one rule that keeps the whole app timezone-correct:
///
/// * [parseInstant] — an absolute moment (createdAt, updatedAt, resolvedAt, …).
///   Converted to the device's **local** zone at parse time, so any downstream
///   `DateFormat` / `MaterialLocalizations` renders in the user's timezone
///   automatically. Relative "x ago" helpers are unaffected either way because
///   `DateTime.difference` compares absolute instants.
///
/// * [parseDate] — a pure calendar date (dueDate, startDate, a tracker day, …).
///   It has **no** timezone and must never be shifted across zones, so it is
///   normalized to local midnight of that exact calendar day. Passing it through
///   `toLocal()` would be a bug (it could move the date to the previous day).
///
/// * [parseIsoSeconds] / [isoSeconds] — a *duration* rather than a moment. The
///   backend models a few settings as `java.time.Duration`, which goes over the
///   wire as `PT5S`, so a field showing "seconds" cannot read the number
///   directly and cannot write one back either.
library;

/// Parses an absolute timestamp into a **local** [DateTime]. Accepts an
/// ISO-8601 string (UTC or with offset) or a numeric epoch in milliseconds.
/// Returns `null` for null/blank/invalid input.
DateTime? parseInstant(Object? value) {
  if (value == null) return null;
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(
      value.toInt(),
      isUtc: true,
    ).toLocal();
  }
  if (value is String) {
    if (value.isEmpty) return null;
    return DateTime.tryParse(value)?.toLocal();
  }
  return null;
}

/// Parses a pure calendar date into local midnight of that day. Strips any time
/// or zone component so the date stays on the same calendar day everywhere.
DateTime? parseDate(Object? value) {
  if (value is! String || value.isEmpty) return null;
  final dt = DateTime.tryParse(value);
  if (dt == null) return null;
  return DateTime(dt.year, dt.month, dt.day);
}

/// Whole seconds in an ISO-8601 duration (`PT5S`, `PT1M30S`), or null.
///
/// Hours and minutes are handled because Java normalizes on the way out — a
/// 60-second budget is serialized `PT1M`, not `PT60S` — so a parser that only
/// understood seconds would silently show a settings field as empty. Anything
/// it cannot read returns null so the caller can fall back to a sensible
/// default, rather than a zero the user would then save.
int? parseIsoSeconds(Object? value) {
  if (value is! String || value.isEmpty) return null;
  final match = RegExp(
    r'^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?$',
    caseSensitive: false,
  ).firstMatch(value.trim());
  if (match == null) return null;
  final hours = int.tryParse(match.group(1) ?? '') ?? 0;
  final minutes = int.tryParse(match.group(2) ?? '') ?? 0;
  final seconds = double.tryParse(match.group(3) ?? '') ?? 0;
  final total = hours * 3600 + minutes * 60 + seconds.round();
  return total > 0 ? total : null;
}

/// [seconds] as the ISO-8601 duration the backend's `Duration` binder parses.
String isoSeconds(int seconds) => 'PT${seconds}S';
