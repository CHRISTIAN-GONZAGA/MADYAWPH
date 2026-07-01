import 'package:flutter/material.dart';

import 'admin_online_check_in_dialog.dart';

export 'admin_online_check_in_dialog.dart' show formatAdminCheckInDate;

/// Quick check-in for booked / reserved rooms from Summary or Book tab.
Future<bool> performAdminRoomCheckIn(
  BuildContext context, {
  required Map<String, dynamic> room,
  Future<void> Function()? onSuccess,
}) async {
  final ok = await showAdminOnlineAwareCheckInDialog(context, room: room);
  if (ok && onSuccess != null) await onSuccess();
  return ok;
}
