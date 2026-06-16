import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../auth_storage.dart';
import '../../../dio_client.dart';
import '../../../locale_controller.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_input.dart';
import '../../../widgets/chat_attachment.dart';
import '../../widgets/complete_guest_booking_dialog.dart';
import 'hourly_billing.dart';
import 'manual_booking_dialog.dart';

/// Same booking popup + submit path as [CustomerRoomsScreen] admin walk-in.
Future<bool> showAdminWalkInCustomerStyleBooking({
  required BuildContext context,
  required String hotelId,
  required Map<String, dynamic> room,
}) async {
  ({String name, String email, String phone})? savedGuest;
  try {
    savedGuest = await AuthStorage.customerGuestContact();
  } catch (_) {
    savedGuest = null;
  }
  if (!context.mounted) return false;

  final nameCtrl = TextEditingController(text: savedGuest?.name ?? '');
  final emailCtrl = TextEditingController(text: savedGuest?.email ?? '');
  final phoneCtrl = TextEditingController(text: savedGuest?.phone ?? '');
  final checkInCtrl = TextEditingController();
  final checkOutCtrl = TextEditingController();

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  DateTime? checkInDate = today;
  DateTime? checkOutDate = today.add(const Duration(days: 1));
  checkInCtrl.text = checkInDate.toIso8601String().split('T').first;
  checkOutCtrl.text = checkOutDate.toIso8601String().split('T').first;

  var discountType = 'none';
  var paymentMethod = 'Cash';
  XFile? discountIdFile;
  XFile? guestIdFile;

  final payload = await showDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setLocal) {
        final nights = (checkInDate != null && checkOutDate != null)
            ? checkOutDate!.difference(checkInDate!).inDays
            : 0;
        final safeNights = nights > 0 ? nights : 0;
        final estTotal = (checkInDate != null && checkOutDate != null)
            ? HourlyBilling.customerDateStayCharge(
                room,
                checkInDate!,
                checkOutDate!,
              )
            : 0.0;
        final discountPct = switch (discountType) {
          'pwd' => 20.0,
          'senior' => 20.0,
          _ => 0.0,
        };
        final estAfterDiscount = HourlyBilling.round50(
          estTotal * (1 - (discountPct / 100)),
        );
        final durationLabel = (checkInDate != null && checkOutDate != null)
            ? (HourlyBilling.isHourly(room)
                ? () {
                    final inAt =
                        HourlyBilling.customerStayCheckIn(checkInDate!);
                    final outAt = HourlyBilling.customerStayCheckOut(
                      room,
                      checkInDate!,
                      checkOutDate!,
                    );
                    final hours = HourlyBilling.stayHours(inAt, outAt);
                    final blocks = HourlyBilling.blocksForStay(
                      hours,
                      HourlyBilling.blockHours(room),
                    );
                    return '$hours hr(s) · $blocks block(s) of ${HourlyBilling.blockHours(room)}h';
                  }()
                : '$safeNights night${safeNights == 1 ? '' : 's'}')
            : '';

        Future<void> pickCheckIn() async {
          final picked = await showDatePicker(
            context: dialogContext,
            firstDate: today,
            lastDate: today.add(const Duration(days: 365)),
            initialDate: checkInDate ?? today,
          );
          if (picked == null) return;
          checkInDate = picked;
          if (checkOutDate != null && !checkOutDate!.isAfter(picked)) {
            checkOutDate = null;
            checkOutCtrl.clear();
          }
          checkInCtrl.text = picked.toIso8601String().split('T').first;
          setLocal(() {});
        }

        Future<void> pickCheckOut() async {
          if (checkInDate == null) {
            ScaffoldMessenger.of(dialogContext).showSnackBar(
              SnackBar(content: Text(dialogContext.tr('select_checkin_first'))),
            );
            return;
          }
          final picked = await showDatePicker(
            context: dialogContext,
            firstDate: HourlyBilling.isHourly(room)
                ? checkInDate!
                : checkInDate!.add(const Duration(days: 1)),
            lastDate: checkInDate!.add(const Duration(days: 365)),
            initialDate: checkOutDate ??
                (HourlyBilling.isHourly(room)
                    ? checkInDate!
                    : checkInDate!.add(const Duration(days: 1))),
          );
          if (picked == null) return;
          checkOutDate = picked;
          checkOutCtrl.text = picked.toIso8601String().split('T').first;
          setLocal(() {});
        }

        return AlertDialog(
          title: const Text('Complete your booking'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppInput(
                  controller: nameCtrl,
                  label: dialogContext.tr('full_name'),
                ),
                const SizedBox(height: 8),
                AppInput(
                  controller: emailCtrl,
                  label: dialogContext.tr('email_gmail'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 8),
                AppInput(
                  controller: phoneCtrl,
                  label: dialogContext.tr('phone_number'),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final file = await ChatAttachment.pick(dialogContext);
                    if (file != null) setLocal(() => guestIdFile = file);
                  },
                  icon: const Icon(Icons.credit_card_outlined),
                  label: Text(
                    guestIdFile == null
                        ? 'Upload government ID (optional)'
                        : 'ID attached — tap to replace',
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: discountType,
                  decoration: const InputDecoration(
                    labelText: 'Discount (optional)',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'none', child: Text('No discount')),
                    DropdownMenuItem(value: 'pwd', child: Text('PWD (20% off)')),
                    DropdownMenuItem(
                      value: 'senior',
                      child: Text('Senior citizen (20% off)'),
                    ),
                  ],
                  onChanged: (v) => setLocal(() {
                    discountType = v ?? 'none';
                    if (discountType == 'none') discountIdFile = null;
                  }),
                ),
                if (discountType != 'none') ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final file = await ChatAttachment.pick(dialogContext);
                      if (file != null) setLocal(() => discountIdFile = file);
                    },
                    icon: const Icon(Icons.badge_outlined),
                    label: Text(
                      discountIdFile == null
                          ? 'Upload discount ID photo'
                          : 'Discount ID attached — tap to replace',
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                AppInput(
                  controller: checkInCtrl,
                  label: 'Check-in date',
                  hint: 'Tap to open calendar',
                  readOnly: true,
                  onTap: pickCheckIn,
                  suffixIcon: const Icon(Icons.calendar_month_outlined),
                ),
                const SizedBox(height: 8),
                AppInput(
                  controller: checkOutCtrl,
                  label: 'Check-out date',
                  hint: 'Tap to open calendar',
                  readOnly: true,
                  onTap: pickCheckOut,
                  suffixIcon: const Icon(Icons.calendar_month_outlined),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: paymentMethod,
                  decoration: const InputDecoration(
                    labelText: 'Payment method',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                    DropdownMenuItem(value: 'GCash', child: Text('GCash')),
                    DropdownMenuItem(value: 'PayMaya', child: Text('PayMaya')),
                    DropdownMenuItem(
                      value: 'Credit Card',
                      child: Text('Credit Card'),
                    ),
                  ],
                  onChanged: (v) => setLocal(() => paymentMethod = v ?? 'Cash'),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Duration: $durationLabel\n'
                    'Estimated: ₱${estTotal.toStringAsFixed(2)}'
                    '${discountPct > 0 ? ' → ₱${estAfterDiscount.toStringAsFixed(2)} after discount' : ''}',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            AppPrimaryButton(
              label: 'Submit booking',
              onPressed: () {
                final name = nameCtrl.text.trim();
                final email = emailCtrl.text.trim();
                final phone = phoneCtrl.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('Enter your full name.')),
                  );
                  return;
                }
                if (email.isEmpty || !email.contains('@')) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('Enter a valid email address.')),
                  );
                  return;
                }
                if (phone.length < 7) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('Enter a valid phone number.')),
                  );
                  return;
                }
                if (discountType != 'none' && discountIdFile == null) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('Upload a photo of your discount ID.'),
                    ),
                  );
                  return;
                }
                if (checkInCtrl.text.trim().isEmpty ||
                    checkOutCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('Select check-in and check-out.'),
                    ),
                  );
                  return;
                }
                Navigator.of(dialogContext).pop({
                  'guest_name': nameCtrl.text.trim(),
                  'guest_email': emailCtrl.text.trim(),
                  'guest_phone': phoneCtrl.text.trim(),
                  'check_in': checkInCtrl.text.trim(),
                  'check_out': checkOutCtrl.text.trim(),
                  'discount_type': discountType,
                  'payment_method': paymentMethod,
                });
              },
            ),
          ],
        );
      },
    ),
  );

  nameCtrl.dispose();
  emailCtrl.dispose();
  phoneCtrl.dispose();
  checkInCtrl.dispose();
  checkOutCtrl.dispose();

  if (payload == null || !context.mounted) return false;

  try {
    await submitAdminWalkInBooking(
      room: room,
      payload: CompleteGuestBookingPayload(
        guestName: (payload['guest_name'] ?? '').toString(),
        guestEmail: (payload['guest_email'] ?? '').toString(),
        guestPhone: (payload['guest_phone'] ?? '').toString(),
        checkIn: (payload['check_in'] ?? '').toString(),
        checkOut: (payload['check_out'] ?? '').toString(),
        discountType: (payload['discount_type'] ?? 'none').toString(),
        paymentMethod: (payload['payment_method'] ?? 'Cash').toString(),
        guestIdFile: guestIdFile,
        discountIdFile: discountIdFile,
      ),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Room ${room['room_number']} booked as a local walk-in.',
          ),
        ),
      );
    }
    return true;
  } on DioException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dioErrorMessage(e))),
      );
    }
    return false;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
    return false;
  }
}

/// Alias used by [AdminRoomNavigation] and legacy call sites.
Future<bool> showAdminWalkInBookingDialog({
  required BuildContext context,
  required Map<String, dynamic> room,
  String hotelId = '',
}) {
  return showAdminWalkInCustomerStyleBooking(
    context: context,
    hotelId: hotelId,
    room: room,
  );
}
