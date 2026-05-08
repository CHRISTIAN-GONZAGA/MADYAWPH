import 'package:flutter/material.dart';

import 'intro/app_bootstrap.dart';
import 'theme_controller.dart';

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
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: seed),
            useMaterial3: true,
          ),
          home: const AppBootstrap(),
        );
      },
    );
  }
}
