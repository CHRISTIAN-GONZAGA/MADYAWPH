import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Sends guest welcome SMS from the front-desk phone's own SIM (device load).
///
/// Android: silent send via [SmsManager] — never opens the Messages app.
/// iOS: Apple blocks silent SMS; returns [DeviceSmsMode.failed] with guidance.
/// Never throws into check-in — failures are returned as [DeviceSmsOutcome].
class DeviceGuestWelcomeSms {
  DeviceGuestWelcomeSms._();

  static const _channel = MethodChannel('gloretto/device_sms');

  /// Normalize common PH formats for SmsManager.
  static String normalizePhone(String raw) {
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    if (digits.startsWith('63') && digits.length >= 12) {
      digits = '0${digits.substring(2)}';
    } else if (digits.startsWith('9') && digits.length == 10) {
      digits = '0$digits';
    }
    return digits;
  }

  static String buildWelcomeBody({
    required String hotelName,
    required String guestName,
    required String roomNumber,
    required String roomPassword,
  }) {
    final hotel = hotelName.trim().isEmpty ? 'the hotel' : hotelName.trim();
    final guest = guestName.trim().isEmpty ? 'Guest' : guestName.trim();
    final room = roomNumber.trim().isEmpty ? 'your room' : roomNumber.trim();
    final password = roomPassword.trim();

    final buffer = StringBuffer()
      ..writeln('Welcome to $hotel, $guest!')
      ..writeln('You are checked in to Room $room.');
    if (password.isNotEmpty) {
      buffer.writeln('Your room password is: $password');
    }
    buffer.writeln(
      'Open the MADYAW guest portal and sign in with this password.',
    );
    return buffer.toString().trim();
  }

  /// Ask for SEND_SMS ahead of check-in so the first send is silent.
  static Future<bool> ensurePermission() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final raw = await _channel.invokeMethod<dynamic>('ensureSmsPermission');
      if (raw is bool) return raw;
      if (raw is Map) {
        return raw['granted'] == true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Silent device-SIM send. Check-in must already have succeeded.
  static Future<DeviceSmsOutcome> sendWelcome({
    required String guestPhone,
    required String hotelName,
    required String guestName,
    required String roomNumber,
    required String roomPassword,
  }) async {
    final phone = normalizePhone(guestPhone);
    if (phone.isEmpty) {
      return DeviceSmsOutcome.skipped('No guest phone number on this booking.');
    }

    final body = buildWelcomeBody(
      hotelName: hotelName,
      guestName: guestName,
      roomNumber: roomNumber,
      roomPassword: roomPassword,
    );

    if (kIsWeb) {
      return DeviceSmsOutcome.failed(
        'Welcome SMS needs the Android staff app (device SIM).',
      );
    }

    if (Platform.isIOS) {
      return DeviceSmsOutcome.failed(
        'Automatic SMS from phone load is not available on iOS. Use an Android front-desk phone.',
      );
    }

    if (!Platform.isAndroid) {
      return DeviceSmsOutcome.failed('Automatic SMS requires Android.');
    }

    try {
      final raw = await _channel.invokeMethod<dynamic>('sendSms', {
        'phone': phone,
        'body': body,
      });
      final map = raw is Map ? Map<String, dynamic>.from(raw) : const {};
      if (map['sent'] == true) {
        return DeviceSmsOutcome.sentDirect();
      }
      final mode = (map['mode'] ?? '').toString();
      if (mode == 'permission_denied') {
        return DeviceSmsOutcome.failed(
          'SMS permission denied. Enable SMS for MADYAW in Android settings, then try again.',
        );
      }
      final detail = (map['error'] ?? map['message'] ?? 'SMS was not sent.')
          .toString();
      return DeviceSmsOutcome.failed(detail);
    } on PlatformException catch (e) {
      return DeviceSmsOutcome.failed(
        e.message?.isNotEmpty == true
            ? e.message!
            : 'Could not send SMS from this phone.',
      );
    } catch (e) {
      return DeviceSmsOutcome.failed('$e');
    }
  }

  /// Convenience: build + send from a server `guest_welcome_sms` payload map.
  static Future<DeviceSmsOutcome> sendFromPayload(
    Map<String, dynamic> payload, {
    String fallbackPhone = '',
    String fallbackGuest = '',
    String fallbackRoom = '',
  }) {
    return sendWelcome(
      guestPhone: (payload['guest_phone'] ?? fallbackPhone).toString(),
      hotelName: (payload['hotel_name'] ?? '').toString(),
      guestName: (payload['guest_name'] ?? fallbackGuest).toString(),
      roomNumber: (payload['room_number'] ?? fallbackRoom).toString(),
      roomPassword: (payload['room_access_password'] ?? '').toString(),
    );
  }
}

enum DeviceSmsMode { sentDirect, skipped, failed }

class DeviceSmsOutcome {
  const DeviceSmsOutcome._(this.mode, this.message);

  final DeviceSmsMode mode;
  final String message;

  factory DeviceSmsOutcome.sentDirect() => const DeviceSmsOutcome._(
        DeviceSmsMode.sentDirect,
        'Welcome SMS sent from this phone.',
      );

  factory DeviceSmsOutcome.skipped(String reason) =>
      DeviceSmsOutcome._(DeviceSmsMode.skipped, reason);

  factory DeviceSmsOutcome.failed(String reason) =>
      DeviceSmsOutcome._(DeviceSmsMode.failed, reason);

  bool get didSend => mode == DeviceSmsMode.sentDirect;
}
