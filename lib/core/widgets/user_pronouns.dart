import 'package:flutter/material.dart';

import '../models/core_models.dart';
import '../theme/app_colors.dart';

/// How a person's pronouns are presented, everywhere in the app.
///
/// Two rules hold across every surface:
///
/// * **Never invent them.** A blank or missing value renders nothing at all —
///   no placeholder, no "—". Someone who has not filled the field in is not
///   making a statement we should put words to.
/// * **Never say them twice.** Where a surface already prints the pronouns
///   next to the name ([PronounsLabel]), the avatar beside it is built without
///   them so hovering does not echo what is already on screen. Where they are
///   not printed, the avatar's tooltip is the only place they appear — which
///   is what makes them reachable on every people-chip in the app.

/// The value to actually show, or null when there is nothing to say.
String? normalizePronouns(String? pronouns) {
  final value = pronouns?.trim();
  return (value == null || value.isEmpty) ? null : value;
}

/// Tooltip text for a person's avatar: who they are, and — when we know them
/// and the surface is not already showing them — how to refer to them.
String personTooltip({required String name, String? pronouns}) {
  final said = normalizePronouns(pronouns);
  final who = name.trim();
  if (said == null) return who;
  return who.isEmpty ? said : '$who · $said';
}

/// Pronouns by user id, for the screens that resolve a directory once and then
/// render rows from it. Skips everyone who has not said, so a lookup miss and
/// "not set" are the same thing at every call site.
Map<String, String> pronounsById(Iterable<DirectoryUser> users) => {
  for (final user in users) user.id: ?normalizePronouns(user.pronouns),
};

/// A username as it is shown to a reader: `@name`, kept left-to-right.
///
/// The `@` is a neutral character, so in a right-to-left paragraph the bidi
/// algorithm reads it as belonging to the Arabic around it and moves it to the
/// visual end — `@pronoun-tester` renders as `pronoun-tester@`. Wrapping the
/// handle in an isolate (U+2066 … U+2069) says "this run has its own direction,
/// resolve it on its own", which is exactly what a Latin identifier inside
/// Arabic prose needs. Invisible in every left-to-right language, so there is
/// one form of this string rather than two.
String userHandle(String? username) {
  final name = username?.trim() ?? '';
  if (name.isEmpty) return '';
  return '\u2066@$name\u2069';
}

/// The inline, muted pronouns that sit next to a name — comment headers,
/// member rows, the admin user list, the audit trail.
///
/// Renders nothing at all — not even [leadingGap] — when there is nothing to
/// say, so a row can hold one unconditionally instead of guarding at the call
/// site and having the gap survive the label it was spacing.
class PronounsLabel extends StatelessWidget {
  const PronounsLabel({
    super.key,
    required this.pronouns,
    this.fontSize = 12,
    this.color,
    this.leadingGap = 0,
  });

  final String? pronouns;
  final double fontSize;
  final Color? color;

  /// Space between the name and the pronouns, dropped along with them.
  final double leadingGap;

  @override
  Widget build(BuildContext context) {
    final said = normalizePronouns(pronouns);
    if (said == null) return const SizedBox.shrink();
    final label = Text(
      said,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w500,
        color: color ?? AppColors.inkFaint,
      ),
    );
    if (leadingGap == 0) return label;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: leadingGap),
        Flexible(child: label),
      ],
    );
  }
}
