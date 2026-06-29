import 'package:dio/dio.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';
import 'package:flutter/material.dart';

import '../../../dio_client.dart';
import '../../../widgets/admin_time_slot_field.dart';
import '../admin_dashboard_models.dart';

String formatAdminCheckInDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Quick check-in for booked / reserved rooms from Summary or Book tab.
Future<bool> performAdminRoomCheckIn(
  BuildContext context, {
  required Map<String, dynamic> room,
  Future<void> Function()? onSuccess,
}) async {
  final roomId = AdminDashboardModels.roomIdOf(room);
  if (roomId.isEmpty) {
    showAppMessage(context, 'Room ID missing. Refresh and try again.');
    return false;
  }

  final inDate = AdminDashboardModels.stayStartDate(room) ?? DateTime.now();
  final outDate =
      AdminDashboardModels.stayEndDate(room) ?? inDate.add(const Duration(days: 1));
  var checkInDate = inDate;
  var checkOutDate = outDate;
  TimeOfDay? checkInTime = AdminDashboardModels.bookingTimeOfDay(room, 'check_in_time') ??
      const TimeOfDay(hour: 15, minute: 0);
  TimeOfDay? checkOutTime = AdminDashboardModels.bookingTimeOfDay(room, 'check_out_time') ??
      const TimeOfDay(hour: 11, minute: 0);

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text('Check in — Room ${room['room_number']}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AdminDashboardModels.guestName(room),
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Check-in date'),
                subtitle: Text(formatAdminCheckInDate(checkInDate)),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    firstDate: DateTime.now().subtract(const Duration(days: 7)),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    initialDate: checkInDate,
                  );
                  if (picked != null) setLocal(() => checkInDate = picked);
                },
              ),
              AdminTimeSlotField(
                label: 'Check-in time',
                value: checkInTime,
                onChanged: (t) => setLocal(() => checkInTime = t),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Check-out date'),
                subtitle: Text(formatAdminCheckInDate(checkOutDate)),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    firstDate: checkInDate,
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    initialDate: checkOutDate,
                  );
                  if (picked != null) setLocal(() => checkOutDate = picked);
                },
              ),
              AdminTimeSlotField(
                label: 'Check-out time',
                value: checkOutTime,
                onChanged: (t) => setLocal(() => checkOutTime = t),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Check in guest'),
          ),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return false;

  final inTime = checkInTime ?? const TimeOfDay(hour: 15, minute: 0);
  final outTime = checkOutTime ?? const TimeOfDay(hour: 11, minute: 0);
  final checkInAt = DateTime(
    checkInDate.year,
    checkInDate.month,
    checkInDate.day,
    inTime.hour,
    inTime.minute,
  );
  final checkOutAt = DateTime(
    checkOutDate.year,
    checkOutDate.month,
    checkOutDate.day,
    outTime.hour,
    outTime.minute,
  );

  try {
    await portalDio().patch(
      '/admin/rooms/$roomId/status',
      data: {
        'status': 'checked_in',
        'check_in_at': checkInAt.toIso8601String(),
        'check_out_at': checkOutAt.toIso8601String(),
      },
    );
    if (!context.mounted) return false;
    showAppMessage(context, 'Guest checked in.');
    if (onSuccess != null) await onSuccess();
    return true;
  } on DioException catch (e) {
    if (!context.mounted) return false;
    showAppMessage(context, dioErrorMessage(e), isError: true);
    return false;
  }
}
