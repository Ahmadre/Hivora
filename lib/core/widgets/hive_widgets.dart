import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api/api_client.dart';
import '../i18n/i18n.dart';
import '../responsive/responsive.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/hue_colors.dart';
import 'preview_image.dart' show blurHashProviderFor;
import 'app_avatar.dart';
import 'user_pronouns.dart';

/// App-wide toggle — Cupertino style (the product's switch convention), tinted
/// with the honey accent when on. Use this instead of Material [Switch].
class HiveSwitch extends StatelessWidget {
  const HiveSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return CupertinoSwitch(
      value: value,
      onChanged: onChanged,
      activeTrackColor: AppColors.accent,
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
//  Hinata "Hive" v2 design kit — shared primitives that mirror the
//  reference web prototype (./Design/v2). Every workspace screen builds
//  from these so cards, badges, glyphs and motion stay 1:1 consistent.
// ════════════════════════════════════════════════════════════════════════

/// Cubic easing used across the design (cubic-bezier(.22,1,.36,1)).
const hiveEase = Cubic(0.22, 1, 0.36, 1);

// ───────────────────────────── meta tables ──────────────────────────────

class _TypeMeta {
  const _TypeMeta(this.icon, this.color);
  final IconData icon;
  final Color color;
}

const _typeMeta = <String, _TypeMeta>{
  // Backend Issue.Type: TASK, BUG, FEATURE, STORY, EPIC, SUBTASK.
  'TASK': _TypeMeta(LucideIcons.circleCheck, AppColors.stTodo),
  'BUG': _TypeMeta(LucideIcons.bug, AppColors.priUrgent),
  'FEATURE': _TypeMeta(LucideIcons.sparkles, AppColors.stProgress),
  'EPIC': _TypeMeta(LucideIcons.zap, AppColors.stReview),
  'STORY': _TypeMeta(LucideIcons.bookmark, AppColors.stDone),
  'SUBTASK': _TypeMeta(LucideIcons.gitBranch, AppColors.priLow),
};

_TypeMeta _typeOf(String type) =>
    _typeMeta[type.toUpperCase()] ?? _typeMeta['TASK']!;

class _PriMeta {
  const _PriMeta(this.icon, this.color);
  final IconData icon;
  final Color color;
}

const _priMeta = <String, _PriMeta>{
  // Backend Issue.Priority: SHOWSTOPPER, CRITICAL, MAJOR, NORMAL, MINOR,
  // TRIVIAL.
  'SHOWSTOPPER': _PriMeta(LucideIcons.chevronsUp, AppColors.priUrgent),
  'CRITICAL': _PriMeta(LucideIcons.chevronUp, AppColors.priUrgent),
  'MAJOR': _PriMeta(LucideIcons.chevronUp, AppColors.priHigh),
  'NORMAL': _PriMeta(LucideIcons.gripHorizontal, AppColors.priNormal),
  'MINOR': _PriMeta(LucideIcons.chevronDown, AppColors.priLow),
  'TRIVIAL': _PriMeta(LucideIcons.chevronsDown, AppColors.priLow),
  // Legacy aliases kept so older data / the design palette still resolve.
  'URGENT': _PriMeta(LucideIcons.chevronsUp, AppColors.priUrgent),
  'HIGH': _PriMeta(LucideIcons.chevronUp, AppColors.priHigh),
  'LOW': _PriMeta(LucideIcons.chevronDown, AppColors.priLow),
};

_PriMeta _priOf(String pri) =>
    _priMeta[pri.toUpperCase()] ?? _priMeta['NORMAL']!;

/// Friendly label for a workflow state code, falling back to a humanized form.
String stateLabel(String state) => switch (state.toUpperCase()) {
  'BACKLOG' => 'Backlog',
  'TODO' => 'To Do',
  'IN_PROGRESS' => 'In Progress',
  'IN_REVIEW' => 'In Review',
  'DONE' => 'Done',
  _ =>
    state
        .replaceAll('_', ' ')
        .split(' ')
        .map(
          (w) =>
              w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase(),
        )
        .join(' '),
};

// ───────────────────────────── glyphs / badges ──────────────────────────

/// Small tinted rounded square holding an issue-type icon.
class TypeGlyph extends StatelessWidget {
  const TypeGlyph({super.key, required this.type, this.size = 20});

  final String type;
  final double size;

  @override
  Widget build(BuildContext context) {
    final m = _typeOf(type);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.soft(m.color),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Icon(m.icon, size: size * 0.66, color: m.color),
    );
  }
}

/// Pill badge with type icon + label.
class TypeBadge extends StatelessWidget {
  const TypeBadge({super.key, required this.type});
  final String type;

  @override
  Widget build(BuildContext context) {
    final m = _typeOf(type);
    return _Pill(
      color: m.color,
      icon: m.icon,
      label: context.t('type.${type.toLowerCase()}'),
    );
  }
}

/// Priority indicator: a bare flag icon, or a labelled pill.
class PriorityFlag extends StatelessWidget {
  const PriorityFlag({
    super.key,
    required this.priority,
    this.withLabel = false,
  });

  final String priority;
  final bool withLabel;

  @override
  Widget build(BuildContext context) {
    final m = _priOf(priority);
    if (!withLabel) {
      return Icon(m.icon, size: 16, color: m.color);
    }
    return _Pill(
      color: m.color,
      icon: m.icon,
      label: context.t('priority.${priority.toLowerCase()}'),
    );
  }
}

/// Inline state cell: colored dot + state name (matches `.c-state`).
class StateDotBadge extends StatelessWidget {
  const StateDotBadge({super.key, required this.state, this.color});
  final String state;

  /// Overrides the global state-palette color (per-project state hue).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? AppColors.stateColor(state.toUpperCase());
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            stateLabel(state),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.color, required this.icon, required this.label});
  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.soft(color),
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Subtle label/tag chip (matches `.tag`).
class LabelTag extends StatelessWidget {
  const LabelTag(this.label, {super.key, this.hue});
  final String label;

  /// When set, tints the chip to the project's configured label hue; otherwise
  /// renders the neutral monochrome chip.
  final int? hue;

  @override
  Widget build(BuildContext context) {
    final h = hue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: h == null ? AppColors.surfaceMuted : hueSoft(h),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: h == null ? AppColors.hairline2 : hueBorder(h),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: h == null ? AppColors.inkSoft : hueChipText(h),
        ),
      ),
    );
  }
}

/// Monospace readable id (`HIV-241`).
class IdMono extends StatelessWidget {
  const IdMono(this.text, {super.key, this.color, this.fontSize = 11.5});
  final String text;
  final Color? color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: AppTheme.fontMono,
        fontSize: fontSize,
        fontWeight: FontWeight.w500,
        color: color ?? AppColors.inkSoft,
      ),
    );
  }
}

// ───────────────────────────── progress ─────────────────────────────────

/// Thin animated progress bar (matches `.prog`).
class HiveProgress extends StatelessWidget {
  const HiveProgress({
    super.key,
    required this.value,
    this.color,
    this.height = 6,
  });

  final double value;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 800),
        curve: hiveEase,
        tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
        builder: (_, v, _) => LinearProgressIndicator(
          value: v,
          minHeight: height,
          backgroundColor: AppColors.canvas2,
          valueColor: AlwaysStoppedAnimation(color ?? AppColors.accent),
        ),
      ),
    );
  }
}

// ───────────────────────────── avatars ──────────────────────────────────

/// Deterministic harmonious color from a seed string (approximates the
/// prototype's oklch(0.62 0.12 hue)).
Color hiveHueColor(String seed) {
  final hue = (seed.hashCode.abs() % 360).toDouble();
  return HSLColor.fromAHSL(1, hue, 0.42, 0.55).toColor();
}

String _initials(String value) {
  final parts = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.characters.first.toUpperCase();
  return (parts.first.characters.first + parts.last.characters.first)
      .toUpperCase();
}

/// Whether [value] is an opaque identifier rather than something a person is
/// called — a Mongo ObjectId, a UUID, a hex token.
///
/// Initials of an id are noise that *looks* like data: every user whose
/// ObjectId starts with the same nibble gets the same letter, so a whole list
/// renders the same meaningless "6". A caller that has no name yet is better
/// served by an honest placeholder, so [HiveAvatar] draws a person glyph for
/// these instead of a fake initial.
@visibleForTesting
bool looksLikeOpaqueId(String value) {
  final v = value.trim();
  if (v.length < 12 || v.contains(RegExp(r'\s'))) return false;
  // 24-hex ObjectId, 32-hex token, or a dashed UUID.
  return RegExp(r'^[0-9a-f]{12,}$', caseSensitive: false).hasMatch(v) ||
      RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        caseSensitive: false,
      ).hasMatch(v);
}

/// Round initials avatar tinted by name hue.
class HiveAvatar extends StatelessWidget {
  const HiveAvatar({
    super.key,
    required this.name,
    this.size = 30,
    this.ring = false,
    this.imageUrl,
    this.glyph,
    this.background,
    this.pronouns,
  });

  final String name;
  final double size;
  final bool ring;
  final String? imageUrl;

  /// The person's pronouns, shown on hover as "Name · they/them".
  ///
  /// This is how pronouns reach the many places that show a face but have no
  /// room to spell them out — board cards, assignee chips, avatar stacks. Pass
  /// null where the surface already prints them beside the name (the tooltip
  /// would only repeat it) or where the avatar is wrapped in a tooltip of its
  /// own, which would otherwise nest two.
  final String? pronouns;

  /// When set, renders this widget instead of initials — used to mark
  /// non-human actors such as automated system actions with the brand mark.
  final Widget? glyph;

  /// Overrides the auto-generated hue. Pair with [glyph] for branded avatars.
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final said = normalizePronouns(pronouns);
    if (said == null) return _avatar(context);
    return Tooltip(
      message: personTooltip(name: name, pronouns: said),
      waitDuration: const Duration(milliseconds: 400),
      child: _avatar(context),
    );
  }

  Widget _avatar(BuildContext context) {
    final url = imageUrl;
    final hasImage = url != null && url.isNotEmpty;
    if (hasImage) {
      // External absolute images keep the plain network path; our own avatar
      // URLs (/api/v1/users/.../avatar) are authenticated and must be loaded as
      // bytes via the ApiClient — a cross-origin NetworkImage taints the
      // CanvasKit canvas on web and silently fails (same fix as AppAvatar).
      final isExternal =
          url.startsWith('http') && !url.contains('/api/v1/users/');
      if (isExternal) return _circle(NetworkImage(url));
      ApiClient? api;
      try {
        api = context.read<ApiClient>();
      } catch (_) {
        api = null;
      }
      if (api != null) {
        return ApiImageAvatar(
          key: ValueKey(url),
          path: url,
          api: api,
          // The picture's BlurHash rides in its URL, so the circle is a blurred
          // version of the actual photo while the bytes are on their way.
          placeholder: _circle(blurHashProviderFor(url)),
          builder: _circle,
        );
      }
    }
    return _circle(null);
  }

  Widget _circle(ImageProvider? image) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: background ?? hiveHueColor(name),
      shape: BoxShape.circle,
      image: image != null
          ? DecorationImage(image: image, fit: BoxFit.cover)
          : null,
      boxShadow: ring
          ? [BoxShadow(color: AppColors.surface, spreadRadius: 2)]
          : null,
    ),
    alignment: Alignment.center,
    child: image != null ? null : glyph ?? _label(),
  );

  /// Initials — unless all we were given is an id, which has none.
  Widget _label() {
    if (looksLikeOpaqueId(name)) {
      return Icon(LucideIcons.user, size: size * 0.5, color: Colors.white);
    }
    return Text(
      _initials(name),
      style: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
        fontSize: size * 0.4,
      ),
    );
  }
}

/// Overlapping avatar stack with optional +N overflow chip.
class HiveAvatarStack extends StatelessWidget {
  const HiveAvatarStack({
    super.key,
    required this.names,
    this.imageUrls = const [],
    this.pronouns = const [],
    this.size = 26,
    this.max = 4,
  });

  final List<String> names;

  /// Optional avatar image URLs, parallel to [names] (null/short entries fall
  /// back to initials).
  final List<String?> imageUrls;

  /// Optional pronouns, parallel to [names]. A stack is all face and no text,
  /// so hovering one is the only way to learn who it is — and how to refer to
  /// them.
  final List<String?> pronouns;
  final double size;
  final int max;

  @override
  Widget build(BuildContext context) {
    final shown = names.take(max).toList();
    final extra = names.length - shown.length;
    final overlap = size * 0.3;
    final count = shown.length + (extra > 0 ? 1 : 0);
    if (count == 0) return const SizedBox.shrink();
    return SizedBox(
      height: size,
      width: size + (count - 1) * (size - overlap),
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * (size - overlap),
              child: HiveAvatar(
                name: shown[i],
                imageUrl: i < imageUrls.length ? imageUrls[i] : null,
                pronouns: i < pronouns.length ? pronouns[i] : null,
                size: size,
                ring: true,
              ),
            ),
          if (extra > 0)
            Positioned(
              left: shown.length * (size - overlap),
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: AppColors.canvas2,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: AppColors.surface, spreadRadius: 2),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  '+$extra',
                  style: TextStyle(
                    fontSize: size * 0.36,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkSoft,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ───────────────────────────── page head ────────────────────────────────

/// Page title + subtitle on the left, optional action buttons on the right.
class PageHead extends StatelessWidget {
  const PageHead({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTheme.fontBrand,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    color: AppColors.ink,
                    height: 1.1,
                  ),
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.5, color: AppColors.inkSoft),
                ),
              ],
            ],
          ),
        ),
        for (final a in actions) ...[const SizedBox(width: 10), a],
      ],
    );
  }
}

// ───────────────────────────── buttons ──────────────────────────────────

/// Navy primary action button.
///
/// When [collapseToIcon] is set, the button drops its label and renders as a
/// square icon-only control on compact (phone) layouts — the label is moved to
/// a tooltip — so action-heavy headers don't crowd out the page title.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.collapseToIcon = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool collapseToIcon;

  @override
  Widget build(BuildContext context) {
    final glyph = icon ?? LucideIcons.plus;
    if (collapseToIcon && context.isCompact) {
      return Tooltip(
        message: label,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: const Color(0xFF2A2410),
            padding: EdgeInsets.zero,
            minimumSize: const Size(46, 46),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            ),
          ),
          child: Icon(glyph, size: 18),
        ),
      );
    }
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: const Color(0xFF2A2410),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        ),
      ),
      icon: Icon(glyph, size: 16),
      label: Text(label),
    );
  }
}

/// White hairline-bordered secondary button.
///
/// See [PrimaryButton.collapseToIcon] — same compact icon-only behaviour.
class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.collapseToIcon = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool collapseToIcon;

  @override
  Widget build(BuildContext context) {
    final glyph = icon ?? LucideIcons.slidersHorizontal;
    if (collapseToIcon && context.isCompact) {
      return Tooltip(
        message: label,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.ink,
            side: BorderSide(color: AppColors.hairline),
            padding: EdgeInsets.zero,
            minimumSize: const Size(46, 46),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            ),
          ),
          child: Icon(glyph, size: 18),
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        side: BorderSide(color: AppColors.hairline),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        ),
      ),
      icon: Icon(glyph, size: 16),
      label: Text(label),
    );
  }
}

// ───────────────────────────── segmented control ────────────────────────

class SegmentItem {
  const SegmentItem({required this.label, required this.icon});
  final String label;
  final IconData icon;
}

/// Pill segmented control (Board / Backlog / Timeline · Weeks / Days).
class SegmentedControl extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.items,
    required this.selected,
    required this.onChanged,
    this.iconsOnly = false,
  });

  final List<SegmentItem> items;
  final int selected;
  final ValueChanged<int> onChanged;

  /// Drops the labels and keeps the icons — phone headers have to share their
  /// row with the group-by and filter buttons. The label moves into a tooltip
  /// so the meaning stays reachable.
  final bool iconsOnly;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [for (var i = 0; i < items.length; i++) _segment(context, i)],
      ),
    );
  }

  Widget _segment(BuildContext context, int i) {
    final segment = GestureDetector(
      onTap: () => onChanged(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(
          horizontal: iconsOnly ? 11 : 12,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: i == selected ? AppColors.navy : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              items[i].icon,
              size: 15,
              color: i == selected ? Colors.white : AppColors.inkSoft,
            ),
            if (!iconsOnly) ...[
              const SizedBox(width: 6),
              Text(
                items[i].label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: i == selected ? Colors.white : AppColors.inkSoft,
                ),
              ),
            ],
          ],
        ),
      ),
    );
    // Only when the label is gone — a tooltip repeating visible text is noise.
    return iconsOnly
        ? Tooltip(message: items[i].label, child: segment)
        : segment;
  }
}

// ───────────────────────────── helpers ──────────────────────────────────

/// Relative due label + lateness: "3 T. überfällig", "Heute", "in 4 T.", and
/// a plain date once the deadline is more than a week out.
///
/// Localized end to end — the near terms through the message bundle, the far
/// date through [DateFormat] in the app's locale, so a German user never reads
/// "23d overdue" or "Jul 24".
({String text, bool late})? dueLabel(BuildContext context, DateTime? due) {
  if (due == null) return null;
  final d = DateTime(due.year, due.month, due.day);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final diff = d.difference(today).inDays;
  // Interpolated, not pluralized: these strings use the same wording for one
  // day and for many ("1 T. überfällig" / "23 T. überfällig"), and asking
  // i18next for a plural form that no bundle defines renders the bare key.
  String t(String key, [int? count]) => context.t(
    'issues.due.$key',
    variables: count == null ? const {} : {'count': count},
  );
  if (diff < 0) return (text: t('overdue', -diff), late: true);
  if (diff == 0) return (text: t('today'), late: true);
  if (diff == 1) return (text: t('tomorrow'), late: false);
  if (diff <= 7) return (text: t('inDays', diff), late: false);
  final locale = Localizations.localeOf(context).toString();
  return (text: DateFormat.MMMd(locale).format(d), late: false);
}

// ───────────────────────── directional chevrons ─────────────────────────
//
// Lucide ships fixed glyphs — unlike Material's `arrow_forward`, a
// `LucideIcons.chevronRight` does not turn around when the text does. Every
// disclosure arrow in the app therefore kept pointing at the leading edge in
// Arabic, into the row it was supposed to lead out of.
//
// These pick the glyph rather than wrapping it: a call site keeps its own size,
// colour and semantics, and the change at each one is a single token.

/// The chevron that points the way the text runs — "open this", "next page",
/// "later week". Use it for disclosure arrows and for stepping *forward*
/// through a sequence.
IconData forwardChevron(BuildContext context) =>
    Directionality.of(context) == TextDirection.rtl
    ? LucideIcons.chevronLeft
    : LucideIcons.chevronRight;

/// The chevron that points against the text run — "back", "previous page",
/// "earlier week". The mirror of [forwardChevron], and always its pair.
IconData backChevron(BuildContext context) =>
    Directionality.of(context) == TextDirection.rtl
    ? LucideIcons.chevronRight
    : LucideIcons.chevronLeft;

/// The arrow that points the way the text runs — "next step", "go to this",
/// and the `from → to` of a change. [backArrow] is its pair, for "back".
IconData forwardArrow(BuildContext context) =>
    Directionality.of(context) == TextDirection.rtl
    ? LucideIcons.arrowLeft
    : LucideIcons.arrowRight;

/// The arrow that points against the text run — every "back" in the app.
IconData backArrow(BuildContext context) =>
    Directionality.of(context) == TextDirection.rtl
    ? LucideIcons.arrowRight
    : LucideIcons.arrowLeft;

/// The quarter turn that swings a chevron between pointing the way text runs
/// and pointing down, for the twisty on an expandable section.
///
/// Clockwise in LTR (right → down), counter-clockwise in RTL (left → down); a
/// fixed `0.25` would send the Arabic one up instead. Negate it to swing the
/// other way, from down back to the reading direction.
double chevronTurn(BuildContext context) =>
    Directionality.of(context) == TextDirection.rtl ? -0.25 : 0.25;

/// Format minutes as `2h 30m`.
String fmtDuration(int? minutes) {
  if (minutes == null) return '—';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}
