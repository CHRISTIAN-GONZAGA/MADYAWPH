import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';

import '../../../dio_client.dart';
import '../../../utils/money_format.dart';
import '../admin_dashboard_models.dart';
import 'device_guest_welcome_sms.dart';
import 'hourly_billing.dart';

String formatAdminCheckInDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _formatClock(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

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

  final isHourly = HourlyBilling.isHourly(room);
  final scheduledOut =
      AdminDashboardModels.stayEndDate(room) ?? DateTime.now().add(const Duration(days: 1));

  // Hourly: stay window is always clock-now + block_hours (server also enforces).
  // Nightly: check-in at clock now; checkout stays on scheduled overnight date @ 11:00.
  final window = HourlyBilling.clockBasedStayWindow(
    room,
    DateTime.now(),
    checkOutDate: scheduledOut,
  );
  final checkOutAt = window.checkOut;

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
      portalDio().get<Map<String, dynamic>>('/admin/settings/min-check-in-payment'),
    ];
    if (bookingId.isNotEmpty) {
      futures.add(
        portalDio().get<Map<String, dynamic>>(
          '/admin/bookings/$bookingId/bill-summary',
        ),
      );
    }
    final results = await Future.wait(futures);
    final policy = results[0].data as Map<String, dynamic>?;
    minPercent = parseJsonDouble(policy?['min_check_in_payment_percent'] ?? 50);
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

  final staySummary = isHourly
      ? '${HourlyBilling.blockHours(room)}h stay · check-in now · '
          'checkout ~${_formatClock(checkOutAt)}'
      : 'Check-in now · overnight through ${formatAdminCheckInDate(checkOutAt)} '
          '(checkout ${_formatClock(checkOutAt)})';

  // Ask for SEND_SMS before check-in so the welcome SMS can go out silently.
  await DeviceGuestWelcomeSms.ensurePermission();
  if (!context.mounted) return false;

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
              Text(
                staySummary,
                style: Theme.of(ctx).textTheme.bodyMedium,
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

  // Recompute at submit so the window matches the actual check-in clock.
  final liveWindow = HourlyBilling.clockBasedStayWindow(
    room,
    DateTime.now(),
    checkOutDate: scheduledOut,
  );

  Map<String, dynamic>? checkInResponse;
  try {
    final res = await portalDio().patch<Map<String, dynamic>>(
      '/admin/rooms/$roomId/status',
      data: {
        'status': 'checked_in',
        'check_in_at': liveWindow.checkIn.toIso8601String(),
        'check_out_at': liveWindow.checkOut.toIso8601String(),
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
        : <String, dynamic>{
            'guest_phone': AdminDashboardModels.guestPhone(room),
            'guest_name': AdminDashboardModels.guestName(room),
            'room_number': (room['room_number'] ?? '').toString(),
            'room_access_password': (checkInResponse?['room'] is Map
                    ? (checkInResponse!['room'] as Map)['room_access_password']
                    : '')
                ?.toString() ??
                '',
          };
    final roomPayload = checkInResponse?['room'];
    final roomMap = roomPayload is Map
        ? Map<String, dynamic>.from(roomPayload)
        : const <String, dynamic>{};
    if ((smsPayload['room_access_password'] ?? '').toString().trim().isEmpty) {
      smsPayload['room_access_password'] =
          (roomMap['room_access_password'] ?? '').toString();
    }

    final smsPhone = (smsPayload['guest_phone'] ??
            AdminDashboardModels.guestPhone(room))
        .toString()
        .trim();

    if (smsPhone.isNotEmpty) {
      final smsResult = await DeviceGuestWelcomeSms.sendFromPayload(
        smsPayload,
        fallbackPhone: AdminDashboardModels.guestPhone(room),
        fallbackGuest: AdminDashboardModels.guestName(room),
        fallbackRoom: (room['room_number'] ?? '').toString(),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () => DeviceSmsOutcome.failed('SMS timed out.'),
      );
      if (smsResult.didSend) {
        smsNote = ' Welcome SMS sent from this phone.';
      } else if (smsResult.message.isNotEmpty) {
        smsNote = ' ${smsResult.message}';
      }
    }
  } catch (_) {
    // ignore SMS errors — check-in already succeeded
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
