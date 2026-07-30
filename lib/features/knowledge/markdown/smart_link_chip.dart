import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/blocs/auth_bloc.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_avatar.dart';
import '../data/knowledge_models.dart' show lucideIcon;
import '../knowledge_tokens.dart';
import 'smart_link_resolver.dart';

/// Inline, clickable, hoverable smart-link chip rendered from a `{{…}}` token.
///
/// - `issue`  → type glyph + public id, tinted by issue type; opens the issue.
///              Missing target → a danger "broken link" chip.
/// - `doc`    → article icon + title, honey accent; opens the article.
/// - `user`   → avatar + first name on a soft accent fill.
///
/// Resolution is delegated to the ambient [SmartLinkResolver] (see
/// [SmartLinkScope]) so the same chip works in the KB and in a real issue.
///
/// On hover (desktop) / long-press (touch) a floating [_SmartPreview] card is
/// shown, anchored to the chip and flipped above when it would overflow the
/// viewport bottom (`opacity 0→1, translateY −4→0, 160 ms`, reduced-motion safe).
class SmartLinkChip extends StatefulWidget {
  const SmartLinkChip({super.key, required this.kind, required this.id});

  final String kind; // issue | doc | user
  final String id;

  @override
  State<SmartLinkChip> createState() => _SmartLinkChipState();
}

class _SmartLinkChipState extends State<SmartLinkChip> {
  OverlayEntry? _entry;
  bool _hovered = false;

  @override
  void dispose() {
    _removePreview();
    super.dispose();
  }

  SmartLinkResolver get _resolver => SmartLinkScope.of(context);

  void _showPreview() {
    if (_entry != null) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    final chipRect = topLeft & box.size;
    final viewport = overlayBox.size;

    final card = _buildPreviewCard();
    if (card == null) return;

    const w = 320.0;
    var left = chipRect.left;
    if (left + w > viewport.width - 12) left = viewport.width - w - 12;
    if (left < 12) left = 12;
    final flipUp = chipRect.bottom + 160 > viewport.height;

    _entry = OverlayEntry(
      builder: (_) => Positioned(
        left: left,
        top: flipUp ? null : chipRect.bottom + 6,
        bottom: flipUp ? viewport.height - chipRect.top + 6 : null,
        width: w,
        child: _SmartPreview(child: card),
      ),
    );
    overlay.insert(_entry!);
  }

  void _removePreview() {
    _entry?.remove();
    _entry = null;
  }

  void _open() {
    switch (widget.kind) {
      case 'issue':
        _resolver.openIssue(widget.id);
      case 'doc':
        _resolver.openDoc(widget.id);
      case 'user':
        _resolver.openPerson(widget.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chip = _buildChip();
    return MouseRegion(
      onEnter: (_) {
        setState(() => _hovered = true);
        _showPreview();
      },
      onExit: (_) {
        setState(() => _hovered = false);
        _removePreview();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _open,
        onLongPress: _showPreview,
        onLongPressUp: _removePreview,
        child: chip,
      ),
    );
  }

  // ── chip face ──
  Widget _buildChip() {
    switch (widget.kind) {
      case 'user':
        final u = _resolver.person(widget.id);
        if (u == null) return _broken('@unknown');
        // A mention of the signed-in user is emphasised in strong amber so "you
        // were tagged" reads at a glance; other mentions keep the soft accent.
        final meId = context.read<AuthBloc>().state.user?.id;
        final isMe = meId != null && meId == widget.id;
        return _chipShell(
          background: isMe
              ? AppColors.accent.withValues(alpha: 0.20)
              : AppColors.accentSoft,
          border: isMe ? AppColors.accent : AppColors.accentLine,
          borderWidth: isMe ? 1.4 : 1,
          padStart: 3,
          children: [
            AppAvatar(name: u.name, radius: 8),
            const SizedBox(width: 5),
            _label(
              u.firstName,
              isMe ? AppColors.accentStrong : AppColors.ink,
              bold: isMe,
            ),
          ],
        );
      case 'issue':
        final it = _resolver.issue(widget.id);
        if (it == null) return _broken(widget.id);
        return _chipShell(
          background: AppColors.surfaceMuted,
          border: _hovered ? it.typeColor : AppColors.hairline,
          children: [
            Icon(lucideIcon(it.typeIcon), size: 13, color: it.typeColor),
            const SizedBox(width: 4),
            Text(
              widget.id,
              style: TextStyle(
                fontFamily: AppTheme.fontMono,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
          ],
        );
      case 'doc':
      default:
        final a = _resolver.doc(widget.id);
        if (a == null) return _broken('Missing article');
        return _chipShell(
          background: AppColors.surfaceMuted,
          border: _hovered ? AppColors.accentLine : AppColors.hairline,
          children: [
            Icon(lucideIcon(a.icon), size: 13, color: KbTokens.accent),
            const SizedBox(width: 4),
            _label(a.title, AppColors.ink),
          ],
        );
    }
  }

  Widget _label(String text, Color color, {bool bold = false}) =>
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            color: color,
          ),
        ),
      );

  Widget _chipShell({
    required Color background,
    required Color border,
    required List<Widget> children,
    double padStart = 5,
    double borderWidth = 1,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 130),
      padding: EdgeInsets.fromLTRB(padStart, 1, 6, 1),
      decoration: BoxDecoration(
        color: background,
        // Pill/stadium corners — smart-links read as rounded chips app-wide.
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: border, width: borderWidth),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Widget _broken(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
    decoration: BoxDecoration(
      color: AppColors.dangerSoft,
      borderRadius: BorderRadius.circular(100),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(lucideIcon('unlink'), size: 12, color: AppColors.danger),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.danger,
            ),
          ),
        ),
      ],
    ),
  );

  // ── preview content ──
  Widget? _buildPreviewCard() {
    if (widget.kind == 'issue') {
      final it = _resolver.issue(widget.id);
      if (it == null) return null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _typeGlyph(it.typeIcon, it.typeColor),
              const SizedBox(width: 9),
              Text(
                widget.id,
                style: TextStyle(
                  fontFamily: AppTheme.fontMono,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkSoft,
                ),
              ),
              const Spacer(),
              _stateChip(it.stateName, it.stateColor),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            it.title,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              height: 1.3,
              letterSpacing: -0.1,
            ),
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (it.assigneeName != null)
                _metaItem(
                  AppAvatar(name: it.assigneeName!, radius: 9),
                  it.assigneeName!.split(' ').first,
                ),
              _metaItem(
                Icon(
                  lucideIcon(it.priorityIcon),
                  size: 13,
                  color: AppColors.inkSoft,
                ),
                it.priorityLabel,
              ),
              if (it.tags.isNotEmpty) _tag(it.tags.first),
            ],
          ),
          _footer(context.t('knowledge.openIssue')),
        ],
      );
    }
    final a = _resolver.doc(widget.id);
    if (a == null) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: AppColors.accentSoft,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Icon(lucideIcon(a.icon), size: 15, color: KbTokens.accent),
            ),
            const SizedBox(width: 9),
            if (a.spaceName != null)
              Flexible(
                child: Text(
                  a.spaceName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: a.spaceColor ?? KbTokens.accent,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          a.title,
          style: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            height: 1.3,
            letterSpacing: -0.1,
          ),
        ),
        if (a.excerpt.isNotEmpty) ...[
          const SizedBox(height: 7),
          Text(
            '${a.excerpt}…',
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.inkSoft,
              height: 1.5,
            ),
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (a.authorName != null)
              _metaItem(
                AppAvatar(name: a.authorName!, radius: 9),
                a.authorName!.split(' ').first,
              ),
            if (a.updated != null)
              _metaItem(
                Icon(lucideIcon('clock'), size: 13, color: AppColors.inkFaint),
                '${a.updated} ago',
              ),
            if (a.reads != null)
              _metaItem(
                Icon(lucideIcon('eye'), size: 13, color: AppColors.inkFaint),
                '${a.reads}',
              ),
          ],
        ),
        _footer(context.t('knowledge.openArticle')),
      ],
    );
  }

  Widget _typeGlyph(String icon, Color color) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Icon(lucideIcon(icon), size: 13, color: color),
    );
  }

  Widget _stateChip(String name, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(
        name,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    ],
  );

  Widget _metaItem(Widget leading, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      leading,
      const SizedBox(width: 5),
      Text(text, style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft)),
    ],
  );

  Widget _tag(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(KbTokens.radiusChip),
      border: Border.all(color: AppColors.hairline2),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
    ),
  );

  Widget _footer(String label) => Padding(
    padding: const EdgeInsets.only(top: 11),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(height: 1, color: AppColors.hairline2),
        const SizedBox(height: 10),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              lucideIcon('corner-down-left'),
              size: 13,
              color: KbTokens.accent,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: KbTokens.accent,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

/// The floating card shell: surface, hairline, card radius, pop shadow + the
/// reference enter animation (opacity 0→1, translateY −4→0, 160 ms), honoring
/// reduced-motion.
class _SmartPreview extends StatefulWidget {
  const _SmartPreview({required this.child});
  final Widget child;

  @override
  State<_SmartPreview> createState() => _SmartPreviewState();
}

class _SmartPreviewState extends State<_SmartPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final card = Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(KbTokens.radiusCard),
          border: Border.all(color: AppColors.hairline),
          boxShadow: [
            BoxShadow(
              color: AppColors.navyDeep.withValues(alpha: 0.18),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: widget.child,
      ),
    );
    if (reduce) return card;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => Opacity(
        opacity: _c.value,
        child: Transform.translate(
          offset: Offset(0, -4 * (1 - _c.value)),
          child: child,
        ),
      ),
      child: card,
    );
  }
}
