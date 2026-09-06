import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../sprint_format.dart';
import 'glass_modal.dart';

/// Result of the create-sprint modal.
class CreateSprintData {
  const CreateSprintData({
    required this.name,
    required this.goal,
    required this.start,
    required this.end,
  });

  final String name;
  final String? goal;
  final DateTime start;
  final DateTime end;
}

/// Liquid-Glass "Create sprint" modal. Returns [CreateSprintData] or null.
Future<CreateSprintData?> showCreateSprintDialog(
  BuildContext context, {
  required int nextNumber,
  DateTime? defaultStart,
}) {
  return showGlassModal<CreateSprintData>(
    context,
    builder: (_) =>
        _CreateSprintBody(nextNumber: nextNumber, defaultStart: defaultStart),
  );
}

class _CreateSprintBody extends StatefulWidget {
  const _CreateSprintBody({required this.nextNumber, this.defaultStart});

  final int nextNumber;
  final DateTime? defaultStart;

  @override
  State<_CreateSprintBody> createState() => _CreateSprintBodyState();
}

class _CreateSprintBodyState extends State<_CreateSprintBody> {
  late final TextEditingController _name = TextEditingController(
    text: 'Sprint ${widget.nextNumber}',
  );
  final _goal = TextEditingController();
  int _weeks = 2; // index+1; default 2 weeks
  late DateTime _start =
      widget.defaultStart ?? DateTime.now().add(const Duration(days: 1));

  DateTime get _end => autoEndDate(_start, _weeks);

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _goal.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final picked = await showGlassDatePicker(
      context,
      title: context.t('issues.startDate'),
      initialDate: _start,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked != null) setState(() => _start = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: LucideIcons.rocket,
          title: context.t('sprint.create.title'),
          subtitle: context.t('sprint.create.sub'),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 6, 22, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GlassField(
                  label: context.t('sprint.name'),
                  child: TextField(
                    controller: _name,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: glassInputDecoration(),
                  ),
                ),
                const SizedBox(height: 16),
                GlassField(
                  label: context.t('sprint.goal'),
                  trailing: Text(
                    context.t('sprint.optional'),
                    style: TextStyle(fontSize: 11, color: AppColors.inkFaint),
                  ),
                  child: TextField(
                    controller: _goal,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 2,
                    maxLines: 4,
                    decoration: glassInputDecoration(
                      hint: context.t('sprint.goalHint'),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                GlassField(
                  label: context.t('sprint.duration'),
                  child: GlassSegmented(
                    labels: [
                      for (var w = 1; w <= 4; w++)
                        w == 1
                            ? context.t('sprint.week')
                            : context.t(
                                'sprint.weeksN',
                                variables: {'count': '$w'},
                              ),
                    ],
                    selected: _weeks - 1,
                    onChanged: (i) => setState(() => _weeks = i + 1),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: GlassField(
                        label: context.t('sprint.startDate'),
                        child: _DateButton(
                          label: prettyDate(_start),
                          onTap: _pickStart,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GlassField(
                        label: context.t('sprint.endDate'),
                        trailing: Text(
                          context.t('sprint.auto'),
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.inkFaint,
                          ),
                        ),
                        child: _DateButton(
                          label: prettyDate(_end),
                          muted: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        GlassModalFooter(
          confirmLabel: context.t('sprint.create.cta'),
          hint: Text(
            '${prettyDate(_start)} → ${prettyDate(_end)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
          ),
          onConfirm: _name.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(
                  CreateSprintData(
                    name: _name.text.trim(),
                    goal: _goal.text.trim().isEmpty ? null : _goal.text.trim(),
                    start: _start,
                    end: _end,
                  ),
                ),
        ),
      ],
    );
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton({required this.label, this.onTap, this.muted = false});

  final String label;
  final VoidCallback? onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface.withValues(alpha: muted ? 0.4 : 0.7),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.hairline),
          ),
          alignment: AlignmentDirectional.centerStart,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: muted ? AppColors.inkSoft : AppColors.ink,
                  ),
                ),
              ),
              if (!muted)
                Icon(LucideIcons.calendar, size: 15, color: AppColors.inkSoft),
            ],
          ),
        ),
      ),
    );
  }
}
