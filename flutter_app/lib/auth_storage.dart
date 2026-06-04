import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure keys for hotel context, Sanctum portal, and guest portal tokens.
class AuthStorage {
  AuthStorage._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _kHotelId = 'hotel_id';
  static const _kHotelName = 'hotel_name';
  static const _kPortalToken = 'portal_token';
  static const _kPortalRole = 'portal_role';
  static const _kGuestToken = 'guest_token';
  static const _kUiSeedColor = 'ui_seed_color';
  static const _kThemeMode = 'ui_theme_mode';
  static const _kThemeFabDx = 'theme_fab_dx';
  static const _kThemeFabDy = 'theme_fab_dy';
  static const _kAppLocale = 'app_locale';
  static const _kIntroSeen = 'intro_seen';
  static const _kHotelsDirectoryCache = 'hotels_directory_cache';

  static Future<String?> hotelId() => _storage.read(key: _kHotelId);

  static Future<String?> hotelName() => _storage.read(key: _kHotelName);

  static Future<String?> portalToken() => _storage.read(key: _kPortalToken);

  /// `admin` or `staff` after portal login or register.
  static Future<String?> portalRole() => _storage.read(key: _kPortalRole);

  static Future<String?> guestToken() => _storage.read(key: _kGuestToken);

  static Future<String?> appLocaleCode() => _storage.read(key: _kAppLocale);

  static Future<void> setAppLocaleCode(String code) =>
      _storage.write(key: _kAppLocale, value: code);

  /// After first completed intro, skip splash on later launches for faster startup.
  static Future<bool> hasSeenIntro() async =>
      (await _storage.read(key: _kIntroSeen)) == '1';

  static Future<void> setIntroSeen() =>
      _storage.write(key: _kIntroSeen, value: '1');

  /// Cached JSON from GET /hotels for instant picker UI while refreshing.
  static Future<String?> hotelsDirectoryCache() =>
      _storage.read(key: _kHotelsDirectoryCache);

  static Future<void> setHotelsDirectoryCache(String json) =>
      _storage.write(key: _kHotelsDirectoryCache, value: json);

  static Future<void> clearHotelsDirectoryCache() =>
      _storage.delete(key: _kHotelsDirectoryCache);

  /// Hex like "#2563eb" (seed color for Material3).
  static Future<String?> uiSeedColorHex() => _storage.read(key: _kUiSeedColor);

  /// `light`, `dark`, or `system`.
  static Future<String?> themeModePreference() =>
      _storage.read(key: _kThemeMode);

  static Future<void> setThemeModePreference(String mode) =>
      _storage.write(key: _kThemeMode, value: mode);

  static Future<void> setHotelContext(
      {required String id, required String name}) async {
    await _storage.write(key: _kHotelId, value: id);
    await _storage.write(key: _kHotelName, value: name);
  }

  static Future<void> setPortalAuth(
      {required String token, required String role}) async {
    await _storage.write(key: _kPortalToken, value: token);
    await _storage.write(key: _kPortalRole, value: role);
  }

  static Future<void> setGuestToken(String token) =>
      _storage.write(key: _kGuestToken, value: token);

  /// Removes Sanctum portal credentials only (keeps hotel context and guest).
  static Future<void> clearPortalAuth() async {
    await _storage.delete(key: _kPortalToken);
    await _storage.delete(key: _kPortalRole);
  }

  static Future<void> clearGuestAuth() => _storage.delete(key: _kGuestToken);

  static Future<void> setUiSeedColorHex(String hex) =>
      _storage.write(key: _kUiSeedColor, value: hex);

  /// Last FAB position for theme picker (logical px from bottom-right anchor).
  static Future<void> setThemeFabOffset(double dxFromRight, double dyFromBottom) async {
    await _storage.write(key: _kThemeFabDx, value: dxFromRight.toString());
    await _storage.write(key: _kThemeFabDy, value: dyFromBottom.toString());
  }

  static Future<(double, double)?> themeFabOffset() async {
    final xs = await _storage.read(key: _kThemeFabDx);
    final ys = await _storage.read(key: _kThemeFabDy);
    if (xs == null || ys == null) return null;
    final dx = double.tryParse(xs);
    final dy = double.tryParse(ys);
    if (dx == null || dy == null) return null;
    return (dx, dy);
  }

  /// Full sign-out / switch hotel: clears all persisted auth.
  static Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
