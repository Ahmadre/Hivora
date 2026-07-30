import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/features/git/widgets/deployment_panel.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Reproduces the crash reported when expanding the "Create branch" dropdown in
/// the issue deployment panel for a connected repository.
void main() {
  final project = Project.fromJson(const {
    'id': 'p1',
    'key': 'HIN',
    'name': 'hinata-app',
    'workflowStates': [
      {'id': 's1', 'name': 'In Progress', 'hue': 70},
      {'id': 's2', 'name': 'In Review', 'hue': 300},
    ],
    'git': {
      'provider': 'github',
      'owner': 'hinata-platform',
      'repo': 'hinata-app',
      'method': 'oauth',
      'branchTemplate': '{key}-{summary}',
      'automation': {
        'branchCreated': {'on': true, 'toStateId': 's1'},
        'prOpened': {'on': true, 'toStateId': 's2'},
        'smartCommits': true,
      },
    },
  });

  const issue = Issue(
    id: 'i1',
    projectId: 'p1',
    readableId: 'HIN-18',
    title: 'Restore drag-handle focus ring after a drop',
    state: 'Open',
  );

  Widget host(double width) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: SingleChildScrollView(
            child: DeploymentPanel(
              issue: issue,
              project: project,
              onConnectInSettings: () {},
              onProjectChanged: (_) {},
            ),
          ),
        ),
      ),
    ),
  );

  // The action rows label themselves via context.t (i18next); without a
  // localization delegate wired in, context.t echoes the raw key, so we tap the
  // rows by their (language-agnostic) leading icon instead of the visible text.
  testWidgets('expanding Create branch does not throw', (tester) async {
    await tester.pumpWidget(host(380));
    await tester.tap(find.byIcon(LucideIcons.gitBranch));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanding Create commit does not throw', (tester) async {
    await tester.pumpWidget(host(380));
    await tester.tap(find.byIcon(LucideIcons.gitCommitHorizontal));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
