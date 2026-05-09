import 'package:flutter/material.dart';

import 'auth_storage.dart';
import 'dio_client.dart';

final ValueNotifier<Color> themeSeedColorNotifier =
    ValueNotifier<Color>(const Color(0xFF1565C0));

final ValueNotifier<ThemeMode> themeModeNotifier =
    ValueNotifier<ThemeMode>(ThemeMode.light);

ThemeMode _parseThemeMode(String? raw) {
  switch (raw) {
    case 'dark':
      return ThemeMode.dark;
    case 'system':
      return ThemeMode.system;
    case 'light':
    default:
      return ThemeMode.light;
  }
}

String _themeModeToStorage(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.dark:
      return 'dark';
    case ThemeMode.system:
      return 'system';
    case ThemeMode.light:
      return 'light';
  }
}

Future<void> loadThemeMode() async {
  final raw = await AuthStorage.themeModePreference();
  themeModeNotifier.value = _parseThemeMode(raw);
}

Future<void> setThemeMode(ThemeMode mode) async {
  themeModeNotifier.value = mode;
  await AuthStorage.setThemeModePreference(_themeModeToStorage(mode));
}

String _toHex(Color c) =>
    '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';

Color? _fromHex(String? hex) {
  if (hex == null) return null;
  final s = hex.trim().replaceAll('#', '');
  if (s.length != 6) return null;
  final v = int.tryParse(s, radix: 16);
  if (v == null) return null;
  return Color(0xFF000000 | v);
}

Future<void> loadThemeSeedColor() async {
  final hex = await AuthStorage.uiSeedColorHex();
  final c = _fromHex(hex);
  if (c != null) {
    themeSeedColorNotifier.value = c;
  }
}

Future<void> setThemeSeedColor(Color c) async {
  themeSeedColorNotifier.value = c;
  await AuthStorage.setUiSeedColorHex(_toHex(c));

  // Best-effort: persist per-user theme on backend when logged in.
  try {
    await portalDio()
        .put('/theme', data: {'theme_color': _toHex(c), 'scope': 'user'});
  } catch (_) {}
}
