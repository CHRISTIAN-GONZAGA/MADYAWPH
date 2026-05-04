import 'package:flutter/material.dart';

import 'intro/app_bootstrap.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GlorettoApp());
}

class GlorettoApp extends StatelessWidget {
  const GlorettoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gloretto',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
        useMaterial3: true,
      ),
      home: const AppBootstrap(),
    );
  }
}
