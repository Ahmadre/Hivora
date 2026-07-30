import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/git_dev_info.dart';
import 'package:hinata/features/git/widgets/copy_field.dart';
import 'package:hinata/features/git/widgets/dev_rows.dart';

/// Verifies the two acceptance checks called out in GIT-INTEGRATION.md §9:
///  • terminology is provider-adaptive (GitHub/Bitbucket "PR", GitLab "MR");
///  • a long branch name never causes horizontal overflow.
void main() {
  group('provider-adaptive terminology (PR ↔ MR)', () {
    test('GitHub → Pull request / PR', () {
      expect(GitProvider.github.prTerm, 'Pull request');
      expect(GitProvider.github.prTermPlural, 'Pull requests');
      expect(GitProvider.github.prShort, 'PR');
      expect(GitProvider.github.ownerWord, 'organization');
      expect(GitProvider.github.unit, 'repository');
    });

    test('GitLab → Merge request / MR', () {
      expect(GitProvider.gitlab.prTerm, 'Merge request');
      expect(GitProvider.gitlab.prTermPlural, 'Merge requests');
      expect(GitProvider.gitlab.prShort, 'MR');
      expect(GitProvider.gitlab.ownerWord, 'group');
      expect(GitProvider.gitlab.unit, 'project');
    });

    test('Bitbucket → Pull request / PR', () {
      expect(GitProvider.bitbucket.prTerm, 'Pull request');
      expect(GitProvider.bitbucket.prShort, 'PR');
      expect(GitProvider.bitbucket.ownerWord, 'workspace');
    });

    test('raw provider id resolves', () {
      expect(gitProviderFrom('github'), GitProvider.github);
      expect(gitProviderFrom('gitlab'), GitProvider.gitlab);
      expect(gitProviderFrom('bitbucket'), GitProvider.bitbucket);
      expect(gitProviderFrom('nope'), isNull);
    });
  });

  group('no horizontal overflow with a long branch name', () {
    const longBranch =
        'HIN-241-redesign-the-agile-board-with-calmer-column-rhythm-and-honey-active-header';

    testWidgets('BranchRow ellipsizes inside a narrow rail', (tester) async {
      await tester.pumpWidget(
        _host(
          width: 240,
          child: BranchRow(
            branch: const GitBranch(
              name: longBranch,
              base: 'main',
              ahead: 6,
              behind: 2,
            ),
            names: const {},
            avatars: const {},
            onOpen: () {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('CopyField scrolls a long command instead of overflowing', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          width: 240,
          child: const CopyField(text: 'git checkout -b $longBranch'),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('GitLab Pr/MR row builds without overflow', (tester) async {
      await tester.pumpWidget(
        _host(
          width: 260,
          child: PrRow(
            pr: const GitPullRequest(
              number: 57,
              title:
                  'API-230 Serialize token refresh across every request path',
              state: PrState.open,
              reviewerIds: ['u1', 'u2'],
              approvals: 1,
              changesRequested: 1,
            ),
            provider: GitProvider.gitlab,
            names: const {'u1': 'Amara', 'u2': 'Bela'},
            avatars: const {},
            busy: false,
            onMerge: () {},
            onReady: () {},
            onOpen: () {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}

Widget _host({required double width, required Widget child}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  home: Scaffold(
    body: Center(
      child: SizedBox(width: width, child: child),
    ),
  ),
);
