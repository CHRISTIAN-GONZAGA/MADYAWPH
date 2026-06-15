import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../dio_client.dart';
import '../../../widgets/admin_time_slot_field.dart';
import '../../../widgets/app_input.dart';
import '../../../widgets/app_scaffold.dart';
import '../admin_dashboard_models.dart';
import '../../admin_rooms.dart';
import 'hourly_billing.dart';

const _inputDecoration = InputDecoration(
  border: OutlineInputBorder(),
);

/// Opens the walk-in booking form (full screen — mirrors public customer booking).
Future<bool> showAdminManualBookingDialog({
  required BuildContext context,
  required Map<String, dynamic> room,
  required Future<void> Function() onSuccess,
}) async {
  final result = await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      builder: (_) => AdminWalkInBookingScreen(
        room: room,
        onSuccess: onSuccess,
      ),
    ),
  );
  return result == true;
}

/// Tap on room board tile — book if vacant, otherwise open room details.
Future<void> handleAdminWalkInRoomTap(
  BuildContext context, {
  required Map<String, dynamic> room,
  required Future<void> Function() onSuccess,
}) async {
  final roomId = AdminDashboardModels.roomIdOf(room);

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

class AdminWalkInBookingScreen extends StatefulWidget {
  const AdminWalkInBookingScreen({
    super.key,
    required this.room,
    required this.onSuccess,
  });

  final Map<String, dynamic> room;
  final Future<void> Function() onSuccess;

  @override
  State<AdminWalkInBookingScreen> createState() =>
      _AdminWalkInBookingScreenState();
}

class _AdminWalkInBookingScreenState extends State<AdminWalkInBookingScreen> {
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
  String _paymentMethod = 'Cash';

  static const _paymentMethods = [
    'Cash',
    'GCash',
    'PayMaya',
    'Credit Card',
  ];

  bool get _isHourly => HourlyBilling.isHourly(widget.room);

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

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _submitViaAdminApi(String roomId) async {
    final inAt = _checkInAt();
    final outAt = _checkOutAt();
    await portalDio().post('/admin/bookings', data: {
      'room_id': roomId,
      'guest_name': _nameCtrl.text.trim(),
      'guest_email': _emailCtrl.text.trim(),
      'guest_phone': _phoneCtrl.text.trim(),
      'check_in_at': inAt.toIso8601String(),
      'check_out_at': outAt.toIso8601String(),
      'payment_method': _paymentMethod,
      'check_in_now': _checkInNow,
    });
  }

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
    final roomId = AdminDashboardModels.roomIdOf(widget.room);
    if (roomId.isEmpty) {
      setState(() {
        _error = 'Room ID missing. Refresh the dashboard and try again.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await _submitViaAdminApi(roomId);
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roomNo = (widget.room['room_number'] ?? '—').toString();
    final category = AdminDashboardModels.categoryLabel(widget.room);
    final inAt = _checkInAt();
    final outAt = _checkOutAt();
    final validWindow = outAt.isAfter(inAt);
    final estimated =
        validWindow ? HourlyBilling.stayCharge(widget.room, inAt, outAt) : 0.0;
    final stayHours = validWindow ? HourlyBilling.stayHours(inAt, outAt) : 0;

    return AppScaffold(
      appBar: AppBar(
        title: Text('Walk-in · Room $roomNo'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '$category · ${HourlyBilling.priceLabel(widget.room)}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 20),
          Text(
            'Guest details',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 12),
          AppInput(
            controller: _nameCtrl,
            label: 'Guest name *',
            decoration: _inputDecoration,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          AppInput(
            controller: _emailCtrl,
            label: 'Email *',
            keyboardType: TextInputType.emailAddress,
            decoration: _inputDecoration,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          AppInput(
            controller: _phoneCtrl,
            label: 'Phone *',
            keyboardType: TextInputType.phone,
            decoration: _inputDecoration,
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 24),
          Text(
            'Stay dates & times',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _pickDate(checkIn: true),
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text('Check-in\n${_fmtDate(_checkInDate)}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _pickDate(checkIn: false),
                  icon: const Icon(Icons.event, size: 18),
                  label: Text('Check-out\n${_fmtDate(_checkOutDate)}'),
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
          if (!_isHourly) ...[
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Check in immediately'),
              subtitle: const Text(
                'Mark guest as checked in after booking',
              ),
              value: _checkInNow,
              onChanged: _busy ? null : (v) => setState(() => _checkInNow = v),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Payment',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _paymentMethod,
            decoration: _inputDecoration.copyWith(labelText: 'Payment method'),
            items: _paymentMethods
                .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                .toList(),
            onChanged: _busy
                ? null
                : (v) {
                    if (v != null) setState(() => _paymentMethod = v);
                  },
          ),
          if (validWindow && estimated > 0) ...[
            const SizedBox(height: 16),
            Card(
              color: scheme.primaryContainer.withValues(alpha: 0.35),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  _isHourly
                      ? 'Estimated total: ₱${estimated.toStringAsFixed(0)} · $stayHours hr(s)'
                      : 'Estimated total: ₱${estimated.toStringAsFixed(0)}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: scheme.primary,
                      ),
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
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Book guest'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
