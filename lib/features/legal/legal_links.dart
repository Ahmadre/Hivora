import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';

/// The app's legal documents are hosted centrally on the project website so
/// they are reachable independently of any server instance (store listings
/// reference the same URLs). `/privacy-policy` and `/terms-of-service` are
/// language-neutral entry points; the language-specific pages live under
/// `/{lang}/{slug}`.
const String _legalBaseUrl = 'https://hinata.ahmadre.com';

/// Public URL of a hosted legal page, matching the app's current locale.
Uri legalUrl(BuildContext context, String slug) {
  final lang = Localizations.localeOf(context).languageCode == 'de'
      ? 'de'
      : 'en';
  return Uri.parse('$_legalBaseUrl/$lang/$slug');
}

/// Opens the hosted privacy policy in the external browser.
Future<void> openPrivacyPolicy(BuildContext context) => launchUrl(
  legalUrl(context, 'privacy-policy'),
  mode: LaunchMode.externalApplication,
);

/// Opens the hosted terms of service in the external browser.
Future<void> openTermsOfService(BuildContext context) => launchUrl(
  legalUrl(context, 'terms-of-service'),
  mode: LaunchMode.externalApplication,
);

/// A centred pair of links to the hosted legal pages (terms of service +
/// privacy policy), used as a footer in the auth area (login / register).
class LegalLinks extends StatelessWidget {
  const LegalLinks({super.key});

  @override
  Widget build(BuildContext context) {
    final linkStyle = TextStyle(
      color: AppColors.textSecondary,
      fontSize: 13,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.textSecondary,
    );
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      children: [
        InkWell(
          onTap: () => openTermsOfService(context),
          child: Text(context.t('auth.termsOfService'), style: linkStyle),
        ),
        Text('·', style: TextStyle(color: AppColors.textSecondary)),
        InkWell(
          onTap: () => openPrivacyPolicy(context),
          child: Text(context.t('auth.privacyPolicy'), style: linkStyle),
        ),
      ],
    );
  }
}
