import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';
import 'package:image_picker/image_picker.dart';

import '../../../dio_client.dart';
import '../../../widgets/app_input.dart';
import '../../../widgets/chat_attachment.dart';
import '../../widgets/complete_guest_booking_dialog.dart';
import '../admin_dashboard_models.dart';
import '../widgets/guest_nationalities.dart';
import '../widgets/manual_booking_dialog.dart';
class MultipleBookingSection extends StatefulWidget {
  const MultipleBookingSection({
    super.key,
    required this.rooms,
    required this.onBooked,
  });

  final List<Map<String, dynamic>> rooms;
  final Future<void> Function() onBooked;

  @override
  State<MultipleBookingSection> createState() => _MultipleBookingSectionState();
}

class _MultipleBookingSectionState extends State<MultipleBookingSection> {
  final _selected = <String>{};

  List<Map<String, dynamic>> get _bookable {
    return widget.rooms.where(AdminDashboardModels.isWalkInBookable).toList();
  }

  Future<void> _bookSelected() async {
    final selectedRooms = _bookable
        .where((r) => _selected.contains(AdminDashboardModels.roomIdOf(r)))
        .toList();
    if (selectedRooms.length < 2) {
      showAppMessage(
        context,
        'Select at least two rooms for a group booking.',
        isError: true,
      );
      return;
    }

    final today = DateTime.now();
    final checkIn = DateTime(today.year, today.month, today.day);
    final checkOut = checkIn.add(const Duration(days: 1));
    final checkInCtrl = TextEditingController(
      text: checkIn.toIso8601String().split('T').first,
    );
    final checkOutCtrl = TextEditingController(
      text: checkOut.toIso8601String().split('T').first,
    );
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    var paymentMethod = 'Cash';
    var guestNationality = 'Filipino';
    var adults = 1;
  var children = 0;
    XFile? guestIdFile;

    final submitted = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Book ${selectedRooms.length} rooms'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppInput(
                    controller: nameCtrl,
                    label: 'Guest name',
                  ),
                  const SizedBox(height: 8),
                  AppInput(
                    controller: phoneCtrl,
                    label: 'Phone',
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 8),
                  AppInput(
                    controller: emailCtrl,
                    label: 'Email (optional)',
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 8),
                  AppInput(
                    controller: checkInCtrl,
                    label: 'Check-in date (YYYY-MM-DD)',
                  ),
                  const SizedBox(height: 8),
                  AppInput(
                    controller: checkOutCtrl,
                    label: 'Check-out date (YYYY-MM-DD)',
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
                      DropdownMenuItem(
                        value: 'PayMaya',
                        child: Text('PayMaya'),
                      ),
                      DropdownMenuItem(
                        value: 'Credit Card',
                        child: Text('Credit Card'),
                      ),
                    ],
                    onChanged: (v) => setLocal(() => paymentMethod = v ?? 'Cash'),
                  ),
                  const SizedBox(height: 8),
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
                    onChanged: (v) =>
                        setLocal(() => guestNationality = v ?? 'Filipino'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final file = await ChatAttachment.pick(ctx);
                      if (file != null) {
                        setLocal(() => guestIdFile = file);
                      }
                    },
                    icon: const Icon(Icons.badge_outlined),
                    label: Text(
                      guestIdFile == null
                          ? 'Upload government ID (optional)'
                          : 'ID: ${guestIdFile!.name}',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Create bookings'),
            ),
          ],
        ),
      ),
    );

    if (submitted != true || !mounted) {
      nameCtrl.dispose();
      emailCtrl.dispose();
      phoneCtrl.dispose();
      checkInCtrl.dispose();
      checkOutCtrl.dispose();
      return;
    }

    final payload = CompleteGuestBookingPayload(
      guestName: nameCtrl.text.trim(),
      guestEmail: emailCtrl.text.trim(),
      guestPhone: phoneCtrl.text.trim(),
      checkIn: checkInCtrl.text.trim(),
      checkOut: checkOutCtrl.text.trim(),
      paymentMethod: paymentMethod,
      adults: adults,
      children: children,
      guestsMale: 0,
      guestsFemale: 0,
      guestNationality: guestNationality,
      discountType: 'none',
      bookingMode: 'walk-in',
      guestIdFile: guestIdFile,
    );
    nameCtrl.dispose();
    emailCtrl.dispose();
    phoneCtrl.dispose();
    checkInCtrl.dispose();
    checkOutCtrl.dispose();

    if (payload.guestName.isEmpty) {
      showAppMessage(context, 'Guest name is required.', isError: true);
      return;
    }

    try {
      await submitAdminBulkWalkInBooking(
        rooms: selectedRooms,
        payload: payload,
      );
      if (!mounted) return;
      setState(_selected.clear);
      await widget.onBooked();
      if (!mounted) return;
      showAppMessage(
        context,
        'Created ${selectedRooms.length} bookings for ${payload.guestName}.',
      );
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    } catch (e) {
      if (!mounted) return;
      showAppMessage(context, '$e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookable = AdminDashboardModels.sortRoomsByNumber(_bookable);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            'Group booking',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Select two or more available rooms, then book them under one guest.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (bookable.isEmpty)
          const Expanded(
            child: Center(child: Text('No walk-in bookable rooms right now.')),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 88),
              itemCount: bookable.length,
              itemBuilder: (context, i) {
                final room = bookable[i];
                final id = AdminDashboardModels.roomIdOf(room);
                final roomNo = (room['room_number'] ?? '—').toString();
                final category = AdminDashboardModels.categoryLabel(room);
                return CheckboxListTile(
                  value: _selected.contains(id),
                  onChanged: id.isEmpty
                      ? null
                      : (v) {
                          setState(() {
                            if (v == true) {
                              _selected.add(id);
                            } else {
                              _selected.remove(id);
                            }
                          });
                        },
                  title: Text('Room $roomNo'),
                  subtitle: Text(category),
                  secondary: CircleAvatar(child: Text(roomNo)),
                );
              },
            ),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton(
              onPressed: _selected.length >= 2 ? _bookSelected : null,
              child: Text(
                _selected.isEmpty
                    ? 'Select rooms'
                    : 'Book ${_selected.length} rooms',
              ),
            ),
          ),
        ),
      ],
    );
  }
}
