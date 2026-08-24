import 'package:flutter/services.dart';

/// Short device alert for chat, bookings, and other staff/guest notifications.
class ChatNotificationSound {
  ChatNotificationSound._();

  static DateTime? _lastPlayedAt;

  static Future<void> playNewMessage() => play();

  static Future<void> play() async {
    final now = DateTime.now();
    if (_lastPlayedAt != null &&
        now.difference(_lastPlayedAt!) < const Duration(milliseconds: 900)) {
      return;
    }
    _lastPlayedAt = now;
    try {
      await SystemSound.play(SystemSoundType.alert);
    } catch (_) {
      try {
        await SystemSound.play(SystemSoundType.click);
      } catch (_) {}
    }
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {}
  }
}
