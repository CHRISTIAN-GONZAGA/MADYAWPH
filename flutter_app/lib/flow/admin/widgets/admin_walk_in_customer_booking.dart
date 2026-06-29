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
import 'free_breakfast_selection.dart';
import 'hourly_billing.dart';
import 'walk_in_complimentary_picker.dart';
import 'admin_walk_in_stay_calendar_dialog.dart';
import 'booking_mode_field.dart';
import 'guest_nationalities.dart';
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

  final selectedDates = await showWalkInRoomStayCalendar(
    context: context,
    room: room,
  );
  if (selectedDates == null || !context.mounted) return false;

  final nameCtrl = TextEditingController(text: savedGuest?.name ?? '');
  final emailCtrl = TextEditingController(text: savedGuest?.email ?? '');
  final phoneCtrl = TextEditingController(text: savedGuest?.phone ?? '');
  final checkInCtrl = TextEditingController();
  final checkOutCtrl = TextEditingController();
  final bookingModeOtherCtrl = TextEditingController();

  final today = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  DateTime? checkInDate = selectedDates.checkIn;
  DateTime? checkOutDate = selectedDates.checkOut;
  checkInCtrl.text = checkInDate.toIso8601String().split('T').first;
  checkOutCtrl.text = checkOutDate.toIso8601String().split('T').first;

  var discountType = 'none';
  var paymentMethod = 'Cash';
  var bookingMode = BookingModeOptions.defaultValue;
  XFile? discountIdFile;
  XFile? guestIdFile;
  var adults = 1;
  var children = 0;
  var guestsMale = 0;
  var guestsFemale = 0;
  var guestNationality = 'Filipino';
  final complimentaryQty = <String, int>{};
  var amenityMenuItems = const <Map<String, dynamic>>[];

  try {
    final menuRes =
        await portalDio().get<Map<String, dynamic>>('/admin/amenity-menu');
    amenityMenuItems = ((menuRes.data?['data'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .where((item) => item['is_active'] != false)
        .toList();
  } catch (_) {
    amenityMenuItems = const [];
  }
  if (!context.mounted) return false;

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
                  label: '${dialogContext.tr('email_gmail')} (optional)',
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 8),
                AppInput(
                  controller: phoneCtrl,
                  label: '${dialogContext.tr('phone_number')} (optional)',
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                Text(
                  'Guests in room',
                  style: Theme.of(dialogContext).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                _WalkInCounterRow(
                  label: 'Adults',
                  value: adults,
                  min: 1,
                  onChanged: (v) => setLocal(() => adults = v),
                ),
                _WalkInCounterRow(
                  label: 'Children',
                  value: children,
                  onChanged: (v) => setLocal(() => children = v),
                ),
                const SizedBox(height: 8),
                Text(
                  'Demographics (head count)',
                  style: Theme.of(dialogContext).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                _WalkInCounterRow(
                  label: 'Male',
                  value: guestsMale,
                  onChanged: (v) => setLocal(() => guestsMale = v),
                ),
                _WalkInCounterRow(
                  label: 'Female',
                  value: guestsFemale,
                  onChanged: (v) => setLocal(() => guestsFemale = v),
                ),
                DropdownButtonFormField<String>(
                  value: guestNationality,
                  decoration: const InputDecoration(
                    labelText: 'Nationality',
                    border: OutlineInputBorder(),
                  ),
                  items: GuestNationalities.all
                      .map(
                        (n) => DropdownMenuItem(value: n, child: Text(n)),
                      )
                      .toList(),
                  onChanged: (v) => setLocal(() {
                    guestNationality = v ?? 'Filipino';
                  }),
                ),
                if (amenityMenuItems.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  WalkInComplimentaryPicker(
                    menuItems: amenityMenuItems,
                    quantitiesById: complimentaryQty,
                    onChanged: () => setLocal(() {}),
                  ),
                ],
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
                BookingModeField(
                  mode: bookingMode,
                  otherController: bookingModeOtherCtrl,
                  onModeChanged: (value) => setLocal(() => bookingMode = value),
                ),
                const SizedBox(height: 8),
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
                if (email.isNotEmpty && !email.contains('@')) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('Enter a valid email address.')),
                  );
                  return;
                }
                if (phone.isNotEmpty && phone.length < 7) {
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
                if (bookingMode == 'other' &&
                    bookingModeOtherCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Specify the booking mode or choose another option.',
                      ),
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
                  'booking_mode': BookingModeOptions.apiValue(
                    bookingMode,
                    bookingModeOtherCtrl.text,
                  ),
                  'adults': adults,
                  'children': children,
                  'guests_male': guestsMale,
                  'guests_female': guestsFemale,
                  'guest_nationality': guestNationality,
                  'free_breakfast_options': amenityMenuItems
                      .map((item) {
                        final id = (item['id'] ?? item['_id'] ?? '').toString();
                        final qty = complimentaryQty[id] ?? 0;
                        if (qty <= 0) return null;
                        return {
                          'menu_item_id': id,
                          'name': (item['name'] ?? '').toString(),
                          'quantity': qty,
                          'amenity_type':
                              (item['amenity_type'] ?? item['type'] ?? '')
                                  .toString(),
                        };
                      })
                      .whereType<Map<String, dynamic>>()
                      .toList(),
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
  bookingModeOtherCtrl.dispose();

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
        adults: (payload['adults'] as num?)?.toInt() ?? 1,
        children: (payload['children'] as num?)?.toInt() ?? 0,
        guestsMale: (payload['guests_male'] as num?)?.toInt() ?? 0,
        guestsFemale: (payload['guests_female'] as num?)?.toInt() ?? 0,
        guestNationality: (payload['guest_nationality'] ?? 'Filipino').toString(),
        bookingMode: (payload['booking_mode'] ?? BookingModeOptions.defaultValue)
            .toString(),
        freeBreakfastSelections: FreeBreakfastSelection.listFromDynamic(
          payload['free_breakfast_options'] as List?,
        ),
      ),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Room ${room['room_number']} booked. Open the Book tab to check the guest in when they arrive.',
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

class _WalkInCounterRow extends StatelessWidget {
  const _WalkInCounterRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
  });

  final String label;
  final int value;
  final int min;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: value > min ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          SizedBox(
            width: 28,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => onChanged(value + 1),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }
}
