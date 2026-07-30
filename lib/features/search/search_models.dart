import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// The fixed grouping order of the palette (mirrors `GS_ORDER` in search.jsx).
enum SearchCat { commands, issues, projects, people, boards, docs }

/// Per-category icon + i18n label key (mirrors `GS_CAT`).
class SearchCatMeta {
  const SearchCatMeta(this.icon, this.labelKey);
  final IconData icon;
  final String labelKey;
}

const Map<SearchCat, SearchCatMeta> kSearchCatMeta = {
  SearchCat.commands: SearchCatMeta(LucideIcons.command, 'search.cat.commands'),
  SearchCat.issues: SearchCatMeta(LucideIcons.circleDot, 'search.cat.issues'),
  SearchCat.projects: SearchCatMeta(
    LucideIcons.squareKanban,
    'search.cat.projects',
  ),
  SearchCat.people: SearchCatMeta(LucideIcons.users, 'search.cat.people'),
  SearchCat.boards: SearchCatMeta(LucideIcons.columns3, 'search.cat.boards'),
  SearchCat.docs: SearchCatMeta(LucideIcons.bookOpen, 'search.cat.docs'),
};

/// One row in the search index. Display data is precomputed off the real
/// models when the index is built; [onSelect] performs the navigation/command.
class SearchEntry {
  SearchEntry({
    required this.cat,
    required this.key,
    required this.title,
    required this.keys,
    required this.onSelect,
    this.closesOnSelect = true,
    this.subtitle,
    this.leadingIcon,
    this.issueType,
    this.statusColor,
    this.statusName,
    this.mono,
    this.avatarName,
    this.avatarUrl,
    this.memberNames,
    this.keyChipText,
    this.keyChipColor,
    this.hint,
    this.archived = false,
  });

  final SearchCat cat;

  /// Stable identity for the row (used as the keyboard-selection key).
  final String key;

  final String title;

  /// Lowercased haystack: title + id + tags + assignee + type + state.
  final String keys;

  /// Runs the result/command. Receives a context that is still mounted under
  /// the app (the dialog is dismissed by the caller before/with navigation).
  final void Function(BuildContext context) onSelect;

  /// Whether activating this entry dismisses the palette. Commands that mutate
  /// in place (e.g. toggle appearance) keep it open, mirroring search.jsx.
  final bool closesOnSelect;

  // ---- per-category display data ----
  final String? subtitle;

  /// Leading tile glyph (docs / boards / commands).
  final IconData? leadingIcon;

  /// Issue type for the tinted [TypeGlyph] leading tile.
  final String? issueType;

  /// Issue status dot + name (issue subtitle).
  final Color? statusColor;
  final String? statusName;

  /// Monospace id shown in the issue subtitle (e.g. `HIV-241`).
  final String? mono;

  /// Trailing single avatar (issue assignee / person leading).
  final String? avatarName;
  final String? avatarUrl;

  /// Trailing avatar stack (project members).
  final List<String>? memberNames;

  /// Project hex key chip.
  final String? keyChipText;
  final Color? keyChipColor;

  /// Command keyboard hint (e.g. `C`).
  final String? hint;

  /// Archived (soft-deleted) issue / archived project — rendered with an
  /// "Archived" badge.
  final bool archived;
}
