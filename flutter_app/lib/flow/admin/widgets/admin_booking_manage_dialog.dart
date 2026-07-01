import 'package:dio/dio.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';
import 'package:flutter/material.dart';

import '../../../dio_client.dart';
import '../admin_dashboard_models.dart';

Future<bool> showAdminManageBookingDialog({
  required BuildContext context,
  required Map<String, dynamic> booking,
  bool isFrontDesk = false,
  bool isAdmin = true,
}) async {
  final bookingId = (booking['id'] ?? '').toString();
  if (bookingId.isEmpty) return false;

  final status = (booking['status'] ?? '').toString().toLowerCase();
  if (status == 'cancelled' || status == 'completed') {
    showAppMessage(context, 'This booking is already closed.');
    return false;
  }

  final pending = AdminDashboardModels.pendingDateChange(booking);
  final hasPending = AdminDashboardModels.hasPendingDateChange(booking);

  final checkInCtrl = TextEditingController(
    text: hasPending
        ? (pending?['check_in_date'] ?? '').toString().split('T').first
        : (booking['check_in_date'] ?? '').toString().split('T').first,
  );
  final checkOutCtrl = TextEditingController(
    text: hasPending
        ? (pending?['check_out_date'] ?? '').toString().split('T').first
        : (booking['check_out_date'] ?? '').toString().split('T').first,
  );
  DateTime? checkIn = AdminDashboardModels.parseDate(checkInCtrl.text);
  DateTime? checkOut = AdminDashboardModels.parseDate(checkOutCtrl.text);

  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        Future<void> pickCheckIn() async {
          final picked = await showDatePicker(
            context: ctx,
            firstDate: DateTime.now().subtract(const Duration(days: 1)),
            lastDate: DateTime.now().add(const Duration(days: 730)),
            initialDate: checkIn ?? DateTime.now(),
          );
          if (picked == null) return;
          checkIn = picked;
          checkInCtrl.text = picked.toIso8601String().split('T').first;
          if (checkOut != null && !checkOut!.isAfter(picked)) {
            checkOut = null;
            checkOutCtrl.clear();
          }
          setLocal(() {});
        }

        Future<void> pickCheckOut() async {
          if (checkIn == null) return;
          final picked = await showDatePicker(
            context: ctx,
            firstDate: checkIn!.add(const Duration(days: 1)),
            lastDate: checkIn!.add(const Duration(days: 730)),
            initialDate: checkOut ?? checkIn!.add(const Duration(days: 1)),
          );
          if (picked == null) return;
          checkOut = picked;
          checkOutCtrl.text = picked.toIso8601String().split('T').first;
          setLocal(() {});
        }

        Future<void> approvePending() async {
          try {
            await portalDio()
                .post('/admin/bookings/$bookingId/date-change/approve');
            if (ctx.mounted) Navigator.pop(ctx, true);
          } on DioException catch (e) {
            if (!ctx.mounted) return;
            showAppMessage(ctx, dioErrorMessage(e), isError: true);
          }
        }

        Future<void> rejectPending() async {
          try {
            await portalDio()
                .post('/admin/bookings/$bookingId/date-change/reject');
            if (ctx.mounted) Navigator.pop(ctx, true);
          } on DioException catch (e) {
            if (!ctx.mounted) return;
            showAppMessage(ctx, dioErrorMessage(e), isError: true);
          }
        }

        return AlertDialog(
          title: Text('Manage booking ${booking['booking_reference'] ?? ''}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  (booking['guest_name'] ?? 'Guest').toString(),
                  style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                if (hasPending) ...[
                  const SizedBox(height: 10),
                  Card(
                    color: Theme.of(ctx).colorScheme.tertiaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pending date change',
                            style: Theme.of(ctx).textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Requested by ${pending?['requested_by_name'] ?? 'front desk'}',
                            style: Theme.of(ctx).textTheme.bodySmall,
                          ),
                          Text(
                            '${AdminDashboardModels.formatDisplayDate(pending?['check_in_date'])} → ${AdminDashboardModels.formatDisplayDate(pending?['check_out_date'])}',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: checkInCtrl,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Check-in',
                    suffixIcon: Icon(Icons.calendar_month_outlined),
                  ),
                  onTap: pickCheckIn,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: checkOutCtrl,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Check-out',
                    suffixIcon: Icon(Icons.calendar_month_outlined),
                  ),
                  onTap: pickCheckOut,
                ),
                const SizedBox(height: 8),
                Text(
                  isFrontDesk
                      ? 'Date changes are sent to the admin for approval. You can still cancel this booking.'
                      : 'Saving checks for conflicts with other stays on this room.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Close'),
            ),
            if (hasPending && !isFrontDesk) ...[
              TextButton(
                onPressed: rejectPending,
                child: Text(
                  'Reject change',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                ),
              ),
              FilledButton(
                onPressed: approvePending,
                child: const Text('Approve change'),
              ),
            ],
            TextButton(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: ctx,
                  builder: (c) => AlertDialog(
                    title: const Text('Cancel booking?'),
                    content: const Text(
                      'This releases the room hold when safe to do so.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('Keep'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('Cancel booking'),
                      ),
                    ],
                  ),
                );
                if (confirm != true || !ctx.mounted) return;
                try {
                  await portalDio().post('/admin/bookings/$bookingId/cancel');
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } on DioException catch (e) {
                  if (!ctx.mounted) return;
                  showAppMessage(ctx, dioErrorMessage(e), isError: true);
                }
              },
              child: Text(
                'Cancel booking',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
            ),
            if (!hasPending || isFrontDesk)
              FilledButton(
                onPressed: checkIn == null || checkOut == null
                    ? null
                    : () async {
                        try {
                          final res = await portalDio().patch<Map<String, dynamic>>(
                            '/admin/bookings/$bookingId',
                            data: {
                              'check_in_at':
                                  checkIn!.toIso8601String().split('T').first,
                              'check_out_at':
                                  checkOut!.toIso8601String().split('T').first,
                            },
                          );
                          if (!ctx.mounted) return;
                          if (res.data?['pending_approval'] == true) {
                            showAppMessage(
                              ctx,
                              (res.data?['message'] ?? 'Date change submitted for admin approval.')
                                  .toString(),
                            );
                          }
                          Navigator.pop(ctx, true);
                        } on DioException catch (e) {
                          if (!ctx.mounted) return;
                          showAppMessage(ctx, dioErrorMessage(e), isError: true);
                        }
                      },
                child: Text(
                  isFrontDesk ? 'Request date change' : 'Save dates',
                ),
              ),
          ],
        );
      },
    ),
  );

  checkInCtrl.dispose();
  checkOutCtrl.dispose();
  return saved == true;
}

Future<bool> showAdminManageReservationDialog({
  required BuildContext context,
  required Map<String, dynamic> reservation,
  bool isFrontDesk = false,
  bool isAdmin = true,
}) async {
  final id = (reservation['id'] ?? reservation['_id'] ?? '').toString();
  if (id.isEmpty) return false;

  final status = (reservation['status'] ?? '').toString().toLowerCase();
  if (!['pending_approval', 'approved', 'reserved', 'booked'].contains(status)) {
    showAppMessage(context, 'This reservation cannot be edited.');
    return false;
  }

  final pending = AdminDashboardModels.pendingDateChange(reservation);
  final hasPending = AdminDashboardModels.hasPendingDateChange(reservation);

  final checkInCtrl = TextEditingController(
    text: hasPending
        ? (pending?['check_in_date'] ?? '').toString().split('T').first
        : (reservation['check_in_date'] ?? '').toString().split('T').first,
  );
  final checkOutCtrl = TextEditingController(
    text: hasPending
        ? (pending?['check_out_date'] ?? '').toString().split('T').first
        : (reservation['check_out_date'] ?? '').toString().split('T').first,
  );
  DateTime? checkIn = AdminDashboardModels.parseDate(checkInCtrl.text);
  DateTime? checkOut = AdminDashboardModels.parseDate(checkOutCtrl.text);

  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        Future<void> pickCheckIn() async {
          final picked = await showDatePicker(
            context: ctx,
            firstDate: DateTime.now().subtract(const Duration(days: 1)),
            lastDate: DateTime.now().add(const Duration(days: 730)),
            initialDate: checkIn ?? DateTime.now(),
          );
          if (picked == null) return;
          checkIn = picked;
          checkInCtrl.text = picked.toIso8601String().split('T').first;
          if (checkOut != null && !checkOut!.isAfter(picked)) {
            checkOut = null;
            checkOutCtrl.clear();
          }
          setLocal(() {});
        }

        Future<void> pickCheckOut() async {
          if (checkIn == null) return;
          final picked = await showDatePicker(
            context: ctx,
            firstDate: checkIn!.add(const Duration(days: 1)),
            lastDate: checkIn!.add(const Duration(days: 730)),
            initialDate: checkOut ?? checkIn!.add(const Duration(days: 1)),
          );
          if (picked == null) return;
          checkOut = picked;
          checkOutCtrl.text = picked.toIso8601String().split('T').first;
          setLocal(() {});
        }

        Future<void> approvePending() async {
          try {
            await portalDio()
                .post('/admin/reservations/$id/date-change/approve');
            if (ctx.mounted) Navigator.pop(ctx, true);
          } on DioException catch (e) {
            if (!ctx.mounted) return;
            showAppMessage(ctx, dioErrorMessage(e), isError: true);
          }
        }

        Future<void> rejectPending() async {
          try {
            await portalDio()
                .post('/admin/reservations/$id/date-change/reject');
            if (ctx.mounted) Navigator.pop(ctx, true);
          } on DioException catch (e) {
            if (!ctx.mounted) return;
            showAppMessage(ctx, dioErrorMessage(e), isError: true);
          }
        }

        return AlertDialog(
          title: Text(
            'Manage reservation ${reservation['external_reference'] ?? id}',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  (reservation['guest_name'] ?? 'Guest').toString(),
                  style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                Text('Status: ${AdminDashboardModels.reservationStatusLabel(status)}'),
                if (hasPending) ...[
                  const SizedBox(height: 10),
                  Card(
                    color: Theme.of(ctx).colorScheme.tertiaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pending date change',
                            style: Theme.of(ctx).textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Requested by ${pending?['requested_by_name'] ?? 'front desk'}',
                            style: Theme.of(ctx).textTheme.bodySmall,
                          ),
                          Text(
                            '${AdminDashboardModels.formatDisplayDate(pending?['check_in_date'])} → ${AdminDashboardModels.formatDisplayDate(pending?['check_out_date'])}',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: checkInCtrl,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Check-in',
                    suffixIcon: Icon(Icons.calendar_month_outlined),
                  ),
                  onTap: pickCheckIn,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: checkOutCtrl,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Check-out',
                    suffixIcon: Icon(Icons.calendar_month_outlined),
                  ),
                  onTap: pickCheckOut,
                ),
                if (isFrontDesk) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Date changes are sent to the admin for approval. You can still cancel this hold.',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Close'),
            ),
            if (hasPending && !isFrontDesk) ...[
              TextButton(
                onPressed: rejectPending,
                child: Text(
                  'Reject change',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                ),
              ),
              FilledButton(
                onPressed: approvePending,
                child: const Text('Approve change'),
              ),
            ],
            if (status != 'pending_approval')
              TextButton(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: ctx,
                    builder: (c) => AlertDialog(
                      title: const Text('Cancel reservation?'),
                      content: const Text(
                        'The room hold will be released when possible.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: const Text('Keep'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('Cancel reservation'),
                        ),
                      ],
                    ),
                  );
                  if (confirm != true || !ctx.mounted) return;
                  try {
                    await portalDio().post('/admin/reservations/$id/cancel');
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  } on DioException catch (e) {
                    if (!ctx.mounted) return;
                    showAppMessage(ctx, dioErrorMessage(e), isError: true);
                  }
                },
                child: Text(
                  'Cancel hold',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                ),
              ),
            if (!hasPending || isFrontDesk)
              FilledButton(
                onPressed: checkIn == null || checkOut == null
                    ? null
                    : () async {
                        try {
                          final res = await portalDio().patch<Map<String, dynamic>>(
                            '/admin/reservations/$id',
                            data: {
                              'check_in_at':
                                  checkIn!.toIso8601String().split('T').first,
                              'check_out_at':
                                  checkOut!.toIso8601String().split('T').first,
                            },
                          );
                          if (!ctx.mounted) return;
                          if (res.data?['pending_approval'] == true) {
                            showAppMessage(
                              ctx,
                              (res.data?['message'] ?? 'Date change submitted for admin approval.')
                                  .toString(),
                            );
                          }
                          Navigator.pop(ctx, true);
                        } on DioException catch (e) {
                          if (!ctx.mounted) return;
                          showAppMessage(ctx, dioErrorMessage(e), isError: true);
                        }
                      },
                child: Text(
                  isFrontDesk ? 'Request date change' : 'Save dates',
                ),
              ),
          ],
        );
      },
    ),
  );

  checkInCtrl.dispose();
  checkOutCtrl.dispose();
  return saved == true;
}
