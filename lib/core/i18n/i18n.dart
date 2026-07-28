import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:i18next/i18next.dart';

/// Central i18next wiring. Translations live in `assets/i18n/<lang>/common.json`.
abstract final class I18n {
  static const supportedLocales = [Locale('en'), Locale('de')];

  static const localeNames = {
    'en': 'English (UK)',
    'de': 'Deutsch (Deutschland)',
  };

  static List<LocalizationsDelegate<dynamic>> delegates() => [
    I18NextLocalizationDelegate(
      locales: supportedLocales,
      dataSource: AssetBundleLocalizationDataSource(bundlePath: 'assets/i18n'),
      // escapeValue defaults to true, which HTML-escapes interpolated
      // values (e.g. a repo slug's "/" becomes "&#x2F;"). That's meant for
      // HTML output; Flutter Text widgets render plain text, so it only
      // corrupts our strings. Disable it so interpolated values stay literal.
      options: const I18NextOptions(
        fallbackNamespaces: ['common'],
        escapeValue: false,
      ),
    ),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];
}

extension I18nContext on BuildContext {
  /// Translate [key] from the `common` namespace, e.g. `context.t('nav.dashboard')`.
  ///
  /// When [key] isn't a known translation key, i18next echoes it back prefixed
  /// with the namespace (`common:...`). That happens for server-side error
  /// messages, which arrive already localized (the backend honours our
  /// `Accept-Language` header) and should be shown verbatim. So on a miss we
  /// return the raw [key] instead of the namespaced fallback.
  String t(String key, {Map<String, dynamic>? variables, int? count}) {
    final i18next = I18Next.of(this);
    if (i18next == null) return key;
    final result = i18next.t('common:$key', variables: variables, count: count);
    if (result == 'common:$key' || result == key) return key;
    return result;
  }
}
