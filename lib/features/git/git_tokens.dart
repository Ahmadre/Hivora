import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/models/git_dev_info.dart';

/// Design tokens for the Git integration surfaces, mirrored 1:1 from
/// `app/git.css`. Colours resolve through the shared hue system
/// (`core/theme/hue_colors.dart`) so they stay theme-aware.

/// Brand colour for a provider glyph tile (octocat white / monogram).
Color providerBrand(GitProvider provider) => switch (provider) {
  GitProvider.github => const Color(0xFF1F2328),
  GitProvider.gitlab => const Color(0xFFFC6D26),
  GitProvider.bitbucket => const Color(0xFF0C66E4),
};

/// Accordion-category hues (the hue-tinted icon tile per category).
const int kHueBranch = 250; // indigo
const int kHueCommit = 70; // honey / accent
const int kHuePullRequest = 300; // violet
const int kHueBuild = 155; // green

/// Category icon for the Development accordion.
IconData categoryIcon(String key) => switch (key) {
  'branches' => LucideIcons.gitBranch,
  'commits' => LucideIcons.gitCommitHorizontal,
  'prs' => LucideIcons.gitPullRequest,
  'builds' => LucideIcons.box,
  _ => LucideIcons.gitBranch,
};

/// Hue + icon + label for a PR/MR state pill (label localized for [context]).
({int hue, IconData icon, String label}) prStateStyle(
  BuildContext context,
  PrState state,
) => switch (state) {
  PrState.open => (
    hue: 155,
    icon: LucideIcons.gitPullRequest,
    label: context.t('git.stateOpen'),
  ),
  PrState.draft => (
    hue: 250,
    icon: LucideIcons.gitPullRequestDraft,
    label: context.t('git.stateDraft'),
  ),
  PrState.merged => (
    hue: 300,
    icon: LucideIcons.gitMerge,
    label: context.t('git.stateMerged'),
  ),
  PrState.closed => (
    hue: 20,
    icon: LucideIcons.gitPullRequestClosed,
    label: context.t('git.stateClosed'),
  ),
};

/// Hue + icon + label for a checks / build status pill (label localized).
({int hue, IconData icon, String label}) checkStyle(
  BuildContext context,
  CheckState state,
) => switch (state) {
  CheckState.passing => (
    hue: 155,
    icon: LucideIcons.circleCheckBig,
    label: context.t('git.statePassing'),
  ),
  CheckState.failing => (
    hue: 20,
    icon: LucideIcons.circleX,
    label: context.t('git.stateFailing'),
  ),
  CheckState.pending => (
    hue: 65,
    icon: LucideIcons.clock,
    label: context.t('git.statePending'),
  ),
  CheckState.running => (
    hue: 200,
    icon: LucideIcons.loaderCircle,
    label: context.t('git.stateRunning'),
  ),
};
