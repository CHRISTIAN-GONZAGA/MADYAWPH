import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';

import '../../../dio_client.dart';
import '../../../utils/money_format.dart';
import '../../../widgets/payment_proof_picker.dart';
import '../admin_dashboard_models.dart';
import 'device_guest_welcome_sms.dart';
import 'hourly_billing.dart';
import 'booking_confirmation_summary_dialog.dart';
import 'online_payment_qr_block.dart';

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
  final bookingMap = room['latest_booking'] is Map
      ? Map<String, dynamic>.from(room['latest_booking'] as Map)
      : const <String, dynamic>{};
  final isOrgBooking = bookingMap['is_org_booking'] == true ||
      (bookingMap['booking_source'] ?? '').toString() == 'admin-org' ||
      (bookingMap['org_name'] ?? '').toString().trim().isNotEmpty;
  final isOnlineStay =
      (bookingMap['booking_type'] ?? '').toString().toLowerCase() == 'online' ||
          (bookingMap['booking_source'] ?? '').toString() == 'app-customer' ||
          (bookingMap['source'] ?? '').toString().toLowerCase() == 'web';
  final scheduledOut =
      AdminDashboardModels.stayEndDate(room) ?? DateTime.now().add(const Duration(days: 1));

  // Online stays keep the quoted window. Walk-in hourly still uses clock-now + block.
  final window = isOnlineStay
      ? (checkIn: DateTime.now(), checkOut: scheduledOut)
      : HourlyBilling.clockBasedStayWindow(
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
  double amountAlreadyPaid = 0;
  List<BookingSummaryLine> billLines = const [];
  double minPercent = isOrgBooking ? 0 : 50;
  double minDue = 0;
  final paymentCtrl = TextEditingController();
  final paymentRefCtrl = TextEditingController();
  var paymentMethod = 'Cash';
  var loadingPolicy = true;

  try {
    final booking = bookingMap;
    final bookingId = AdminDashboardModels.documentIdOf(booking);
    final futures = <Future>[
      if (!isOrgBooking)
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
    var billIndex = 0;
    if (!isOrgBooking) {
      final policy = results[0].data as Map<String, dynamic>?;
      minPercent = parseJsonDouble(policy?['min_check_in_payment_percent'] ?? 50);
      billIndex = 1;
    }
    if (results.length > billIndex) {
      final bill = results[billIndex].data as Map<String, dynamic>?;
      balanceDue = parseJsonDouble(
        bill?['balance_due'] ?? bill?['total_due'] ?? balanceDue,
      );
      amountAlreadyPaid = parseJsonDouble(bill?['amount_paid'] ?? 0);
      final rawLines = bill?['lines'];
      if (rawLines is List) {
        billLines = [
          for (final raw in rawLines)
            if (raw is Map)
              BookingSummaryLine(
                label: (raw['label'] ?? '').toString(),
                amount: parseJsonDouble(raw['amount']),
              ),
        ];
      }
    }
    minDue = isOrgBooking
        ? 0
        : (balanceDue * (minPercent / 100)).clamp(0, double.infinity);
    if (minDue > 0.009) {
      paymentCtrl.text = minDue.toStringAsFixed(2);
    }
  } catch (_) {
    minDue = isOrgBooking
        ? 0
        : (balanceDue * (minPercent / 100)).clamp(0, double.infinity);
    if (minDue > 0.009) {
      paymentCtrl.text = minDue.toStringAsFixed(2);
    }
  } finally {
    loadingPolicy = false;
  }

  final stayPaid = balanceDue <= 0.009;
  final staySummary = isOnlineStay
      ? (stayPaid
          ? 'Online payment already applied. Check in without collecting again.'
          : 'Collect the remaining balance only — online payment is already on the bill.')
      : (isHourly
          ? '${HourlyBilling.blockHours(room)}h stay · check-in now · '
              'checkout ~${_formatClock(checkOutAt)}'
          : 'Check-in now · overnight through ${formatAdminCheckInDate(checkOutAt)} '
              '(checkout ${_formatClock(checkOutAt)})');

  // Warm the SMS composer channel (Play build does not request SEND_SMS).
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
              GuestStayDocuments(
                guestIdUrl: GuestStayDocuments.urlFrom(bookingMap, 'guest_id_url'),
                paymentScreenshotUrl: GuestStayDocuments.urlFrom(
                  bookingMap,
                  'payment_screenshot_url',
                ),
                discountIdUrl:
                    GuestStayDocuments.urlFrom(bookingMap, 'discount_id_url'),
                requireIdAndReceipt: isOnlineStay,
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
                    : isOrgBooking
                        ? 'Government / org charge account — check-in allowed without payment.\n'
                            'Outstanding balance: ${formatMoney(balanceDue)} '
                            '(collect later in Gov/Org Booking).'
                        : stayPaid
                            ? 'Already paid (E-wallet)'
                                '${amountAlreadyPaid > 0.009 ? ' — ${formatMoney(amountAlreadyPaid)} received' : ''}.\n'
                                'No check-in payment needed.'
                            : 'Remaining balance: ${formatMoney(balanceDue)}'
                                '${amountAlreadyPaid > 0.009 ? '\nAlready paid (E-wallet): ${formatMoney(amountAlreadyPaid)}' : ''}\n'
                                'Company policy: at least ${minPercent.toStringAsFixed(minPercent % 1 == 0 ? 0 : 1)}%'
                                '${minDue > 0 ? ' (${formatMoney(minDue)})' : ''} of the remaining balance.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              if (!isOrgBooking && !stayPaid) ...[
              const SizedBox(height: 10),
              TextField(
                controller: paymentCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: InputDecoration(
                  labelText: 'Amount received (₱)',
                  border: const OutlineInputBorder(),
                  prefixText: '₱ ',
                  helperText: balanceDue > 0
                      ? 'You may tender more than due; change is shown below.'
                      : null,
                ),
                onChanged: (_) => setLocal(() {}),
              ),
              Builder(
                builder: (_) {
                  final tendered =
                      double.tryParse(paymentCtrl.text.trim()) ?? 0;
                  final change = tendered > 0 && balanceDue > 0
                      ? (tendered - balanceDue).clamp(0, double.infinity)
                      : 0.0;
                  final remaining = tendered > 0 && balanceDue > 0
                      ? (balanceDue - tendered).clamp(0, double.infinity)
                      : balanceDue;
                  if (tendered <= 0 || balanceDue <= 0) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      tendered + 0.009 < minDue
                          ? 'Need at least ${formatMoney(minDue)} to check in.'
                          : (change > 0
                              ? 'Change given: ${formatPeso(change)}'
                              : (remaining <= 0.009
                                  ? 'Paid in full — no change.'
                                  : 'Remaining after this payment: ${formatPeso(remaining)}')),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: tendered + 0.009 < minDue
                            ? Theme.of(ctx).colorScheme.error
                            : Theme.of(ctx).colorScheme.primary,
                      ),
                    ),
                  );
                },
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
                  DropdownMenuItem(value: 'QR Ph', child: Text('QR Ph')),
                  DropdownMenuItem(value: 'GCash', child: Text('GCash')),
                  DropdownMenuItem(value: 'Card', child: Text('Card')),
                  DropdownMenuItem(value: 'Bank transfer', child: Text('Bank transfer')),
                ],
                onChanged: (v) {
                  if (v != null) setLocal(() => paymentMethod = v);
                },
              ),
              OnlinePaymentQrBlock(
                paymentMethod: paymentMethod,
                referenceController: paymentRefCtrl,
              ),
              ],
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
              if (!isOrgBooking &&
                  !stayPaid &&
                  minPercent > 0 &&
                  balanceDue > 0 &&
                  paid + 0.009 < minDue) {
                showAppMessage(
                  ctx,
                  'Enter at least ${formatMoney(minDue)} '
                  '(${minPercent.toStringAsFixed(minPercent % 1 == 0 ? 0 : 1)}% of the remaining balance).',
                  isError: true,
                );
                return;
              }
              if (!isOrgBooking &&
                  !stayPaid &&
                  isOnlinePaymentMethod(paymentMethod) &&
                  paymentRefCtrl.text.trim().isEmpty) {
                showAppMessage(
                  ctx,
                  'Enter the QR Ph / e-wallet payment reference after the guest pays.',
                  isError: true,
                );
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: Builder(
              builder: (_) {
                final tendered =
                    double.tryParse(paymentCtrl.text.trim()) ?? 0;
                final change = tendered > 0 && balanceDue > 0
                    ? (tendered - balanceDue).clamp(0, double.infinity)
                    : 0.0;
                return Text(
                  stayPaid
                      ? 'Check in guest'
                      : (change > 0 ? 'Make payment' : 'Check in guest'),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );

  final payAmount = isOrgBooking || stayPaid
      ? 0.0
      : (double.tryParse(paymentCtrl.text.trim()) ?? 0);
  final paymentReference = paymentRefCtrl.text.trim();
  paymentCtrl.dispose();
  paymentRefCtrl.dispose();
  if (ok != true || !context.mounted) return false;

  final liveWindow = isOnlineStay
      ? (checkIn: DateTime.now(), checkOut: scheduledOut)
      : HourlyBilling.clockBasedStayWindow(
          room,
          DateTime.now(),
          checkOutDate: scheduledOut,
        );

  final summaryLines = billLines.isNotEmpty
      ? billLines
      : bookingSummaryLinesForRooms(
          rooms: [room],
          checkIn: liveWindow.checkIn,
          checkOut: liveWindow.checkOut,
        );

  final summaryOk = await showBookingConfirmationSummary(
    context: context,
    title: 'Confirm check-in',
    guestName: AdminDashboardModels.guestName(room),
    roomLabel: 'Room ${room['room_number']}',
    checkIn: liveWindow.checkIn,
    checkOut: liveWindow.checkOut,
    totalAmount: stayPaid ? amountAlreadyPaid : balanceDue,
    lines: summaryLines,
    paymentMethod: isOrgBooking
        ? 'B2B charge account'
        : (stayPaid ? 'E-wallet' : paymentMethod),
    amountTendered: isOrgBooking || stayPaid ? null : payAmount,
    changeDue: !isOrgBooking && !stayPaid && payAmount > balanceDue
        ? (payAmount - balanceDue).clamp(0, double.infinity)
        : 0,
    checkInNow: true,
    confirmLabel: stayPaid ? 'Check in guest' : 'Make payment',
  );
  if (!summaryOk || !context.mounted) return false;

  Map<String, dynamic>? checkInResponse;
  try {
    final res = await portalDio().patch<Map<String, dynamic>>(
      '/admin/rooms/$roomId/status',
      data: {
        'status': 'checked_in',
        'check_in_at': liveWindow.checkIn.toIso8601String(),
        'check_out_at': liveWindow.checkOut.toIso8601String(),
        if (!stayPaid && payAmount > 0) 'check_in_payment_amount': payAmount,
        if (!stayPaid && payAmount > 0) 'payment_method': paymentMethod,
        if (!stayPaid && payAmount > 0 && paymentReference.isNotEmpty)
          'payment_reference': paymentReference,
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
      if (smsResult.didSend || smsResult.message.isNotEmpty) {
        smsNote = ' ${smsResult.message}';
      }
    }
  } catch (_) {
    // ignore SMS errors — check-in already succeeded
  }

  if (!context.mounted) return true;
  final paymentPayload = checkInResponse?['check_in_payment'];
  final paymentMap = paymentPayload is Map
      ? Map<String, dynamic>.from(paymentPayload)
      : const <String, dynamic>{};
  final changeDue = parseJsonDouble(
    paymentMap['change_due'] ??
        (paymentMap['bill'] is Map
            ? (paymentMap['bill'] as Map)['change_given']
            : null),
  );
  final payNote = payAmount > 0
      ? (changeDue > 0.009
          ? ' ${formatMoney(payAmount)} tendered; change given ${formatPeso(changeDue)}.'
          : ' ${formatMoney(payAmount)} applied to the room bill.')
      : '';
  showAppMessage(
    context,
    'Guest checked in.$payNote$emailNote$smsNote',
  );
  return true;
}
