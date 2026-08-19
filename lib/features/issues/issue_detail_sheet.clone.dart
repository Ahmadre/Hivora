part of 'issue_detail_sheet.dart';

// ─────────────────────────── Clone dialog ──────────────────────────────────

/// The prefix a cloned summary is offered with, mirroring the server constant.
///
/// Deliberately the same string in every language: it is written into a title
/// that a whole organisation reads and searches, so a per-user prefix would
/// mean the same action produced different titles depending on who ran it —
/// and half the clones would fall out of any search for them. It is only a
/// prefill; whoever clones is free to delete it.
const String kIssueClonePrefix = 'CLONE - ';

/// Mirrors `CreateIssueRequest.title` on the server — a clone is an ordinary
/// issue and gets the ordinary bound.
const int kIssueTitleMaxChars = 300;

/// The summary a clone dialog opens with: the original's title behind the
/// prefix, cut to what the server will accept.
///
/// The prefix survives the cut, not the other way round — a title long enough
/// to need cutting is exactly the one where the reader needs the word "CLONE"
/// most.
String cloneTitlePrefill(String title) =>
    _cutToUnits('$kIssueClonePrefix$title', kIssueTitleMaxChars);

/// Cuts [value] to at most [max] UTF-16 code units — the unit the server's
/// length bound counts — without splitting a surrogate pair, which would leave
/// a lone surrogate that is not a character at all.
String _cutToUnits(String value, int max) {
  if (value.length <= max) return value;
  var end = max;
  final last = value.codeUnitAt(end - 1);
  if (last >= 0xD800 && last <= 0xDBFF) end -= 1;
  return value.substring(0, end);
}

/// Opens the clone dialog for [issue] and returns the created copy, or null if
/// the user cancelled.
///
/// The dialog performs the call itself rather than handing a request back: a
/// failure that closed the modal would throw away the summary the user just
/// typed, so it stays open, keeps the input and says what went wrong.
Future<Issue?> showIssueCloneDialog(
  BuildContext context, {
  required Issue issue,
  required List<DirectoryUser> users,
  required IssueRepository repository,
  String? meId,
  bool multiAssignee = false,
}) => showGlassModal<Issue>(
  context,
  width: 460,
  builder: (_) => _IssueCloneBody(
    issue: issue,
    users: users,
    repository: repository,
    meId: meId,
    multiAssignee: multiAssignee,
  ),
);

class _IssueCloneBody extends StatefulWidget {
  const _IssueCloneBody({
    required this.issue,
    required this.users,
    required this.repository,
    this.meId,
    this.multiAssignee = false,
  });

  final Issue issue;
  final List<DirectoryUser> users;
  final IssueRepository repository;
  final String? meId;
  final bool multiAssignee;

  @override
  State<_IssueCloneBody> createState() => _IssueCloneBodyState();
}

class _IssueCloneBodyState extends State<_IssueCloneBody> {
  late final TextEditingController _title = TextEditingController(
    text: cloneTitlePrefill(widget.issue.title),
  );
  late List<String> _assigneeIds = List.of(widget.issue.assigneeIds);
  bool _includeLinks = false;
  bool _includeSprint = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // The confirm button lives or dies on this field being non-empty, so every
    // keystroke has to reach the footer.
    _title.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  String? _nameOf(String id) => widget.users
      .cast<DirectoryUser?>()
      .firstWhere((user) => user?.id == id, orElse: () => null)
      ?.displayName;

  Future<void> _pickAssignee(Rect anchor) async {
    final wide = MediaQuery.sizeOf(context).width >= kGlassPopoverBreakpoint;
    Widget picker(BuildContext pickerContext) => _PeoplePicker(
      anchored: wide,
      users: widget.users,
      meId: widget.meId,
      multiSelect: widget.multiAssignee,
      initialSelected: _assigneeIds.toSet(),
      // Multi mode stays open and reports the whole set on every toggle; there
      // is nothing to save yet, so it only updates what the dialog will send.
      onSelectionChanged: (ids) => setState(() => _assigneeIds = ids.toList()),
      onUnassign: () {
        Navigator.of(pickerContext).pop();
        setState(() => _assigneeIds = []);
      },
      onAssignMe: widget.meId == null
          ? null
          : () {
              Navigator.of(pickerContext).pop();
              setState(() => _assigneeIds = [widget.meId!]);
            },
      onSelect: (id) {
        Navigator.of(pickerContext).pop();
        setState(() => _assigneeIds = [id]);
      },
    );

    if (wide) {
      await showGlassAnchoredPopover<void>(
        context,
        anchorRect: anchor,
        width: 340,
        maxHeight: 520,
        builder: picker,
      );
      return;
    }
    // _PeoplePicker draws its own grab handle, so suppress the helper's.
    await showGlassBottomSheet<void>(
      context,
      showHandle: false,
      builder: picker,
    );
  }

  Future<void> _clone() async {
    final title = _title.text.trim();
    if (title.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final copy = await widget.repository.cloneIssue(
        widget.issue.id,
        title: title,
        assigneeIds: _assigneeIds,
        includeLinks: _includeLinks,
        includeSprint: _includeSprint,
      );
      if (!mounted) return;
      Navigator.of(context).pop(copy);
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() => _busy = false);
      // Stays open: the summary in the field is the user's work, and a modal
      // that vanishes on a failed request throws it away.
      showGlassErrorToast(context, context.t(failure.message));
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showGlassErrorToast(context, context.t('errors.unexpected'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canClone = _title.text.trim().isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: LucideIcons.copy,
          title: context.t(
            'issues.clone.title',
            variables: {'id': widget.issue.readableId},
          ),
          subtitle: context.t('issues.clone.sub'),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 6, 22, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GlassField(
                  label: context.t('issues.clone.summary'),
                  trailing: Text(
                    context.t('issues.clone.required'),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.accentStrong,
                    ),
                  ),
                  child: TextField(
                    controller: _title,
                    autofocus: true,
                    enabled: !_busy,
                    maxLines: 2,
                    minLines: 1,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => canClone ? _clone() : null,
                    inputFormatters: const [IssueTitleLengthLimit()],
                    decoration: glassInputDecoration(
                      hint: context.t('issues.clone.summaryHint'),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                GlassField(
                  label: context.t(
                    _assigneeIds.length > 1
                        ? 'issues.assignees'
                        : 'issues.assignee',
                  ),
                  child: _ClonePersonField(
                    names: [for (final id in _assigneeIds) _nameOf(id) ?? '?'],
                    onTap: _busy ? null : _pickAssignee,
                  ),
                ),
                const SizedBox(height: 16),
                GlassField(
                  label: context.t('issues.clone.include'),
                  child: Column(
                    children: [
                      GlassOptionRow(
                        title: context.t('issues.clone.links'),
                        subtitle: context.t('issues.clone.linksHint'),
                        value: _includeLinks,
                        onChanged: _busy
                            ? null
                            : (on) => setState(() => _includeLinks = on),
                      ),
                      GlassOptionRow(
                        title: context.t('issues.clone.sprint'),
                        subtitle: context.t('issues.clone.sprintHint'),
                        value: _includeSprint,
                        onChanged: _busy
                            ? null
                            : (on) => setState(() => _includeSprint = on),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                GlassInfoLine(
                  icon: LucideIcons.info,
                  child: Text(
                    context.t('issues.clone.reporterNote'),
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        GlassModalFooter(
          confirmLabel: context.t('issues.clone.confirm'),
          confirmIcon: LucideIcons.copy,
          busy: _busy,
          onConfirm: canClone ? _clone : null,
        ),
      ],
    );
  }
}

/// Caps the summary at what the server accepts.
///
/// Not [LengthLimitingTextInputFormatter], which counts grapheme clusters: the
/// server's bound counts UTF-16 code units, so a title of 300 emoji passes the
/// field and comes back a 400. Counting the same units the server does means
/// the limit is felt while typing rather than after pressing Klonen.
class IssueTitleLengthLimit extends TextInputFormatter {
  const IssueTitleLengthLimit();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.length <= kIssueTitleMaxChars) return newValue;
    // Refusing the edit rather than truncating it: a paste that would overflow
    // leaves what was already there instead of a silently clipped tail.
    return oldValue;
  }
}

/// The one-line assignee field of the clone dialog: avatars and a name, or the
/// "unassigned" hint, opening the shared people picker where it stands.
class _ClonePersonField extends StatelessWidget {
  const _ClonePersonField({required this.names, this.onTap});

  final List<String> names;
  final void Function(Rect anchorRect)? onTap;

  @override
  Widget build(BuildContext context) {
    final tap = onTap;
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      onTap: tap == null
          ? null
          : () {
              final box = context.findRenderObject() as RenderBox?;
              final rect = (box != null && box.hasSize)
                  ? box.localToGlobal(Offset.zero) & box.size
                  : Rect.zero;
              tap(rect);
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          children: [
            Expanded(child: _value(context)),
            Icon(
              LucideIcons.chevronsUpDown,
              size: 16,
              color: AppColors.inkFaint,
            ),
          ],
        ),
      ),
    );
  }

  Widget _value(BuildContext context) {
    if (names.isEmpty) {
      return Text(
        context.t('issues.unassigned'),
        style: TextStyle(fontSize: 13, color: AppColors.inkFaint),
      );
    }
    if (names.length > 1) {
      return Align(
        alignment: Alignment.centerLeft,
        child: HiveAvatarStack(names: names, size: 26),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        HiveAvatar(name: names.first, size: 22),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            names.first,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
