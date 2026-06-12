import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../dio_client.dart';
import '../../../widgets/admin_time_slot_field.dart';
import 'hourly_billing.dart';

Future<bool> showAdminManualBookingDialog({
  required BuildContext context,
  required Map<String, dynamic> room,
  required Future<void> Function() onSuccess,
}) async {
  final nameCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  var checkInDate = DateTime.now();
  var checkOutDate = DateTime.now().add(const Duration(hours: 3));
  var checkInTime = AdminTimeSlotField.snapToSlot(TimeOfDay.fromDateTime(checkInDate));
  var checkOutTime = AdminTimeSlotField.snapToSlot(TimeOfDay.fromDateTime(checkOutDate));
  var checkInNow = true;
  var busy = false;
  String? error;

  final roomNo = (room['room_number'] ?? '').toString();
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        DateTime checkInAt() => DateTime(
              checkInDate.year,
              checkInDate.month,
              checkInDate.day,
              checkInTime.hour,
              checkInTime.minute,
            );
        DateTime checkOutAt() => DateTime(
              checkOutDate.year,
              checkOutDate.month,
              checkOutDate.day,
              checkOutTime.hour,
              checkOutTime.minute,
            );

        final inAt = checkInAt();
        final outAt = checkOutAt();
        final validWindow = outAt.isAfter(inAt);
        final estimated = validWindow
            ? HourlyBilling.stayCharge(room, inAt, outAt)
            : 0.0;
        final stayHours =
            validWindow ? HourlyBilling.stayHours(inAt, outAt) : 0;
        final isHourly = HourlyBilling.isHourly(room);

        Future<void> submit() async {
          if (nameCtrl.text.trim().isEmpty ||
              emailCtrl.text.trim().isEmpty ||
              phoneCtrl.text.trim().isEmpty) {
            setLocal(() => error = 'Enter guest name, email, and phone.');
            return;
          }
          if (!validWindow) {
            setLocal(() => error = 'Check-out must be after check-in.');
            return;
          }
          setLocal(() {
            busy = true;
            error = null;
          });
          try {
            await portalDio().post('/admin/bookings', data: {
              'room_id': (room['id'] ?? '').toString(),
              'guest_name': nameCtrl.text.trim(),
              'guest_email': emailCtrl.text.trim(),
              'guest_phone': phoneCtrl.text.trim(),
              'check_in_at': inAt.toIso8601String(),
              'check_out_at': outAt.toIso8601String(),
              'payment_method': 'Cash',
              'check_in_now': checkInNow,
            });
            if (!ctx.mounted) return;
            Navigator.of(ctx).pop(true);
          } on DioException catch (e) {
            setLocal(() {
              busy = false;
              error = dioErrorMessage(e);
            });
          } catch (e) {
            setLocal(() {
              busy = false;
              error = '$e';
            });
          }
        }

        return AlertDialog(
          title: Text('Book Room $roomNo'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  HourlyBilling.priceLabel(room),
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Guest name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Check-in date'),
                  subtitle: Text(
                    '${checkInDate.year}-${checkInDate.month.toString().padLeft(2, '0')}-${checkInDate.day.toString().padLeft(2, '0')}',
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      firstDate:
                          DateTime.now().subtract(const Duration(days: 1)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      initialDate: checkInDate,
                    );
                    if (picked != null) {
                      setLocal(() => checkInDate = picked);
                    }
                  },
                ),
                AdminTimeSlotField(
                  label: 'Check-in time',
                  value: checkInTime,
                  onChanged: (t) => setLocal(
                    () => checkInTime = t ?? checkInTime,
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Check-out date'),
                  subtitle: Text(
                    '${checkOutDate.year}-${checkOutDate.month.toString().padLeft(2, '0')}-${checkOutDate.day.toString().padLeft(2, '0')}',
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      firstDate: checkInDate,
                      lastDate: checkInDate.add(const Duration(days: 365)),
                      initialDate: checkOutDate,
                    );
                    if (picked != null) {
                      setLocal(() => checkOutDate = picked);
                    }
                  },
                ),
                AdminTimeSlotField(
                  label: 'Check-out time',
                  value: checkOutTime,
                  onChanged: (t) => setLocal(
                    () => checkOutTime = t ?? checkOutTime,
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Check in immediately'),
                  subtitle: const Text(
                    'Mark guest as checked in after booking',
                  ),
                  value: checkInNow,
                  onChanged: (v) => setLocal(() => checkInNow = v),
                ),
                if (validWindow)
                  Card(
                    color: Theme.of(ctx)
                        .colorScheme
                        .primaryContainer
                        .withValues(alpha: 0.35),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Estimated bill',
                            style: Theme.of(ctx)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          if (isHourly) Text('$stayHours hour(s) stay'),
                          Text(
                            '₱${estimated.toStringAsFixed(0)}',
                            style: Theme.of(ctx)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: Theme.of(ctx).colorScheme.primary,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    error!,
                    style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: busy ? null : submit,
              child: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create booking'),
            ),
          ],
        );
      },
    ),
  );

  nameCtrl.dispose();
  emailCtrl.dispose();
  phoneCtrl.dispose();

  if (result == true) {
    await onSuccess();
    return true;
  }
  return false;
}
