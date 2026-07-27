import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../dio_client.dart';
import '../flow/guest_portal_flow.dart';
import '../navigation_keys.dart';

/// Handles HTTPS room QR links (camera scan → app → guest password login).
class GuestRoomDeepLink {
  GuestRoomDeepLink._();

  static final AppLinks _appLinks = AppLinks();
  static StreamSubscription<Uri>? _linkSub;
  static bool _initialized = false;

  static const _pendingUrlKey = 'pending_guest_room_qr_url';
  static const _clipboardCheckedKey = 'guest_room_clipboard_checked_v1';

  /// Call once at app startup (before intro finishes).
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null && isGuestRoomQrUri(initial)) {
        await _storePendingUrl(initial.toString());
      }
    } catch (_) {}

    _linkSub ??= _appLinks.uriLinkStream.listen((uri) async {
      if (!isGuestRoomQrUri(uri)) return;
      await _storePendingUrl(uri.toString());
      await consumePendingIfAny();
    });
  }

  static Future<void> dispose() async {
    await _linkSub?.cancel();
    _linkSub = null;
    _initialized = false;
  }

  /// After intro / when app becomes ready — open guest login if a room QR was scanned.
  static Future<void> consumePendingIfAny() async {
    var url = await _takePendingUrl();
    url ??= await _readClipboardRoomUrlOnce();

    if (url == null || url.trim().isEmpty) return;

    await _openGuestLoginFromQrUrl(url.trim());
  }

  static bool isGuestRoomQrUri(Uri uri) {
    if (uri.scheme == 'madyaw' && uri.host == 'guest') {
      return uri.pathSegments.length >= 4 && uri.pathSegments[0] == 'room';
    }

    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return false;
    }

    final host = uri.host.toLowerCase();
    final allowedHost = Uri.parse(kApiOrigin).host.toLowerCase();
    if (host != allowedHost) return false;

    final segments = uri.pathSegments;
    return segments.length >= 5 &&
        segments[0] == 'qr' &&
        segments[1] == 'room' &&
        segments[2].isNotEmpty &&
        segments[3].isNotEmpty &&
        segments[4].isNotEmpty;
  }

  /// Normalize HTTPS or madyaw:// guest room links to the canonical API URL.
  static String? normalizeGuestRoomQrUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    try {
      final uri = Uri.parse(trimmed);
      if (uri.scheme == 'madyaw' &&
          uri.host == 'guest' &&
          uri.pathSegments.length >= 4 &&
          uri.pathSegments[0] == 'room') {
        return '$kApiOrigin/qr/room/'
            '${Uri.encodeComponent(uri.pathSegments[1])}/'
            '${Uri.encodeComponent(uri.pathSegments[2])}/'
            '${Uri.encodeComponent(uri.pathSegments[3])}';
      }
      if (isGuestRoomQrUri(uri)) {
        return uri.replace(query: null, fragment: null).toString();
      }
    } catch (_) {}

    return null;
  }

  static bool isGuestRoomQrUrl(String raw) {
    try {
      return isGuestRoomQrUri(Uri.parse(raw.trim()));
    } catch (_) {
      return false;
    }
  }

  static Future<void> _openGuestLoginFromQrUrl(String url) async {
    final normalized = normalizeGuestRoomQrUrl(url) ?? url;
    try {
      final res = await publicDio().post<Map<String, dynamic>>(
        '/guest/portal/resolve',
        data: {'payload': normalized},
      );
      final hotelId = (res.data?['hotel_id'] ?? '').toString();
      if (hotelId.isEmpty) return;

      final hotelName = (res.data?['hotel_name'] ?? '').toString();
      final roomBound = res.data?['room_bound'] == true ||
          (res.data?['type'] ?? '').toString() == 'room';
      final roomId = (res.data?['room_id'] ?? '').toString();
      final roomNumber = (res.data?['room_number'] ?? '').toString();

      final context = appNavigatorKey.currentContext;
      if (context == null || !context.mounted) return;

      await openGuestPortalLogin(
        context,
        hotelId: hotelId,
        hotelName: hotelName.isEmpty ? null : hotelName,
        roomId: roomId.isEmpty ? null : roomId,
        roomNumber: roomNumber.isEmpty ? null : roomNumber,
        roomBoundFromQr: roomBound && roomId.isNotEmpty,
      );
    } on DioException {
      // Invalid/expired QR — ignore silently on auto-open.
    } catch (_) {}
  }

  static Future<void> _storePendingUrl(String url) async {
    final normalized = normalizeGuestRoomQrUrl(url) ?? url;
    if (!isGuestRoomQrUrl(normalized)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingUrlKey, normalized);
    // Allow clipboard fallback again when a fresh room link arrives.
    await prefs.remove(_clipboardCheckedKey);
  }

  static Future<String?> _takePendingUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_pendingUrlKey);
    if (url != null) {
      await prefs.remove(_pendingUrlKey);
    }
    return url;
  }

  /// One-time clipboard read after fresh install (landing page copies room URL).
  static Future<String?> _readClipboardRoomUrlOnce() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_clipboardCheckedKey) == true) return null;

    await prefs.setBool(_clipboardCheckedKey, true);

    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (isGuestRoomQrUrl(text)) return text;
    } catch (_) {}

    return null;
  }
}
