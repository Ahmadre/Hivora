import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import 'admin_form_helpers.dart';

/// SSO provider configuration (OIDC, OAuth2, SAML, LDAP, Kerberos, CAS).
class AdminSsoSection extends StatefulWidget {
  const AdminSsoSection({super.key, required this.settings});

  final Map<String, dynamic> settings;

  @override
  State<AdminSsoSection> createState() => _AdminSsoSectionState();
}

class _AdminSsoSectionState extends State<AdminSsoSection> {
  Map<String, dynamic> _section(String name) =>
      (widget.settings[name] ??= <String, dynamic>{}) as Map<String, dynamic>;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminSectionCard(
          icon: LucideIcons.lock,
          title: context.t('admin.sso'),
          subtitle: context.t('admin.ssoHint'),
          children: [
            ProviderTile(
              title: 'OpenID Connect',
              subtitle: context.t('admin.oidcSubtitle'),
              section: _section('oidc'),
              fields: [
                ('displayName', context.t('admin.displayName'), false),
                ('issuerUri', context.t('admin.ssoField.issuerUri'), false),
                ('clientId', context.t('admin.ssoField.clientId'), false),
                (
                  'clientSecret',
                  context.t('admin.ssoField.clientSecret'),
                  true,
                ),
                ('scopes', context.t('admin.ssoField.scopes'), false),
              ],
              onChanged: () => setState(() {}),
            ),
            ProviderTile(
              title: 'OAuth 2.0',
              subtitle: context.t('admin.oauth2Subtitle'),
              section: _section('oauth2'),
              fields: [
                ('displayName', context.t('admin.displayName'), false),
                (
                  'authorizationUri',
                  context.t('admin.ssoField.authorizationUri'),
                  false,
                ),
                ('tokenUri', context.t('admin.ssoField.tokenUri'), false),
                ('userInfoUri', context.t('admin.ssoField.userInfoUri'), false),
                ('clientId', context.t('admin.ssoField.clientId'), false),
                (
                  'clientSecret',
                  context.t('admin.ssoField.clientSecret'),
                  true,
                ),
              ],
              onChanged: () => setState(() {}),
            ),
            ProviderTile(
              title: 'SAML 2.0',
              subtitle: context.t('admin.samlSubtitle'),
              section: _section('saml'),
              fields: [
                ('displayName', context.t('admin.displayName'), false),
                (
                  'idpMetadataUri',
                  context.t('admin.ssoField.idpMetadataUri'),
                  false,
                ),
                ('entityId', context.t('admin.ssoField.entityId'), false),
              ],
              onChanged: () => setState(() {}),
            ),
            ProviderTile(
              title: 'LDAP / Active Directory',
              subtitle: context.t('admin.ldapSubtitle'),
              section: _section('ldap'),
              fields: [
                ('url', context.t('admin.ssoField.ldapUrl'), false),
                ('baseDn', context.t('admin.ssoField.baseDn'), false),
                ('managerDn', context.t('admin.ssoField.managerDn'), false),
                (
                  'managerPassword',
                  context.t('admin.ssoField.managerPassword'),
                  true,
                ),
                (
                  'userSearchBase',
                  context.t('admin.ssoField.userSearchBase'),
                  false,
                ),
                (
                  'userSearchFilter',
                  context.t('admin.ssoField.userSearchFilter'),
                  false,
                ),
              ],
              onChanged: () => setState(() {}),
            ),
            ProviderTile(
              title: 'Kerberos / SPNEGO',
              subtitle: context.t('admin.kerberosSubtitle'),
              section: _section('kerberos'),
              fields: [
                (
                  'servicePrincipal',
                  context.t('admin.ssoField.servicePrincipal'),
                  false,
                ),
                (
                  'keytabLocation',
                  context.t('admin.ssoField.keytabLocation'),
                  false,
                ),
              ],
              onChanged: () => setState(() {}),
            ),
            ProviderTile(
              title: 'CAS',
              subtitle: context.t('admin.casSubtitle'),
              section: _section('cas'),
              fields: [
                (
                  'serverUrlPrefix',
                  context.t('admin.ssoField.casServerUrl'),
                  false,
                ),
                ('serviceUrl', context.t('admin.ssoField.serviceUrl'), false),
              ],
              onChanged: () => setState(() {}),
            ),
          ],
        ),
      ],
    );
  }
}
