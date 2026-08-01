import 'package:flutter/services.dart';

/// Plays a short alert when hotel staff receive a new chat message.
class ChatNotificationSound {
  ChatNotificationSound._();

  static DateTime? _lastPlayedAt;

  /// Debounced so rapid polls do not spam the device speaker.
  static Future<void> playNewMessage() async {
    final now = DateTime.now();
    if (_lastPlayedAt != null &&
        now.difference(_lastPlayedAt!) < const Duration(seconds: 2)) {
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
