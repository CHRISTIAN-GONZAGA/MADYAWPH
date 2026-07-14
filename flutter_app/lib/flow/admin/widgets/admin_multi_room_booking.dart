import 'package:dio/dio.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../auth_storage.dart';
import '../../../dio_client.dart';
import '../../../locale_controller.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_input.dart';
import '../../../widgets/chat_attachment.dart';
import '../../member_qr_scan.dart';
import '../../widgets/complete_guest_booking_dialog.dart';
import 'admin_multi_room_stay_calendar_dialog.dart';
import 'booking_mode_field.dart';
import 'guest_nationalities.dart';
import 'hourly_billing.dart';
import 'manual_booking_dialog.dart';
import 'multi_room_booking_summary.dart';

/// Group walk-in booking — same steps as single room: calendar → guest form → submit.
Future<bool> showAdminMultiRoomWalkInBooking({
  required BuildContext context,
  required List<Map<String, dynamic>> rooms,
}) async {
  if (rooms.length < 2) {
    showAppMessage(
      context,
      'Select at least two rooms for a group booking.',
      isError: true,
    );
    return false;
  }

  ({String name, String email, String phone})? savedGuest;
  try {
    savedGuest = await AuthStorage.customerGuestContact();
  } catch (_) {
    savedGuest = null;
  }
  if (!context.mounted) return false;

  final selectedDates = await showMultiRoomWalkInStayCalendar(
    context: context,
    rooms: rooms,
  );
  if (selectedDates == null || !context.mounted) return false;

  Map<String, List<Map<String, dynamic>>> staysByRoom;
  try {
    staysByRoom = await loadStayCalendarsForRooms(rooms);
  } catch (_) {
    staysByRoom = {};
  }
  if (!context.mounted) return false;

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
  var memberShidId = '';
  var memberDiscountPercent = 0.0;
  var paymentMethod = 'Cash';
  var bookingMode = BookingModeOptions.defaultValue;
  XFile? discountIdFile;
  XFile? guestIdFile;
  var adults = 1;
  var children = 0;
  var guestsMale = 0;
  var guestsFemale = 0;
  var guestNationality = 'Filipino';

  if (!context.mounted) return false;

  final roomNumbers = rooms
      .map((r) => (r['room_number'] ?? '—').toString())
      .toList()
    ..sort();

  final payload = await showDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setLocal) {
        final discountPct = memberDiscountPercent > 0
            ? memberDiscountPercent
            : switch (discountType) {
                'pwd' => 20.0,
                'senior' => 20.0,
                _ => 0.0,
              };
        final anchorRoom = rooms.first;
        final durationLabel = (checkInDate != null && checkOutDate != null)
            ? (HourlyBilling.isHourly(anchorRoom)
                ? () {
                    final inAt =
                        HourlyBilling.customerStayCheckIn(checkInDate!);
                    final outAt = HourlyBilling.customerStayCheckOut(
                      anchorRoom,
                      checkInDate!,
                      checkOutDate!,
                    );
                    final hours = HourlyBilling.stayHours(inAt, outAt);
                    final blocks = HourlyBilling.blocksForStay(
                      hours,
                      HourlyBilling.blockHours(anchorRoom),
                    );
                    return '$hours hr(s) · $blocks block(s) of ${HourlyBilling.blockHours(anchorRoom)}h';
                  }()
                : () {
                    final nights =
                        checkOutDate!.difference(checkInDate!).inDays;
                    final safeNights = nights > 0 ? nights : 0;
                    return '$safeNights night${safeNights == 1 ? '' : 's'}';
                  }())
            : '';

        Future<void> pickCheckIn() async {
          final picked = await showDatePicker(
            context: dialogContext,
            firstDate: today,
            lastDate: today.add(const Duration(days: 365)),
            initialDate: checkInDate ?? today,
          );
          if (picked == null) return;
          if (checkOutDate != null &&
              staysByRoom.isNotEmpty &&
              walkInRangeOverlapsAnyRoomStays(
                staysByRoom,
                picked,
                checkOutDate!,
              )) {
            if (dialogContext.mounted) {
              showAppMessage(
                dialogContext,
                'Those dates overlap a stay on one or more selected rooms.',
                isError: true,
              );
            }
            return;
          }
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
            showAppMessage(
              dialogContext,
              dialogContext.tr('select_checkin_first'),
            );
            return;
          }
          final picked = await showDatePicker(
            context: dialogContext,
            firstDate: HourlyBilling.isHourly(anchorRoom)
                ? checkInDate!
                : checkInDate!.add(const Duration(days: 1)),
            lastDate: checkInDate!.add(const Duration(days: 365)),
            initialDate: checkOutDate ??
                (HourlyBilling.isHourly(anchorRoom)
                    ? checkInDate!
                    : checkInDate!.add(const Duration(days: 1))),
          );
          if (picked == null) return;
          if (staysByRoom.isNotEmpty &&
              walkInRangeOverlapsAnyRoomStays(
                staysByRoom,
                checkInDate!,
                picked,
              )) {
            if (dialogContext.mounted) {
              showAppMessage(
                dialogContext,
                'Those dates overlap a stay on one or more selected rooms.',
                isError: true,
              );
            }
            return;
          }
          checkOutDate = picked;
          checkOutCtrl.text = picked.toIso8601String().split('T').first;
          setLocal(() {});
        }

        return AlertDialog(
          title: Text('Group booking · ${rooms.length} rooms'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Rooms: ${roomNumbers.join(', ')}',
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
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
                  'Member discount (optional)',
                  style: Theme.of(dialogContext).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                if (memberShidId.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '${memberDiscountPercent.toStringAsFixed(0)}% off — $memberShidId',
                      style: TextStyle(
                        color: Theme.of(dialogContext).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          double gross = 0;
                          if (checkInDate != null && checkOutDate != null) {
                            for (final room in rooms) {
                              gross += HourlyBilling.customerDateStayCharge(
                                room,
                                checkInDate!,
                                checkOutDate!,
                              );
                            }
                          }
                          final info = await scanMemberForBooking(
                            dialogContext,
                            grossAmountPesos: gross,
                          );
                          if (info == null) return;
                          setLocal(() {
                            memberShidId = info.shid;
                            memberDiscountPercent = info.discountPercent;
                            discountType = 'none';
                            discountIdFile = null;
                          });
                        },
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('Scan member QR'),
                      ),
                    ),
                    if (memberShidId.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Clear member discount',
                        onPressed: () => setLocal(() {
                          memberShidId = '';
                          memberDiscountPercent = 0;
                        }),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ],
                ),
                if (memberShidId.isNotEmpty && memberDiscountPercent > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 4),
                    child: Text(
                      'Central admin member discount applied automatically.',
                      style: Theme.of(dialogContext)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                            color:
                                Theme.of(dialogContext).colorScheme.primary,
                          ),
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  'Guests in room',
                  style: Theme.of(dialogContext).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                _MultiWalkInCounterRow(
                  label: 'Adults',
                  value: adults,
                  min: 1,
                  onChanged: (v) => setLocal(() => adults = v),
                ),
                _MultiWalkInCounterRow(
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
                _MultiWalkInCounterRow(
                  label: 'Male',
                  value: guestsMale,
                  onChanged: (v) => setLocal(() => guestsMale = v),
                ),
                _MultiWalkInCounterRow(
                  label: 'Female',
                  value: guestsFemale,
                  onChanged: (v) => setLocal(() => guestsFemale = v),
                ),
                DropdownButtonFormField<String>(
                  initialValue: guestNationality,
                  decoration: const InputDecoration(
                    labelText: 'Nationality',
                    border: OutlineInputBorder(),
                  ),
                  items: GuestNationalities.all
                      .map((n) => DropdownMenuItem(value: n, child: Text(n)))
                      .toList(),
                  onChanged: (v) =>
                      setLocal(() => guestNationality = v ?? 'Filipino'),
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
                  initialValue: discountType,
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
                  initialValue: paymentMethod,
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
                if (checkInDate != null && checkOutDate != null) ...[
                  const SizedBox(height: 12),
                  MultiRoomBookingTotalSummary(
                    rooms: rooms,
                    checkIn: checkInDate!,
                    checkOut: checkOutDate!,
                    discountPercent: discountPct,
                  ),
                ] else if (durationLabel.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Duration: $durationLabel'),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            AppPrimaryButton(
              label: 'Submit group booking',
              onPressed: () {
                final name = nameCtrl.text.trim();
                final email = emailCtrl.text.trim();
                final phone = phoneCtrl.text.trim();
                if (name.isEmpty) {
                  showAppMessage(dialogContext, 'Enter your full name.');
                  return;
                }
                if (email.isNotEmpty && !email.contains('@')) {
                  showAppMessage(dialogContext, 'Enter a valid email address.');
                  return;
                }
                if (phone.isNotEmpty && phone.length < 7) {
                  showAppMessage(dialogContext, 'Enter a valid phone number.');
                  return;
                }
                if (memberShidId.isEmpty &&
                    discountType != 'none' &&
                    discountIdFile == null) {
                  showAppMessage(
                    dialogContext,
                    'Upload a photo of your discount ID.',
                  );
                  return;
                }
                if (bookingMode == 'other' &&
                    bookingModeOtherCtrl.text.trim().isEmpty) {
                  showAppMessage(
                    dialogContext,
                    'Specify the booking mode or choose another option.',
                  );
                  return;
                }
                if (checkInCtrl.text.trim().isEmpty ||
                    checkOutCtrl.text.trim().isEmpty ||
                    checkInDate == null ||
                    checkOutDate == null) {
                  showAppMessage(dialogContext, 'Select check-in and check-out.');
                  return;
                }
                if (staysByRoom.isNotEmpty &&
                    walkInRangeOverlapsAnyRoomStays(
                      staysByRoom,
                      checkInDate!,
                      checkOutDate!,
                    )) {
                  showAppMessage(
                    dialogContext,
                    'Selected dates overlap a stay on one or more rooms.',
                    isError: true,
                  );
                  return;
                }
                Navigator.of(dialogContext).pop({
                  'guest_name': name,
                  'guest_email': email,
                  'guest_phone': phone,
                  'check_in': checkInCtrl.text.trim(),
                  'check_out': checkOutCtrl.text.trim(),
                  'discount_type': discountType,
                  if (memberShidId.isNotEmpty) 'member_shid_id': memberShidId,
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
    await submitAdminBulkWalkInBooking(
      rooms: rooms,
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
        freeBreakfastSelections: const [],
        memberShidId: (payload['member_shid_id'] ?? '').toString(),
      ),
    );
    if (context.mounted) {
      final checkIn = DateTime.parse((payload['check_in'] ?? '').toString());
      final checkOut = DateTime.parse((payload['check_out'] ?? '').toString());
      final lines = computeMultiRoomChargeLines(
        rooms: rooms,
        checkIn: checkIn,
        checkOut: checkOut,
      );
      final gross = multiRoomGrossTotal(lines);
      showAppMessage(
        context,
        'Booked ${rooms.length} rooms for ${payload['guest_name']}. '
        'Total due: ${formatPeso(gross)}. '
        'Open the Book tab to check guests in when they arrive.',
      );
    }
    return true;
  } on DioException catch (e) {
    if (context.mounted) {
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
    return false;
  } catch (e) {
    if (context.mounted) {
      showAppMessage(context, '$e', isError: true);
    }
    return false;
  }
}

class _MultiWalkInCounterRow extends StatelessWidget {
  const _MultiWalkInCounterRow({
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
