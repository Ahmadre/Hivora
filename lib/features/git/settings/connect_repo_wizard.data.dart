part of 'connect_repo_wizard.dart';

// [titleKey] is either an i18n key (github rows: human labels) or a literal
// OAuth scope name kept verbatim (gitlab/bitbucket rows like `api`, `account`).
// [descKey]/[scopeKey] always resolve through i18n. See [_permTitle].
typedef _Scope = ({
  String titleKey,
  String descKey,
  String scopeKey,
  bool required,
});

const Map<String, List<_Scope>> _permsByProvider = {
  'github': [
    (
      titleKey: 'git.connect.perms.ghMeta',
      descKey: 'git.connect.perms.ghMetaDesc',
      scopeKey: 'read',
      required: true,
    ),
    (
      titleKey: 'git.connect.perms.ghContents',
      descKey: 'git.connect.perms.ghContentsDesc',
      scopeKey: 'readWrite',
      required: false,
    ),
    (
      titleKey: 'git.connect.perms.ghPrs',
      descKey: 'git.connect.perms.ghPrsDesc',
      scopeKey: 'readWrite',
      required: false,
    ),
    (
      titleKey: 'git.connect.perms.ghIssues',
      descKey: 'git.connect.perms.ghIssuesDesc',
      scopeKey: 'readWrite',
      required: false,
    ),
    (
      titleKey: 'git.connect.perms.ghChecks',
      descKey: 'git.connect.perms.ghChecksDesc',
      scopeKey: 'read',
      required: false,
    ),
    (
      titleKey: 'git.connect.perms.ghHooks',
      descKey: 'git.connect.perms.ghHooksDesc',
      scopeKey: 'readWrite',
      required: false,
    ),
  ],
  'gitlab': [
    (
      titleKey: 'api',
      descKey: 'git.connect.perms.glApiDesc',
      scopeKey: 'full',
      required: true,
    ),
    (
      titleKey: 'read_repository',
      descKey: 'git.connect.perms.glReadDesc',
      scopeKey: 'read',
      required: false,
    ),
    (
      titleKey: 'write_repository',
      descKey: 'git.connect.perms.glWriteDesc',
      scopeKey: 'write',
      required: false,
    ),
    (
      titleKey: 'git.connect.perms.ghHooks',
      descKey: 'git.connect.perms.glHooksDesc',
      scopeKey: 'readWrite',
      required: false,
    ),
  ],
  'bitbucket': [
    (
      titleKey: 'account',
      descKey: 'git.connect.perms.bbAccountDesc',
      scopeKey: 'read',
      required: true,
    ),
    (
      titleKey: 'repository',
      descKey: 'git.connect.perms.bbRepoDesc',
      scopeKey: 'read',
      required: false,
    ),
    (
      titleKey: 'pullrequest',
      descKey: 'git.connect.perms.bbPrDesc',
      scopeKey: 'readWrite',
      required: false,
    ),
    (
      titleKey: 'webhook',
      descKey: 'git.connect.perms.bbHookDesc',
      scopeKey: 'readWrite',
      required: false,
    ),
  ],
};

enum _Step { provider, authorize, owner, repo, token }
