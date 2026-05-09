import 'package:flutter/material.dart';

import 'intro/app_bootstrap.dart';
import 'theme_controller.dart';
import 'ui/app_theme.dart';
import 'ui/design_tokens.dart';
import 'widgets/theme_fab.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  loadThemeSeedColor();
  runApp(const MadyawPhApp());
}

class MadyawPhApp extends StatelessWidget {
  const MadyawPhApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: themeSeedColorNotifier,
      builder: (context, seed, _) {
        return MaterialApp(
          title: 'MADYAWPH',
          debugShowCheckedModeBanner: false,
          themeAnimationDuration: UiTokens.dStd,
          themeAnimationCurve: UiTokens.easeOperational,
          themeMode: ThemeMode.system,
          theme: AppTheme.light(seed),
          darkTheme: AppTheme.dark(seed),
          builder: (context, child) {
            return Stack(
              fit: StackFit.expand,
              children: [
                if (child != null) child,
                const ThemeFab(),
              ],
            );
          },
          home: const AppBootstrap(),
        );
      },
    );
  }
}
