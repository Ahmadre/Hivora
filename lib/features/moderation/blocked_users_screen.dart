import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/moderation_models.dart';
import '../../core/repositories/moderation_repository.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_widgets.dart' show HiveAvatar;
import '../../core/widgets/soft_card.dart';
import '../../core/widgets/status_widgets.dart';
import '../shell/page_chrome.dart';
import '../sprint/modals/glass_modal.dart';

/// The people the signed-in user has blocked, with a way to unblock each.
///
/// A block has to be reversible from somewhere the user can find on their own —
/// it is invisible once it takes effect, so without this screen the only way
/// back would be to stumble across a hidden comment. It lives in the account
/// area next to the other "things I decided about my own experience" settings.
///
/// One request, one list: `/me/blocks` answers with every block the user holds
/// and there is no paged endpoint behind it. The rows are still built lazily, so
/// a person who has muted a great many colleagues costs a list to fetch, not a
/// screenful of widgets to build.
class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  late final ModerationRepository _repository;

  List<BlockedUser> _users = const [];

  /// Whether a load has ever completed. Distinct from "the list is empty": an
  /// empty list is a real answer that earns the empty state, while nothing
  /// having arrived yet is still the spinner's turn.
  bool _loaded = false;
  bool _loading = true;
  String? _errorKey;

  /// Ids currently being unblocked, so a row's button can't be fired twice
  /// while its request is in flight.
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _repository = context.read<ModerationRepository>();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorKey = null;
    });
    try {
      final users = await _repository.blockedUsers();
      if (!mounted) return;
      setState(() {
        _users = users;
        _loaded = true;
        _loading = false;
      });
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorKey = failure.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorKey = 'errors.unexpected';
      });
    }
  }

  Future<void> _unblock(BlockedUser user) async {
    if (!_busy.add(user.userId)) return;
    setState(() {});
    try {
      await _repository.unblockUser(user.userId);
      if (!mounted) return;
      // Drop the row here rather than refetching: the server holds the whole
      // list, so there is no page bookkeeping to keep in step, and the person
      // just asked for this row to be gone — making them watch a round trip
      // first would only make the block look like it is still there.
      setState(() {
        _users = [
          for (final u in _users)
            if (u.userId != user.userId) u,
        ];
      });
      showGlassToast(
        context,
        context.t(
          'moderation.blocked.unblocked',
          variables: {'name': user.displayName},
        ),
        kind: GlassToastKind.success,
      );
    } on ApiFailure catch (failure) {
      if (mounted) showGlassErrorToast(context, context.t(failure.message));
    } catch (_) {
      if (mounted) showGlassErrorToast(context, context.t('errors.unexpected'));
    } finally {
      _busy.remove(user.userId);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageChrome(
      title: context.t('moderation.blocked.title'),
      child: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.accentStrong,
        child: AsyncView(
          isLoading: _loading,
          hasData: _loaded,
          errorKey: _errorKey,
          onRetry: _load,
          builder: (context) {
            final showEmpty = _users.isEmpty;
            // A lazy builder rather than a materialised child list: the whole
            // block list arrives in one response, and only the rows on screen
            // should become widgets.
            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: context.pagePadding,
              itemCount: 1 + (showEmpty ? 1 : _users.length),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Text(
                      context.t('moderation.blocked.intro'),
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  );
                }
                if (showEmpty) {
                  return HiveEmptyState(
                    title: context.t('moderation.blocked.emptyTitle'),
                    message: context.t('moderation.blocked.emptyMessage'),
                  );
                }
                final i = index - 1;
                final user = _users[i];
                return Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
                  child: _BlockedRow(
                    user: user,
                    busy: _busy.contains(user.userId),
                    onUnblock: () => _unblock(user),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _BlockedRow extends StatelessWidget {
  const _BlockedRow({
    required this.user,
    required this.busy,
    required this.onUnblock,
  });

  final BlockedUser user;
  final bool busy;
  final VoidCallback onUnblock;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          HiveAvatar(
            name: user.displayName,
            imageUrl: user.avatarUrl,
            size: 34,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  user.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                if (user.username.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '@${user.username}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          _unblockButton(context),
        ],
      ),
    );
  }

  /// The unblock control: icon-only where the row is tight, labelled where
  /// there is room — the same trade the shell app bar makes with its actions.
  ///
  /// A labelled button does not fit a phone here. "Blockierung aufheben" and a
  /// glyph take most of a 320pt row, leaving a dozen points for the name — and
  /// the name is the entire point of the row, since a block list you cannot read
  /// is one you cannot undo.
  Widget _unblockButton(BuildContext context) {
    final label = context.t('moderation.blocked.unblock');
    final icon = busy
        ? const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(LucideIcons.userCheck, size: 15);
    if (context.isCompact) {
      return IconButton(
        onPressed: busy ? null : onUnblock,
        // Carries the label for pointer users and for screen readers, which is
        // what keeps an icon-only control from being a guess.
        tooltip: label,
        icon: icon,
        style: IconButton.styleFrom(
          foregroundColor: AppColors.ink,
          side: BorderSide(color: AppColors.hairline),
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: busy ? null : onUnblock,
      icon: icon,
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        side: BorderSide(color: AppColors.hairline),
      ),
    );
  }
}
