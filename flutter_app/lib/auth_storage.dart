import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists hotel context and preferences in [SharedPreferences] (survives app restarts
/// reliably on Android). Portal and guest tokens stay in [FlutterSecureStorage].
class AuthStorage {
  AuthStorage._();

  static const _migrationFlag = 'auth_storage_migrated_v2';

  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: false,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
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
  static const _kCustomerGuestName = 'customer_guest_name';
  static const _kCustomerGuestEmail = 'customer_guest_email';
  static const _kCustomerGuestPhone = 'customer_guest_phone';

  static SharedPreferences? _prefs;
  static bool _migrationStarted = false;

  static Future<SharedPreferences> _preferences() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  /// Moves non-secret keys out of secure storage (older builds stored everything there).
  static Future<void> _ensureMigrated() async {
    if (_migrationStarted) return;
    _migrationStarted = true;

    final prefs = await _preferences();
    if (prefs.getBool(_migrationFlag) == true) {
      return;
    }

    Future<void> migrateString(String key) async {
      if (prefs.containsKey(key)) return;
      final legacy = await _secure.read(key: key);
      if (legacy != null && legacy.isNotEmpty) {
        await prefs.setString(key, legacy);
      }
    }

    await migrateString(_kHotelId);
    await migrateString(_kHotelName);
    await migrateString(_kUiSeedColor);
    await migrateString(_kThemeMode);
    await migrateString(_kThemeFabDx);
    await migrateString(_kThemeFabDy);
    await migrateString(_kAppLocale);
    await migrateString(_kIntroSeen);
    await migrateString(_kHotelsDirectoryCache);

    await prefs.setBool(_migrationFlag, true);
  }

  static Future<String?> hotelId() async {
    await _ensureMigrated();
    return (await _preferences()).getString(_kHotelId);
  }

  static Future<String?> hotelName() async {
    await _ensureMigrated();
    return (await _preferences()).getString(_kHotelName);
  }

  static Future<String?> portalToken() => _secure.read(key: _kPortalToken);

  /// `admin`, `staff`, or `super_admin` after portal login or register.
  static Future<String?> portalRole() => _secure.read(key: _kPortalRole);

  static Future<String?> guestToken() => _secure.read(key: _kGuestToken);

  static Future<String?> appLocaleCode() async {
    await _ensureMigrated();
    return (await _preferences()).getString(_kAppLocale);
  }

  static Future<void> setAppLocaleCode(String code) async {
    await _ensureMigrated();
    await (await _preferences()).setString(_kAppLocale, code);
  }

  static Future<bool> hasSeenIntro() async {
    await _ensureMigrated();
    return (await _preferences()).getString(_kIntroSeen) == '1';
  }

  static Future<void> setIntroSeen() async {
    await _ensureMigrated();
    await (await _preferences()).setString(_kIntroSeen, '1');
  }

  static Future<String?> hotelsDirectoryCache() async {
    await _ensureMigrated();
    return (await _preferences()).getString(_kHotelsDirectoryCache);
  }

  static Future<void> setHotelsDirectoryCache(String json) async {
    await _ensureMigrated();
    await (await _preferences()).setString(_kHotelsDirectoryCache, json);
  }

  static Future<void> clearHotelsDirectoryCache() async {
    await _ensureMigrated();
    await (await _preferences()).remove(_kHotelsDirectoryCache);
  }

  /// Last guest contact used on a public booking (for autofill).
  static Future<({String name, String email, String phone})?> customerGuestContact() async {
    await _ensureMigrated();
    final prefs = await _preferences();
    final name = prefs.getString(_kCustomerGuestName);
    final email = prefs.getString(_kCustomerGuestEmail);
    final phone = prefs.getString(_kCustomerGuestPhone);
    if ((name == null || name.isEmpty) &&
        (email == null || email.isEmpty) &&
        (phone == null || phone.isEmpty)) {
      return null;
    }
    return (
      name: name ?? '',
      email: email ?? '',
      phone: phone ?? '',
    );
  }

  static Future<void> setCustomerGuestContact({
    required String name,
    required String email,
    required String phone,
  }) async {
    await _ensureMigrated();
    final prefs = await _preferences();
    await prefs.setString(_kCustomerGuestName, name.trim());
    await prefs.setString(_kCustomerGuestEmail, email.trim());
    await prefs.setString(_kCustomerGuestPhone, phone.trim());
  }

  static Future<String?> uiSeedColorHex() async {
    await _ensureMigrated();
    return (await _preferences()).getString(_kUiSeedColor);
  }

  static Future<String?> themeModePreference() async {
    await _ensureMigrated();
    return (await _preferences()).getString(_kThemeMode);
  }

  static Future<void> setThemeModePreference(String mode) async {
    await _ensureMigrated();
    await (await _preferences()).setString(_kThemeMode, mode);
  }

  static Future<void> setHotelContext({
    required String id,
    required String name,
  }) async {
    await _ensureMigrated();
    final prefs = await _preferences();
    await prefs.setString(_kHotelId, id);
    await prefs.setString(_kHotelName, name);
  }

  static Future<void> setPortalAuth({
    required String token,
    required String role,
  }) async {
    await _secure.write(key: _kPortalToken, value: token);
    await _secure.write(key: _kPortalRole, value: role);
  }

  static Future<void> setGuestToken(String token) =>
      _secure.write(key: _kGuestToken, value: token);

  /// Removes Sanctum portal credentials only (keeps hotel context and guest).
  static Future<void> clearPortalAuth() async {
    await _secure.delete(key: _kPortalToken);
    await _secure.delete(key: _kPortalRole);
  }

  static Future<void> clearGuestAuth() => _secure.delete(key: _kGuestToken);

  static Future<void> setUiSeedColorHex(String hex) async {
    await _ensureMigrated();
    await (await _preferences()).setString(_kUiSeedColor, hex);
  }

  static Future<void> setThemeFabOffset(
    double dxFromRight,
    double dyFromBottom,
  ) async {
    await _ensureMigrated();
    final prefs = await _preferences();
    await prefs.setString(_kThemeFabDx, dxFromRight.toString());
    await prefs.setString(_kThemeFabDy, dyFromBottom.toString());
  }

  static Future<(double, double)?> themeFabOffset() async {
    await _ensureMigrated();
    final prefs = await _preferences();
    final xs = prefs.getString(_kThemeFabDx);
    final ys = prefs.getString(_kThemeFabDy);
    if (xs == null || ys == null) return null;
    final dx = double.tryParse(xs);
    final dy = double.tryParse(ys);
    if (dx == null || dy == null) return null;
    return (dx, dy);
  }

  /// Switch hotel / full reset: clears preferences and secure tokens.
  static Future<void> clearAll() async {
    await _ensureMigrated();
    await (await _preferences()).clear();
    await _secure.deleteAll();
    _migrationStarted = false;
  }
}
