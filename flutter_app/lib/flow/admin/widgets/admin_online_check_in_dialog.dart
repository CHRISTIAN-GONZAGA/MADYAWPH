import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';

import '../../../dio_client.dart';
import '../../../utils/money_format.dart';
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

  double balanceDue = parseJsonDouble(
    room['balance_due'] ??
        (room['latest_booking'] is Map
            ? (room['latest_booking'] as Map)['total_amount']
            : null) ??
        room['total_amount'] ??
        0,
  );
  double minPercent = 50;
  double minDue = 0;
  final paymentCtrl = TextEditingController();
  var paymentMethod = 'Cash';
  var loadingPolicy = true;

  try {
    final booking = room['latest_booking'] is Map
        ? Map<String, dynamic>.from(room['latest_booking'] as Map)
        : const <String, dynamic>{};
    final bookingId = AdminDashboardModels.documentIdOf(booking);
    final futures = <Future>[
      publicDio().get<Map<String, dynamic>>('/platform/info'),
    ];
    if (bookingId.isNotEmpty) {
      futures.add(
        portalDio().get<Map<String, dynamic>>(
          '/admin/bookings/$bookingId/bill-summary',
        ),
      );
    }
    final results = await Future.wait(futures);
    final platform = results[0].data as Map<String, dynamic>?;
    minPercent = parseJsonDouble(platform?['min_check_in_payment_percent'] ?? 50);
    if (results.length > 1) {
      final bill = results[1].data as Map<String, dynamic>?;
      balanceDue = parseJsonDouble(
        bill?['balance_due'] ?? bill?['total_due'] ?? balanceDue,
      );
    }
    minDue = (balanceDue * (minPercent / 100)).clamp(0, double.infinity);
    if (minDue > 0) {
      paymentCtrl.text = minDue.toStringAsFixed(2);
    }
  } catch (_) {
    minDue = (balanceDue * (minPercent / 100)).clamp(0, double.infinity);
    if (minDue > 0) {
      paymentCtrl.text = minDue.toStringAsFixed(2);
    }
  } finally {
    loadingPolicy = false;
  }

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
              const SizedBox(height: 16),
              Text(
                'Check-in payment',
                style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                loadingPolicy
                    ? 'Loading payment policy…'
                    : 'Balance due: ₱${balanceDue.toStringAsFixed(2)}\n'
                        'Company policy: at least ${minPercent.toStringAsFixed(minPercent % 1 == 0 ? 0 : 1)}%'
                        '${minDue > 0 ? ' (₱${minDue.toStringAsFixed(2)})' : ''}.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: paymentCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Amount paid now (₱)',
                  border: OutlineInputBorder(),
                  prefixText: '₱ ',
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: paymentMethod,
                decoration: const InputDecoration(
                  labelText: 'Payment method',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                  DropdownMenuItem(value: 'GCash', child: Text('GCash')),
                  DropdownMenuItem(value: 'Card', child: Text('Card')),
                  DropdownMenuItem(value: 'Bank transfer', child: Text('Bank transfer')),
                ],
                onChanged: (v) {
                  if (v != null) setLocal(() => paymentMethod = v);
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
            onPressed: () {
              final paid = double.tryParse(paymentCtrl.text.trim()) ?? 0;
              if (minPercent > 0 && balanceDue > 0 && paid + 0.009 < minDue) {
                showAppMessage(
                  ctx,
                  'Enter at least ₱${minDue.toStringAsFixed(2)} '
                  '(${minPercent.toStringAsFixed(minPercent % 1 == 0 ? 0 : 1)}% of the balance).',
                  isError: true,
                );
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Check in guest'),
          ),
        ],
      ),
    ),
  );

  final payAmount = double.tryParse(paymentCtrl.text.trim()) ?? 0;
  paymentCtrl.dispose();
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
        if (payAmount > 0) 'check_in_payment_amount': payAmount,
        if (payAmount > 0) 'payment_method': paymentMethod,
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
        smsNote = ' Welcome SMS sent.';
      } else if (smsResult.message.isNotEmpty) {
        smsNote = ' ${smsResult.message}';
      }
    }
  } catch (_) {
    // ignore SMS errors
  }

  if (!context.mounted) return true;
  final payNote = payAmount > 0
      ? ' ₱${payAmount.toStringAsFixed(2)} applied to the room bill.'
      : '';
  showAppMessage(
    context,
    'Guest checked in.$payNote$emailNote$smsNote',
  );
  return true;
}
