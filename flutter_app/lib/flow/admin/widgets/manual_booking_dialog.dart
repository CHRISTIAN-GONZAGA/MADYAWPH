import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../dio_client.dart';
import '../../../widgets/admin_time_slot_field.dart';
import '../admin_dashboard_models.dart';
import '../../admin_rooms.dart';
import 'hourly_billing.dart';

Future<bool> showAdminManualBookingDialog({
  required BuildContext context,
  required Map<String, dynamic> room,
  required Future<void> Function() onSuccess,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (ctx) {
      final height = MediaQuery.sizeOf(ctx).height * 0.92;
      return SizedBox(
        height: height,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: _ManualBookingSheet(
            room: room,
            onSuccess: onSuccess,
          ),
        ),
      );
    },
  );

  return result == true;
}

/// Tap on room board tile — book if vacant, otherwise open room details.
Future<void> handleAdminWalkInRoomTap(
  BuildContext context, {
  required Map<String, dynamic> room,
  required Future<void> Function() onSuccess,
}) async {
  final roomId = (room['id'] ?? '').toString();

  if (AdminDashboardModels.isWalkInBookable(room)) {
    if (roomId.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Room data is incomplete. Pull to refresh the dashboard.',
          ),
        ),
      );
      return;
    }
    final booked = await showAdminManualBookingDialog(
      context: context,
      room: room,
      onSuccess: onSuccess,
    );
    if (booked && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Room ${room['room_number']} booked successfully.'),
        ),
      );
    }
    return;
  }

  if (roomId.isEmpty) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => AdminRoomDetailScreen(roomId: roomId),
    ),
  );
}

class _ManualBookingSheet extends StatefulWidget {
  const _ManualBookingSheet({
    required this.room,
    required this.onSuccess,
  });

  final Map<String, dynamic> room;
  final Future<void> Function() onSuccess;

  @override
  State<_ManualBookingSheet> createState() => _ManualBookingSheetState();
}

class _ManualBookingSheetState extends State<_ManualBookingSheet> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  late DateTime _checkInDate;
  late DateTime _checkOutDate;
  late TimeOfDay _checkInTime;
  late TimeOfDay _checkOutTime;
  var _checkInNow = true;
  var _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _checkInDate = DateTime(now.year, now.month, now.day);
    _checkOutDate = _checkInDate.add(const Duration(days: 1));
    _checkInTime = AdminTimeSlotField.snapToSlot(TimeOfDay.fromDateTime(now));
    _checkOutTime = const TimeOfDay(hour: 11, minute: 0);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  DateTime _checkInAt() => DateTime(
        _checkInDate.year,
        _checkInDate.month,
        _checkInDate.day,
        _checkInTime.hour,
        _checkInTime.minute,
      );

  DateTime _checkOutAt() => DateTime(
        _checkOutDate.year,
        _checkOutDate.month,
        _checkOutDate.day,
        _checkOutTime.hour,
        _checkOutTime.minute,
      );

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty ||
        _emailCtrl.text.trim().isEmpty ||
        _phoneCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Enter guest name, email, and phone.');
      return;
    }
    final inAt = _checkInAt();
    final outAt = _checkOutAt();
    if (!outAt.isAfter(inAt)) {
      setState(() => _error = 'Check-out must be after check-in.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await portalDio().post('/admin/bookings', data: {
        'room_id': (widget.room['id'] ?? '').toString(),
        'guest_name': _nameCtrl.text.trim(),
        'guest_email': _emailCtrl.text.trim(),
        'guest_phone': _phoneCtrl.text.trim(),
        'check_in_at': inAt.toIso8601String(),
        'check_out_at': outAt.toIso8601String(),
        'payment_method': 'Cash',
        'check_in_now': _checkInNow,
      });
      if (!mounted) return;
      await widget.onSuccess();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = dioErrorMessage(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  Future<void> _pickDate({required bool checkIn}) async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: checkIn ? _checkInDate : _checkOutDate,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (checkIn) {
        _checkInDate = picked;
        if (!_checkOutDate.isAfter(_checkInDate)) {
          _checkOutDate = _checkInDate.add(const Duration(days: 1));
        }
      } else {
        _checkOutDate = picked.isBefore(_checkInDate)
            ? _checkInDate.add(const Duration(days: 1))
            : picked;
      }
    });
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roomNo = (widget.room['room_number'] ?? '—').toString();
    final inAt = _checkInAt();
    final outAt = _checkOutAt();
    final validWindow = outAt.isAfter(inAt);
    final estimated =
        validWindow ? HourlyBilling.stayCharge(widget.room, inAt, outAt) : 0.0;
    final stayHours = validWindow ? HourlyBilling.stayHours(inAt, outAt) : 0;
    final isHourly = HourlyBilling.isHourly(widget.room);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      children: [
            Text(
              'Walk-in booking',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Room $roomNo · ${HourlyBilling.priceLabel(widget.room)}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Guest name *',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email *',
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone *',
                prefixIcon: Icon(Icons.phone_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Stay schedule',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(checkIn: true),
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text('In ${_fmtDate(_checkInDate)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(checkIn: false),
                    icon: const Icon(Icons.event, size: 18),
                    label: Text('Out ${_fmtDate(_checkOutDate)}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AdminTimeSlotField(
              label: 'Check-in time',
              value: _checkInTime,
              onChanged: (t) {
                if (t != null) setState(() => _checkInTime = t);
              },
            ),
            const SizedBox(height: 12),
            AdminTimeSlotField(
              label: 'Check-out time',
              value: _checkOutTime,
              onChanged: (t) {
                if (t != null) setState(() => _checkOutTime = t);
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Check in immediately'),
              subtitle: const Text('Mark guest as checked in after booking'),
              value: _checkInNow,
              onChanged: (v) => setState(() => _checkInNow = v),
            ),
            if (validWindow) ...[
              const SizedBox(height: 8),
              Card(
                color: scheme.primaryContainer.withValues(alpha: 0.35),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(Icons.receipt_long, color: scheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Estimated bill',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            if (isHourly)
                              Text('$stayHours hour(s) stay'),
                            Text(
                              '₱${estimated.toStringAsFixed(0)}',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: scheme.primary,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: scheme.error),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Create booking'),
                  ),
                ),
              ],
            ),
          ],
        );
  }
}
