import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Sends guest welcome SMS from the front-desk phone's own SIM (device SMS).
///
/// - Android: tries silent send via [SmsManager] (sender = this phone's number).
/// - iOS: opens Messages composer (Apple does not allow silent SMS); user taps Send.
/// - Never throws into check-in — failures are returned as [DeviceSmsOutcome].
class DeviceGuestWelcomeSms {
  DeviceGuestWelcomeSms._();

  static const _channel = MethodChannel('gloretto/device_sms');

  /// Normalize common PH formats for the device SMS app / SmsManager.
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
    buffer.writeln('Open the MADYAW guest portal and sign in with this password.');
    return buffer.toString().trim();
  }

  /// Best-effort send. Check-in must already have succeeded before calling this.
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

    if (!kIsWeb && Platform.isAndroid) {
      try {
        final raw = await _channel.invokeMethod<dynamic>('sendSms', {
          'phone': phone,
          'body': body,
        });
        final map = raw is Map ? Map<String, dynamic>.from(raw) : const {};
        if (map['sent'] == true) {
          return DeviceSmsOutcome.sentDirect();
        }
        // Permission denied or soft failure — fall through to composer.
      } on PlatformException {
        // Fall through to composer.
      } catch (_) {
        // Fall through to composer.
      }
    }

    return _openComposer(phone: phone, body: body);
  }

  static Future<DeviceSmsOutcome> _openComposer({
    required String phone,
    required String body,
  }) async {
    final uri = Uri(
      scheme: 'sms',
      path: phone,
      queryParameters: {'body': body},
    );
    try {
      final ok = await launchUrl(uri);
      if (ok) {
        return DeviceSmsOutcome.openedComposer();
      }
      return DeviceSmsOutcome.failed('Could not open the Messages app.');
    } catch (e) {
      return DeviceSmsOutcome.failed('$e');
    }
  }
}

enum DeviceSmsMode { sentDirect, openedComposer, skipped, failed }

class DeviceSmsOutcome {
  const DeviceSmsOutcome._(this.mode, this.message);

  final DeviceSmsMode mode;
  final String message;

  factory DeviceSmsOutcome.sentDirect() => const DeviceSmsOutcome._(
        DeviceSmsMode.sentDirect,
        'Welcome SMS sent from this phone.',
      );

  factory DeviceSmsOutcome.openedComposer() => const DeviceSmsOutcome._(
        DeviceSmsMode.openedComposer,
        'Messages opened — tap Send to deliver from this phone’s SIM.',
      );

  factory DeviceSmsOutcome.skipped(String reason) =>
      DeviceSmsOutcome._(DeviceSmsMode.skipped, reason);

  factory DeviceSmsOutcome.failed(String reason) =>
      DeviceSmsOutcome._(DeviceSmsMode.failed, reason);

  bool get didAttempt =>
      mode == DeviceSmsMode.sentDirect || mode == DeviceSmsMode.openedComposer;
}
