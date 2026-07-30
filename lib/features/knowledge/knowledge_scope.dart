import 'package:flutter/widgets.dart';

import 'data/knowledge_models.dart';
import 'data/knowledge_repository.dart';

/// Ambient access to the [KnowledgeRepository] plus the navigation callbacks the
/// KB shell uses (jump to an article / peek a person). Smart-link resolution and
/// issue navigation live in the separate `SmartLinkScope`.
class KnowledgeScope extends InheritedWidget {
  const KnowledgeScope({
    super.key,
    required this.repo,
    required this.openArticle,
    required this.openUser,
    required super.child,
  });

  final KnowledgeRepository repo;
  final void Function(String articleId) openArticle;
  final void Function(KbUser user) openUser;

  static KnowledgeScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<KnowledgeScope>();
    assert(scope != null, 'No KnowledgeScope found in context');
    return scope!;
  }

  @override
  bool updateShouldNotify(KnowledgeScope oldWidget) => repo != oldWidget.repo;
}
