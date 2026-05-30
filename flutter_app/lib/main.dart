import 'package:flutter/material.dart';

import 'intro/app_bootstrap.dart';
import 'locale_controller.dart';
import 'theme_controller.dart';
import 'ui/app_theme.dart';
import 'ui/design_tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Future.wait<void>([
    loadThemeSeedColor(),
    loadThemeMode(),
    AppLocales.hydrate(),
  ]);
  runApp(const MadyawPhApp());
}

class MadyawPhApp extends StatelessWidget {
  const MadyawPhApp({super.key});

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
                  themeAnimationDuration: UiTokens.dStd,
                  themeAnimationCurve: UiTokens.easeOperational,
                  themeMode: mode,
                  theme: AppTheme.light(seed),
                  darkTheme: AppTheme.dark(seed),
                  home: const AppBootstrap(),
                );
              },
            );
          },
        );
      },
    );
  }
}
