import 'package:flutter/material.dart';

import 'intro/app_bootstrap.dart';
import 'theme_controller.dart';
import 'ui/app_theme.dart';
import 'ui/design_tokens.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  loadThemeSeedColor();
  runApp(const GlorettoApp());
}

class GlorettoApp extends StatelessWidget {
  const GlorettoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: themeSeedColorNotifier,
      builder: (context, seed, _) {
        return MaterialApp(
          title: 'Gloretto',
          debugShowCheckedModeBanner: false,
          themeAnimationDuration: UiTokens.dStd,
          themeAnimationCurve: UiTokens.easeOperational,
          themeMode: ThemeMode.system,
          theme: AppTheme.light(seed),
          darkTheme: AppTheme.dark(seed),
          home: const AppBootstrap(),
        );
      },
    );
  }
}
