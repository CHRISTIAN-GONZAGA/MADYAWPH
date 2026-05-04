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

  static Future<String?> hotelId() => _storage.read(key: _kHotelId);

  static Future<String?> hotelName() => _storage.read(key: _kHotelName);

  static Future<String?> portalToken() => _storage.read(key: _kPortalToken);

  /// `admin` or `staff` after portal login or register.
  static Future<String?> portalRole() => _storage.read(key: _kPortalRole);

  static Future<String?> guestToken() => _storage.read(key: _kGuestToken);

  static Future<void> setHotelContext({required String id, required String name}) async {
    await _storage.write(key: _kHotelId, value: id);
    await _storage.write(key: _kHotelName, value: name);
  }

  static Future<void> setPortalAuth({required String token, required String role}) async {
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

  /// Full sign-out / switch hotel: clears all persisted auth.
  static Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
