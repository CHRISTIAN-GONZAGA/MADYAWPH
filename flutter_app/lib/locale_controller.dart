import 'package:flutter/material.dart';

import 'auth_storage.dart';
import 'l10n/app_strings.dart';

/// Persisted UI language for the whole app.
final ValueNotifier<Locale> appLocaleNotifier = ValueNotifier(AppLocales.defaultLocale);

class AppLocales {
  AppLocales._();

  static const defaultLocale = Locale('en');

  static const supported = <Locale>[
    Locale('en'),
    Locale('fil'),
    Locale('zh'),
    Locale('ja'),
    Locale('ko'),
    Locale('es'),
    Locale('fr'),
    Locale('de'),
    Locale('pt'),
    Locale('ar'),
    Locale('hi'),
    Locale('vi'),
    Locale('th'),
    Locale('id'),
    Locale('ms'),
    Locale('it'),
    Locale('ru'),
    Locale('nl'),
    Locale('pl'),
    Locale('tr'),
  ];

  static String code(Locale locale) => locale.languageCode;

  static String label(Locale locale) {
    return AppStrings.languageName(code(locale));
  }

  static Future<void> hydrate() async {
    final saved = await AuthStorage.appLocaleCode();
    if (saved != null && saved.isNotEmpty) {
      appLocaleNotifier.value = Locale(saved);
    }
  }

  static Future<void> setLocale(Locale locale) async {
    appLocaleNotifier.value = locale;
    await AuthStorage.setAppLocaleCode(code(locale));
  }
}

extension LocaleContext on BuildContext {
  String tr(String key) => AppStrings.t(appLocaleNotifier.value, key);
}
