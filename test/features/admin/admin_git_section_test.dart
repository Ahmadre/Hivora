import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/features/admin/sections/admin_git_section.dart';

/// The admin Git-integration section must lay out cleanly at any width and in
/// either provider state (live / demo) — no horizontal overflow, no exceptions.
void main() {
  // A long client id + webhook URL that would blow a fixed-width row apart.
  const longId =
      'Iv1.a1b2c3d4e5f6a7b8-organization-wide-oauth-app-client-identifier';
  const longUrl =
      'https://track.some-really-long-subdomain.example-company.com/api/v1/webhooks/git';

  Map<String, dynamic> settings({required bool live}) => {
    'gitIntegration': {
      'githubClientId': longId,
      'githubConfigured': live,
      'gitlabClientId': longId,
      'gitlabConfigured': !live,
      'bitbucketClientId': '',
      'bitbucketConfigured': false,
      'webhookBaseUrl': longUrl,
      'tokenSecretConfigured': live,
    },
  };

  Widget host(double width, Map<String, dynamic> s) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: SingleChildScrollView(child: AdminGitSection(settings: s)),
        ),
      ),
    ),
  );

  for (final width in <double>[260, 320, 420]) {
    testWidgets('renders without overflow at ${width}px (mixed states)', (
      tester,
    ) async {
      await tester.pumpWidget(host(width, settings(live: true)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('renders with all providers in demo state', (tester) async {
    await tester.pumpWidget(host(300, settings(live: false)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('creates the gitIntegration draft map on first edit', (
    tester,
  ) async {
    final s = <String, dynamic>{};
    await tester.pumpWidget(host(360, s));
    await tester.pumpAndSettle();
    // Accessing the section builds the lazy sub-map so the shell can persist it.
    expect(s['gitIntegration'], isA<Map<String, dynamic>>());
  });
}
