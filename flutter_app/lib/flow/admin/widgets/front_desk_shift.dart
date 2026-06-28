import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Active front-desk shift (time in / scheduled time out).
class FrontDeskShift {
  const FrontDeskShift({
    required this.userId,
    required this.hotelId,
    required this.staffName,
    required this.scheduledTimeIn,
    required this.scheduledTimeOut,
    required this.startedAt,
  });

  final String userId;
  final String hotelId;
  final String staffName;
  final DateTime scheduledTimeIn;
  final DateTime scheduledTimeOut;
  final DateTime startedAt;

  bool get canTimeOut =>
      !DateTime.now().isBefore(scheduledTimeOut);

  Duration get timeUntilTimeOut {
    final remaining = scheduledTimeOut.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'hotelId': hotelId,
        'staffName': staffName,
        'scheduledTimeIn': scheduledTimeIn.toIso8601String(),
        'scheduledTimeOut': scheduledTimeOut.toIso8601String(),
        'startedAt': startedAt.toIso8601String(),
      };

  factory FrontDeskShift.fromJson(Map<String, dynamic> json) {
    return FrontDeskShift(
      userId: (json['userId'] ?? '').toString(),
      hotelId: (json['hotelId'] ?? '').toString(),
      staffName: (json['staffName'] ?? '').toString(),
      scheduledTimeIn: DateTime.parse((json['scheduledTimeIn'] ?? '').toString()),
      scheduledTimeOut:
          DateTime.parse((json['scheduledTimeOut'] ?? '').toString()),
      startedAt: DateTime.parse((json['startedAt'] ?? '').toString()),
    );
  }
}

class FrontDeskShiftStorage {
  static String _key(String hotelId, String userId) =>
      'front_desk_shift_${hotelId}_$userId';

  static Future<FrontDeskShift?> load({
    required String hotelId,
    required String userId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(hotelId, userId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return FrontDeskShift.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(FrontDeskShift shift) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(shift.hotelId, shift.userId),
      jsonEncode(shift.toJson()),
    );
  }

  static Future<void> clear({
    required String hotelId,
    required String userId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(hotelId, userId));
  }
}
