part of 'issues_screen.dart';

/// A grouped-section header that toggles its rows on tap, with a chevron that
/// rotates to point right when collapsed — the same affordance as the board's
/// swimlanes.
class _CollapsibleHeader extends StatelessWidget {
  const _CollapsibleHeader({
    required this.collapsed,
    required this.header,
    required this.onTap,
  });

  final bool collapsed;
  final Widget header;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: AnimatedRotation(
                turns: collapsed ? -0.25 : 0,
                duration: const Duration(milliseconds: 160),
                child: Icon(
                  LucideIcons.chevronDown,
                  size: 18,
                  color: AppColors.inkSoft,
                ),
              ),
            ),
            Flexible(child: header),
          ],
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.leading,
    required this.label,
    required this.count,
  });

  final Widget leading;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontFamily: AppTheme.fontMono,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.inkSoft,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 11,
      height: 11,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// Localised label for an enum-like [code] under [prefix] (`type`/`priority`),
/// humanising the raw code when no translation exists.
String _enumLabel(BuildContext context, String prefix, String code) {
  final key = '$prefix.${code.toLowerCase()}';
  final value = context.t(key);
  if (value != key) return value;
  return code
      .split(RegExp(r'[_ ]'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');
}

// ───────────────────────────── table ────────────────────────────────────

class _IssueTableHeader extends StatelessWidget {
  const _IssueTableHeader();

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
      color: AppColors.inkFaint,
    );
    Widget cell(String key, {int? flex, double? width}) {
      final text = Text(
        context.t(key).toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
      if (width != null) return SizedBox(width: width, child: text);
      return Expanded(flex: flex!, child: text);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          cell('issues.colId', width: 76),
          const SizedBox(width: 12),
          cell('issues.colTitle', flex: 5),
          const SizedBox(width: 12),
          cell('issues.colStatus', flex: 3),
          const SizedBox(width: 8),
          cell('issues.colPriority', flex: 3),
          const SizedBox(width: 8),
          cell('issues.colAssignee', flex: 3),
          const SizedBox(width: 8),
          cell('issues.colDue', width: 60),
          const SizedBox(width: 18),
        ],
      ),
    );
  }
}

class IssueRow extends StatelessWidget {
  const IssueRow({
    super.key,
    required this.issue,
    this.assignee,
    this.assigneeAvatar,
    this.onTap,
    this.onChanged,
    this.palette,
  });

  final Issue issue;
  final String? assignee;
  final String? assigneeAvatar;
  final VoidCallback? onTap;

  /// Invoked after the detail sheet edits this issue, so the host list can
  /// refresh. Only used when [onTap] is not overridden.
  final VoidCallback? onChanged;
  final ProjectPalette? palette;

  @override
  Widget build(BuildContext context) {
    final due = dueLabel(issue.dueDate);
    final compact = context.isCompact;
    final name = assignee ?? '';

    final tap =
        onTap ??
        () => showIssueDetailSheet(
          context,
          issueId: issue.id,
          onChanged: onChanged,
        );

    if (compact) {
      return SoftCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: tap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IdMono(issue.readableId),
                const Spacer(),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: PriorityFlag(
                    priority: issue.priority,
                    withLabel: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TypeGlyph(type: issue.type),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    issue.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (issue.hasSubtasks) ...[
                  const SizedBox(width: 8),
                  SubtaskBadge(issue: issue),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: StateDotBadge(
                    state: issue.state,
                    color: palette?.stateColor(issue.state),
                  ),
                ),
                if (name.isNotEmpty)
                  HiveAvatar(name: name, imageUrl: assigneeAvatar, size: 22),
                if (due != null) ...[
                  const SizedBox(width: 10),
                  Text(
                    due.text,
                    style: TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontSize: 12,
                      color: due.late ? AppColors.danger : AppColors.inkSoft,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      );
    }

    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      onTap: tap,
      child: Row(
        children: [
          SizedBox(width: 76, child: IdMono(issue.readableId)),
          const SizedBox(width: 12),
          // title
          Expanded(
            flex: 5,
            child: Row(
              children: [
                TypeGlyph(type: issue.type),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(
                    issue.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (issue.tags.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: LabelTag(
                      issue.tags.first,
                      hue: palette?.labelHue(issue.tags.first),
                    ),
                  ),
                ],
                if (issue.hasSubtasks) ...[
                  const SizedBox(width: 8),
                  SubtaskBadge(issue: issue),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerLeft,
              child: StateDotBadge(
                state: issue.state,
                color: palette?.stateColor(issue.state),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerLeft,
              child: PriorityFlag(priority: issue.priority, withLabel: true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: name.isEmpty
                ? Text('—', style: TextStyle(color: AppColors.inkFaint))
                : Row(
                    children: [
                      HiveAvatar(
                        name: name,
                        imageUrl: assigneeAvatar,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          name.split(' ').first,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 60,
            child: Text(
              due?.text ?? '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppTheme.fontMono,
                fontSize: 12,
                color: due != null && due.late
                    ? AppColors.danger
                    : AppColors.inkSoft,
              ),
            ),
          ),
          const SizedBox(width: 18),
          Icon(LucideIcons.chevronRight, size: 18, color: AppColors.inkFaint),
        ],
      ),
    );
  }
}
