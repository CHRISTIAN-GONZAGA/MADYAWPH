import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'auth_storage.dart';
import 'intro/app_bootstrap.dart';
import 'locale_controller.dart';
import 'theme_controller.dart';
import 'ui/app_theme.dart';
import 'ui/design_tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await Future.wait<dynamic>([
    loadThemeSeedColor(),
    loadThemeMode(),
    AppLocales.hydrate(),
    AuthStorage.hasSeenIntro(),
  ]);
  final skipIntro = prefs[3] as bool;
  runApp(MadyawPhApp(skipIntro: skipIntro));
}

class MadyawPhApp extends StatelessWidget {
  const MadyawPhApp({super.key, this.skipIntro = false});

  final bool skipIntro;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: themeSeedColorNotifier,
      builder: (context, seed, _) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: themeModeNotifier,
          builder: (context, mode, _) {
            return ValueListenableBuilder<Locale>(
              valueListenable: appLocaleNotifier,
              builder: (context, appLocale, _) {
                return MaterialApp(
                  title: 'MADYAWPH',
                  debugShowCheckedModeBanner: false,
                  locale: appLocale,
                  supportedLocales: AppLocales.supported,
                  localizationsDelegates: const [
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  themeAnimationDuration: UiTokens.dStd,
                  themeAnimationCurve: UiTokens.easeOperational,
                  themeMode: mode,
                  theme: AppTheme.light(seed),
                  darkTheme: AppTheme.dark(seed),
                  home: AppBootstrap(skipIntro: skipIntro),
                );
              },
            );
          },
        );
      },
    );
  }
}
