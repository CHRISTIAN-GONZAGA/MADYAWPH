import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'intro/app_bootstrap.dart';
import 'locale_controller.dart';
import 'navigation_keys.dart';
import 'portal_session_lifecycle.dart';
import 'theme_controller.dart';
import 'ui/app_theme.dart';
import 'ui/design_tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Future.wait<dynamic>([
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
                return PortalSessionLifecycle(
                  child: MaterialApp(
                    navigatorKey: appNavigatorKey,
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
                    home: const AppBootstrap(),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
