import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../dio_client.dart';
import '../admin_dashboard_models.dart';

Future<bool> showAdminManageBookingDialog({
  required BuildContext context,
  required Map<String, dynamic> booking,
}) async {
  final bookingId = (booking['id'] ?? '').toString();
  if (bookingId.isEmpty) return false;

  final status = (booking['status'] ?? '').toString().toLowerCase();
  if (status == 'cancelled' || status == 'completed') {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This booking is already closed.')),
    );
    return false;
  }

  final checkInCtrl = TextEditingController(
    text: (booking['check_in_date'] ?? '').toString().split('T').first,
  );
  final checkOutCtrl = TextEditingController(
    text: (booking['check_out_date'] ?? '').toString().split('T').first,
  );
  DateTime? checkIn = AdminDashboardModels.parseDate(
    (booking['check_in_date'] ?? '').toString(),
  );
  DateTime? checkOut = AdminDashboardModels.parseDate(
    (booking['check_out_date'] ?? '').toString(),
  );

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
                  'Saving checks for conflicts with other stays on this room.',
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
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text(dioErrorMessage(e))),
                  );
                }
              },
              child: Text(
                'Cancel booking',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
            ),
            FilledButton(
              onPressed: checkIn == null || checkOut == null
                  ? null
                  : () async {
                      try {
                        await portalDio().patch(
                          '/admin/bookings/$bookingId',
                          data: {
                            'check_in_at':
                                checkIn!.toIso8601String().split('T').first,
                            'check_out_at':
                                checkOut!.toIso8601String().split('T').first,
                          },
                        );
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } on DioException catch (e) {
                        if (!ctx.mounted) return;
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text(dioErrorMessage(e))),
                        );
                      }
                    },
              child: const Text('Save dates'),
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
}) async {
  final id = (reservation['id'] ?? reservation['_id'] ?? '').toString();
  if (id.isEmpty) return false;

  final status = (reservation['status'] ?? '').toString().toLowerCase();
  if (!['pending_approval', 'approved', 'reserved', 'booked'].contains(status)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This reservation cannot be edited.')),
    );
    return false;
  }

  final checkInCtrl = TextEditingController(
    text: (reservation['check_in_date'] ?? '').toString().split('T').first,
  );
  final checkOutCtrl = TextEditingController(
    text: (reservation['check_out_date'] ?? '').toString().split('T').first,
  );
  DateTime? checkIn = AdminDashboardModels.parseDate(
    (reservation['check_in_date'] ?? '').toString(),
  );
  DateTime? checkOut = AdminDashboardModels.parseDate(
    (reservation['check_out_date'] ?? '').toString(),
  );

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
                Text('Status: $status'),
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
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Close'),
            ),
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
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text(dioErrorMessage(e))),
                    );
                  }
                },
                child: Text(
                  'Cancel hold',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                ),
              ),
            FilledButton(
              onPressed: checkIn == null || checkOut == null
                  ? null
                  : () async {
                      try {
                        await portalDio().patch(
                          '/admin/reservations/$id',
                          data: {
                            'check_in_at':
                                checkIn!.toIso8601String().split('T').first,
                            'check_out_at':
                                checkOut!.toIso8601String().split('T').first,
                          },
                        );
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } on DioException catch (e) {
                        if (!ctx.mounted) return;
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text(dioErrorMessage(e))),
                        );
                      }
                    },
              child: const Text('Save dates'),
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
