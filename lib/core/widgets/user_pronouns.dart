import 'package:flutter/material.dart';

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
///
/// Returns null when there is nothing worth a tooltip, so callers can skip
/// wrapping entirely rather than attaching an empty one.
String? personTooltip({required String name, String? pronouns}) {
  final said = normalizePronouns(pronouns);
  final who = name.trim();
  if (said == null) return who.isEmpty ? null : who;
  return who.isEmpty ? said : '$who · $said';
}

/// The inline, muted pronouns that sit next to a name — comment headers,
/// member rows, the admin user list, the audit trail.
///
/// Renders nothing when there are no pronouns to show, so callers can drop it
/// into a Row unconditionally instead of guarding at every call site.
class PronounsLabel extends StatelessWidget {
  const PronounsLabel({
    super.key,
    required this.pronouns,
    this.fontSize = 12,
    this.color,
  });

  final String? pronouns;
  final double fontSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final said = normalizePronouns(pronouns);
    if (said == null) return const SizedBox.shrink();
    return Text(
      said,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w500,
        color: color ?? AppColors.inkFaint,
      ),
    );
  }
}
