import 'package:flutter/material.dart';

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
      }
    }

    return shift;
  }

  static Future<void> handleTimeOut({
    required BuildContext context,
    required FrontDeskShift shift,
    String summaryTitle = 'Shift revenue summary',
    bool logoutOnFinish = true,
  }) async {
    if (!shift.canTimeOut) return;
    final endedAt = DateTime.now();
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
