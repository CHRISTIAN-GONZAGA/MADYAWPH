import 'package:flutter/material.dart';

import '../../../auth_storage.dart';
import '../../../dio_client.dart';
import 'front_desk_shift.dart';
import 'front_desk_shift_setup_dialog.dart';
import 'front_desk_shift_summary_screen.dart';

/// Shared time-in / time-out shift flow for front desk and staff portal users.
class PortalShiftSession {
  static String timeOutButtonLabel(FrontDeskShift? shift) {
    if (shift == null) return 'Time out';
    if (shift.canTimeOut) return 'Time out';
    final remaining = shift.timeUntilTimeOut;
    final h = remaining.inHours;
    final m = remaining.inMinutes.remainder(60);
    return '${h}h ${m.toString().padLeft(2, '0')}m';
  }

  static Future<FrontDeskShift?> ensureShift({
    required BuildContext context,
    required String userId,
    required String hotelId,
    required String staffName,
    bool shiftPromptShown = false,
    void Function(bool shown)? onPromptShown,
    String shiftSetupTitle = 'Start your shift',
    String shiftSetupDescription =
        'Set your time in and scheduled time out. You can only clock out after the time out you set.',
  }) async {
    if (userId.isEmpty || hotelId.isEmpty) return null;

    var shift = await FrontDeskShiftStorage.load(
      hotelId: hotelId,
      userId: userId,
    );
    if (!context.mounted) return shift;

    shift ??= await _restoreFromServer(
      hotelId: hotelId,
      userId: userId,
      staffName: staffName,
    );
    if (!context.mounted) return shift;

    if (shift == null && !shiftPromptShown) {
      onPromptShown?.call(true);
      shift = await showFrontDeskShiftSetupDialog(
        context: context,
        userId: userId,
        hotelId: hotelId,
        staffName: staffName,
        title: shiftSetupTitle,
        description: shiftSetupDescription,
      );
      if (shift != null) {
        await FrontDeskShiftStorage.save(shift);
        try {
          await portalDio().post<Map<String, dynamic>>(
            '/frontdesk-shifts/start',
            data: {
              'started_at': shift.startedAt.toIso8601String(),
              'scheduled_time_out': shift.scheduledTimeOut.toIso8601String(),
              'staff_name': shift.staffName,
            },
          );
        } catch (_) {
          // Local shift still works if sync fails; admin summary may lag.
        }
      }
    }

    if (shift != null) {
      await AuthStorage.setPortalShiftLock(true);
    }

    return shift;
  }

  static Future<FrontDeskShift?> _restoreFromServer({
    required String hotelId,
    required String userId,
    required String staffName,
  }) async {
    try {
      final res = await portalDio().get<Map<String, dynamic>>(
        '/frontdesk-shifts/active',
      );
      final sessions = res.data?['sessions'];
      if (sessions is! List) return null;
      for (final raw in sessions) {
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        if ((map['user_id'] ?? '').toString() != userId) continue;
        final startedRaw = (map['started_at'] ?? '').toString();
        final outRaw = (map['scheduled_time_out'] ?? '').toString();
        if (startedRaw.isEmpty || outRaw.isEmpty) continue;
        final startedAt = DateTime.tryParse(startedRaw);
        final scheduledOut = DateTime.tryParse(outRaw);
        if (startedAt == null || scheduledOut == null) continue;
        final shift = FrontDeskShift(
          userId: userId,
          hotelId: hotelId,
          staffName: (map['staff_name'] ?? staffName).toString(),
          scheduledTimeIn: startedAt,
          scheduledTimeOut: scheduledOut,
          startedAt: startedAt,
        );
        await FrontDeskShiftStorage.save(shift);
        return shift;
      }
    } catch (_) {}
    return null;
  }

  static Future<void> handleTimeOut({
    required BuildContext context,
    required FrontDeskShift shift,
    String summaryTitle = 'Shift revenue summary',
    bool logoutOnFinish = true,
  }) async {
    if (!shift.canTimeOut) return;
    final endedAt = DateTime.now();
    try {
      await portalDio().post<Map<String, dynamic>>(
        '/frontdesk-shifts/end',
        data: {'ended_at': endedAt.toIso8601String()},
      );
    } catch (_) {}
    await FrontDeskShiftStorage.clear(
      hotelId: shift.hotelId,
      userId: shift.userId,
    );
    await AuthStorage.setPortalShiftLock(false);
    if (!context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => FrontDeskShiftSummaryScreen(
          shift: shift,
          endedAt: endedAt,
          logoutOnFinish: logoutOnFinish,
          title: summaryTitle,
        ),
      ),
    );
  }
}
