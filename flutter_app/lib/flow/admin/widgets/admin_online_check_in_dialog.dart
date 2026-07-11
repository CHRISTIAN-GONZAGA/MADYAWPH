import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';

import '../../../dio_client.dart';
import '../../../widgets/admin_time_slot_field.dart';
import '../admin_dashboard_models.dart';
import 'device_guest_welcome_sms.dart';

String formatAdminCheckInDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Check-in dialog for booked rooms (walk-in or public online).
Future<bool> showAdminOnlineAwareCheckInDialog(
  BuildContext context, {
  required Map<String, dynamic> room,
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
  var checkInTime = AdminDashboardModels.bookingTimeOfDay(room, 'check_in_time') ??
      const TimeOfDay(hour: 15, minute: 0);
  var checkOutTime = AdminDashboardModels.bookingTimeOfDay(room, 'check_out_time') ??
      const TimeOfDay(hour: 11, minute: 0);

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text('Check in — Room ${room['room_number']}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                onChanged: (t) {
                  if (t != null) setLocal(() => checkInTime = t);
                },
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
                onChanged: (t) {
                  if (t != null) setLocal(() => checkOutTime = t);
                },
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

  Map<String, dynamic>? checkInResponse;
  try {
    final res = await portalDio().patch<Map<String, dynamic>>(
      '/admin/rooms/$roomId/status',
      data: {
        'status': 'checked_in',
        'check_in_at': checkInAt.toIso8601String(),
        'check_out_at': checkOutAt.toIso8601String(),
      },
    );
    checkInResponse = res.data;
  } on DioException catch (e) {
    if (!context.mounted) return false;
    showAppMessage(context, dioErrorMessage(e), isError: true);
    return false;
  } catch (e) {
    if (!context.mounted) return false;
    showAppMessage(context, 'Check-in failed: $e', isError: true);
    return false;
  }

  // Check-in already succeeded on the server. Never let SMS / toast plumbing
  // make this look like a failure (Book tab refresh depends on returning true).
  if (!context.mounted) return true;

  final guestEmail = AdminDashboardModels.guestEmail(room);
  final emailNote = guestEmail.isEmpty
      ? ''
      : ' Welcome email queued for $guestEmail (if email is configured).';

  var smsNote = '';
  try {
    final rawSms = checkInResponse?['guest_welcome_sms'];
    final smsPayload = rawSms is Map
        ? Map<String, dynamic>.from(rawSms)
        : const <String, dynamic>{};
    final roomPayload = checkInResponse?['room'];
    final roomMap = roomPayload is Map
        ? Map<String, dynamic>.from(roomPayload)
        : const <String, dynamic>{};

    final smsPhone = (smsPayload['guest_phone'] ??
            AdminDashboardModels.guestPhone(room))
        .toString()
        .trim();
    final smsPassword = (smsPayload['room_access_password'] ??
            roomMap['room_access_password'] ??
            '')
        .toString()
        .trim();
    final smsHotel = (smsPayload['hotel_name'] ?? '').toString().trim();
    final smsGuest = (smsPayload['guest_name'] ??
            AdminDashboardModels.guestName(room))
        .toString()
        .trim();
    final smsRoom = (smsPayload['room_number'] ?? room['room_number'] ?? '')
        .toString()
        .trim();

    if (smsPhone.isNotEmpty) {
      // Best-effort only — do not block returning success if SMS hangs briefly.
      final smsResult = await DeviceGuestWelcomeSms.sendWelcome(
        guestPhone: smsPhone,
        hotelName: smsHotel,
        guestName: smsGuest,
        roomNumber: smsRoom,
        roomPassword: smsPassword,
      ).timeout(
        const Duration(seconds: 25),
        onTimeout: () => DeviceSmsOutcome.skipped('SMS timed out.'),
      );
      if (smsResult.mode == DeviceSmsMode.sentDirect) {
        smsNote = ' Welcome SMS sent from this phone.';
      } else if (smsResult.mode == DeviceSmsMode.openedComposer) {
        smsNote = ' Messages opened — tap Send to SMS from this SIM.';
      }
    }
  } catch (_) {
    // Ignore SMS failures; check-in already completed.
  }

  if (context.mounted) {
    showAppMessage(context, 'Guest checked in.$emailNote$smsNote');
  }
  return true;
}
