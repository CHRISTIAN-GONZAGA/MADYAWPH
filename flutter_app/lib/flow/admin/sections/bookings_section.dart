import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../dio_client.dart';
import '../../../widgets/insufficient_hotel_credits.dart';
import '../../../widgets/admin_month_calendar.dart';
import '../../../widgets/admin_time_slot_field.dart';
import '../admin_dashboard_models.dart';
import '../widgets/admin_booking_manage_dialog.dart';
import '../widgets/admin_room_navigation.dart';
import '../../admin_chat.dart';

class BookingsSection extends StatefulWidget {
  const BookingsSection({
    super.key,
    required this.rooms,
    required this.reservations,
    required this.bookings,
    required this.bookingFilter,
    required this.onChanged,
    required this.currentCredits,
    required this.onTopUpCredits,
  });

  final List<Map<String, dynamic>> rooms;
  final List<dynamic> reservations;
  final List<Map<String, dynamic>> bookings;
  /// `all`, `local`, or `online`
  final String bookingFilter;
  final Future<void> Function() onChanged;
  final double currentCredits;
  final VoidCallback onTopUpCredits;

  @override
  State<BookingsSection> createState() => _BookingsSectionState();
}

class _BookingsSectionState extends State<BookingsSection>
    with SingleTickerProviderStateMixin {
  late final TabController _viewTabs;
  late String _recordFilter;
  final _searchCtrl = TextEditingController();
  DateTime _selectedDay = DateTime.now();
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _recordFilter = widget.bookingFilter;
    _viewTabs = TabController(length: 2, vsync: this);
  }

  @override
  void didUpdateWidget(covariant BookingsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookingFilter != widget.bookingFilter) {
      _recordFilter = widget.bookingFilter;
    }
  }

  List<Map<String, dynamic>> get _filteredBookings {
    final today = DateUtils.dateOnly(DateTime.now());
    var list = widget.bookings.where((b) {
      final status = (b['status'] ?? '').toString().toLowerCase();
      if (status == 'completed' || status == 'cancelled') {
        return false;
      }
      final checkOut = AdminDashboardModels.parseDate(
        (b['check_out_date'] ?? '').toString(),
      );
      if (checkOut != null && checkOut.isBefore(today)) {
        return false;
      }
      return true;
    }).toList();
    if (_recordFilter == 'local') {
      list = list
          .where((b) => (b['booking_type'] ?? 'local').toString() == 'local')
          .toList();
    } else if (_recordFilter == 'online') {
      list = list
          .where((b) => (b['booking_type'] ?? '').toString() == 'online')
          .toList();
    }
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list.where((b) {
      final hay = [
        b['guest_name'],
        b['guest_email'],
        b['guest_phone'],
        b['booking_reference'],
        b['room_number'],
      ].join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _viewTabs.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _resList =>
      widget.reservations.whereType<Map<String, dynamic>>().toList();

  List<Map<String, dynamic>> get _bookedRooms {
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];

    for (final booking in widget.bookings) {
      final status = (booking['status'] ?? '').toString().toLowerCase();
      if (status == 'completed' ||
          status == 'cancelled' ||
          status == 'checked_in') {
        continue;
      }
      if (status != 'booked' &&
          status != 'reserved' &&
          status != 'confirmed') {
        continue;
      }

      final roomId = AdminDashboardModels.normalizeRoomIdString(
        booking['room_id'],
      );
      if (roomId.isEmpty || seen.contains(roomId)) {
        continue;
      }

      Map<String, dynamic>? room;
      for (final r in widget.rooms) {
        if (AdminDashboardModels.normalizeRoomIdString(
              AdminDashboardModels.roomIdOf(r),
            ) ==
            roomId) {
          room = r;
          break;
        }
      }

      if (room != null && AdminDashboardModels.statusOf(room) == 'checked_in') {
        continue;
      }

      out.add(_queueRoomFromBooking(booking, room));
      seen.add(roomId);
    }

    for (final room in widget.rooms) {
      if (AdminDashboardModels.statusOf(room) != 'booked') {
        continue;
      }
      final roomId =
          AdminDashboardModels.normalizeRoomIdString(AdminDashboardModels.roomIdOf(room));
      if (roomId.isEmpty || seen.contains(roomId)) {
        continue;
      }
      out.add(room);
      seen.add(roomId);
    }

    out.sort((a, b) {
      final aIn = AdminDashboardModels.stayStartDate(a);
      final bIn = AdminDashboardModels.stayStartDate(b);
      if (aIn == null && bIn == null) return 0;
      if (aIn == null) return 1;
      if (bIn == null) return -1;
      return aIn.compareTo(bIn);
    });

    return out;
  }

  Map<String, dynamic> _queueRoomFromBooking(
    Map<String, dynamic> booking,
    Map<String, dynamic>? room,
  ) {
    return {
      if (room != null) ...room,
      'id': room != null
          ? AdminDashboardModels.roomIdOf(room)
          : AdminDashboardModels.normalizeRoomIdString(booking['room_id']),
      'room_number': booking['room_number'] ?? room?['room_number'],
      'category_name': booking['category_name'] ?? room?['category_name'],
      'current_guest_name': booking['guest_name'],
      'current_check_in': booking['check_in_date'],
      'current_check_out': booking['check_out_date'],
      'latest_booking': booking,
    };
  }

  bool _canCheckInToday(Map<String, dynamic> room) {
    final checkIn = AdminDashboardModels.stayStartDate(room);
    if (checkIn == null) return true;
    return !DateUtils.dateOnly(checkIn).isAfter(DateUtils.dateOnly(DateTime.now()));
  }

  List<Map<String, dynamic>> get _pendingReservations => _resList
      .where((r) => (r['status'] ?? '').toString() == 'pending_approval')
      .toList();

  List<Map<String, dynamic>> get _approvedReservations {
    final today = DateUtils.dateOnly(DateTime.now());
    return _resList.where((r) {
      final s = (r['status'] ?? '').toString();
      if (s != 'approved' && s != 'reserved') {
        return false;
      }
      final checkIn = AdminDashboardModels.parseDate(
        (r['check_in_date'] ?? '').toString(),
      );
      if (checkIn != null && !checkIn.isAfter(today)) {
        return false;
      }
      return true;
    }).toList();
  }

  String _resolveId(Map<String, dynamic> m) =>
      (m['id'] ?? m['_id'] ?? '').toString();

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool _onDay(DateTime day, String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return false;
    final d = AdminDashboardModels.parseDate(dateStr);
    if (d == null) return false;
    return d.year == day.year && d.month == day.month && d.day == day.day;
  }

  /// Current and upcoming stays for the calendar (booking records + room holds).
  List<Map<String, dynamic>> get _calendarStays {
    final today = DateUtils.dateOnly(DateTime.now());
    final seenRoomIds = <String>{};
    final out = <Map<String, dynamic>>[];

    for (final b in widget.bookings) {
      final status = (b['status'] ?? '').toString().toLowerCase();
      if (status == 'cancelled' || status == 'completed') {
        continue;
      }
      final checkOut = AdminDashboardModels.parseDate(
        (b['check_out_date'] ?? '').toString(),
      );
      if (checkOut != null && checkOut.isBefore(today)) {
        continue;
      }
      final roomId = (b['room_id'] ?? '').toString();
      if (roomId.isNotEmpty) {
        seenRoomIds.add(roomId);
      }
      out.add({...b, '_calendar_source': 'booking'});
    }

    for (final room in widget.rooms) {
      final roomId = AdminDashboardModels.roomIdOf(room);
      if (roomId.isEmpty || seenRoomIds.contains(roomId)) {
        continue;
      }
      final status = AdminDashboardModels.statusOf(room);
      if (!['booked', 'checked_in', 'reserved'].contains(status)) {
        continue;
      }
      final checkIn = AdminDashboardModels.stayStartDate(room);
      final checkOut = AdminDashboardModels.stayEndDate(room);
      if (checkIn == null || checkOut == null) {
        continue;
      }
      if (checkOut.isBefore(today)) {
        continue;
      }
      final booking = room['latest_booking'] as Map<String, dynamic>?;
      out.add({
        'id': booking?['id'] ?? roomId,
        'room_id': roomId,
        'guest_name': AdminDashboardModels.guestName(room),
        'room_number': room['room_number'],
        'category_name': room['category_name'],
        'check_in_date': _fmt(checkIn),
        'check_out_date': _fmt(checkOut),
        'status': status,
        'booking_type': 'local',
        '_calendar_source': 'room',
        '_room': room,
      });
    }

    return out;
  }

  bool _stayActiveOnDay(Map<String, dynamic> entry, DateTime day) {
    final checkIn = AdminDashboardModels.parseDate(
      (entry['check_in_date'] ?? '').toString(),
    );
    final checkOut = AdminDashboardModels.parseDate(
      (entry['check_out_date'] ?? '').toString(),
    );
    if (checkIn == null || checkOut == null) {
      return false;
    }
    final d = DateUtils.dateOnly(day);
    final start = DateUtils.dateOnly(checkIn);
    final end = DateUtils.dateOnly(checkOut);

    return !d.isBefore(start) && !d.isAfter(end);
  }

  int _bookingCountOnDay(DateTime day) =>
      _calendarStays.where((b) => _stayActiveOnDay(b, day)).length;

  bool _hasCalendarEvent(DateTime day) => _bookingCountOnDay(day) > 0;

  List<Map<String, dynamic>> _eventsOnDay(DateTime day) {
    final out = <Map<String, dynamic>>[];
    for (final b in _calendarStays) {
      if (_stayActiveOnDay(b, day)) {
        out.add({
          'type': 'booking_record',
          'booking': b,
          'title':
              '${b['guest_name']} · Room ${b['room_number'] ?? '—'}',
          'subtitle':
              '${AdminDashboardModels.formatBookingDuration(b)} · ${_bookingStatusLabel(b)}',
        });
      }
    }
    for (final res in _resList) {
      if (_onDay(day, res['check_in_date']?.toString()) ||
          _onDay(day, res['check_out_date']?.toString())) {
        out.add({
          'type': 'reservation',
          'title': '${res['guest_name']} · ${_reservationStatusLabel((res['status'] ?? '').toString())}',
          'subtitle':
              AdminDashboardModels.formatDateRange(
                res['check_in_date'],
                res['check_out_date'],
              ),
          'reservation': res,
        });
      }
    }
    return out;
  }

  void _showBookingDetails(Map<String, dynamic> b) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Booking ${b['booking_reference'] ?? b['id']}',
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _detailRow('Guest', '${b['guest_name']}'),
            _detailRow('Phone', '${b['guest_phone'] ?? '—'}'),
            _detailRow('Email', '${b['guest_email'] ?? '—'}'),
            _detailRow('Room', '${b['room_number']} · ${b['room_display_name'] ?? ''}'),
            _detailRow('Category', '${b['category_name'] ?? '—'}'),
            _detailRow('Check-in', AdminDashboardModels.formatDisplayDate(b['check_in_date'])),
            _detailRow('Check-out', AdminDashboardModels.formatDisplayDate(b['check_out_date'])),
            _detailRow(
              'Nights',
              ((b['nights'] as num?)?.toInt() ?? 0) > 0
                  ? '${b['nights']}'
                  : '—',
            ),
            _detailRow('Type', '${b['booking_type'] ?? 'local'}'),
            _detailRow('Status', '${_bookingStatusLabel(b)} / ${b['payment_status'] ?? ''}'),
            _detailRow('Total', '₱${(b['total_amount'] as num?) ?? 0}'),
            _detailRow('Booked on', '${b['date_booked'] ?? b['created_at'] ?? '—'}'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                final ok = await showAdminManageBookingDialog(
                  context: context,
                  booking: b,
                );
                if (ok && mounted) await widget.onChanged();
              },
              icon: const Icon(Icons.edit_calendar_outlined),
              label: const Text('Edit dates / cancel'),
            ),
          ],
        ),
      ),
    );
  }

  void _showReservationDetails(Map<String, dynamic> r) {
    final id = _resolveId(r);
    final status = (r['status'] ?? '').toString();
    final pending = status == 'pending_approval' || status == 'pending';

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Reservation ${r['external_reference'] ?? id}',
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _detailRow('Guest', '${r['guest_name']}'),
            _detailRow('Phone', '${r['guest_phone'] ?? '—'}'),
            _detailRow('Email', '${r['guest_email'] ?? '—'}'),
            _detailRow(
              'Check-in',
              AdminDashboardModels.formatDisplayDate(r['check_in_date']),
            ),
            _detailRow(
              'Check-out',
              AdminDashboardModels.formatDisplayDate(r['check_out_date']),
            ),
            _detailRow('Status', _reservationStatusLabel(status)),
            _detailRow('Total', '₱${(r['total_amount'] as num?) ?? 0}'),
            const SizedBox(height: 12),
            if (pending) ...[
              FilledButton(
                onPressed: _busy
                    ? null
                    : () {
                        Navigator.pop(ctx);
                        _approveReservation(id);
                      },
                child: const Text('Approve'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () {
                        Navigator.pop(ctx);
                        _rejectReservation(id);
                      },
                child: const Text('Reject'),
              ),
            ] else
              FilledButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final ok = await showAdminManageReservationDialog(
                    context: context,
                    reservation: r,
                  );
                  if (ok && mounted) await widget.onChanged();
                },
                icon: const Icon(Icons.edit_calendar_outlined),
                label: const Text('Edit dates / cancel'),
              ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmAction(String title, String message) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Go back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _approveReservation(String id) async {
    if (_busy || id.isEmpty) return;
    if (!await _confirmAction(
      'Approve reservation?',
      'This holds or activates the stay and may deduct platform credits from your hotel wallet.',
    )) {
      return;
    }
    if (!mounted) return;
    if (!await guardHotelCreditsBeforeApproval(
      context,
      currentCredits: widget.currentCredits,
      onTopUp: widget.onTopUpCredits,
    )) {
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await portalDio()
          .post<Map<String, dynamic>>('/admin/reservations/$id/approve');
      if (!mounted) return;
      final activated = res.data?['activated'] == true;
      final wallet = res.data?['wallet'] as Map<String, dynamic>?;
      final fee = (wallet?['fee'] as num?)?.toDouble() ?? 0;
      final roomTotal = (wallet?['room_total'] as num?)?.toDouble();
      final feePercent = (wallet?['fee_percent'] as num?)?.toDouble() ?? 8;
      final balance = (wallet?['balance_after'] as num?)?.toDouble();
      var msg = activated
          ? 'Reservation approved and converted to booking.'
          : 'Reservation approved. Will activate on check-in date.';
      if (fee > 0) {
        msg += ' ${feePercent.toStringAsFixed(0)}% platform fee'
            ' (₱${fee.toStringAsFixed(2)}'
            '${roomTotal != null ? ' of ₱${roomTotal.toStringAsFixed(2)} booking total' : ''})'
            ' deducted from hotel credits'
            '${balance != null ? '. Balance: ₱${balance.toStringAsFixed(2)}' : ''}.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
      await widget.onChanged();
    } on DioException catch (e) {
      if (!mounted) return;
      if (isHotelCreditsApprovalError(e)) {
        await handleHotelCreditsApprovalError(
          context,
          e,
          onTopUp: widget.onTopUpCredits,
        );
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(dioErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rejectReservation(String id) async {
    if (_busy || id.isEmpty) return;
    if (!await _confirmAction(
      'Reject reservation?',
      'The guest will be notified that this request was declined.',
    )) {
      return;
    }
    setState(() => _busy = true);
    try {
      await portalDio().post('/admin/reservations/$id/reject');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reservation rejected.')),
      );
      await widget.onChanged();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(dioErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkInRoom(Map<String, dynamic> room) async {
    final roomId = AdminDashboardModels.roomIdOf(room);
    if (roomId.isEmpty) return;

    final inDate = AdminDashboardModels.stayStartDate(room) ?? DateTime.now();
    final outDate = AdminDashboardModels.stayEndDate(room) ??
        inDate.add(const Duration(days: 1));
    var checkInDate = inDate;
    var checkOutDate = outDate;
    TimeOfDay? checkInTime =
        AdminDashboardModels.bookingTimeOfDay(room, 'check_in_time') ??
            const TimeOfDay(hour: 15, minute: 0);
    TimeOfDay? checkOutTime =
        AdminDashboardModels.bookingTimeOfDay(room, 'check_out_time') ??
            const TimeOfDay(hour: 11, minute: 0);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Check in — Room ${room['room_number']}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AdminDashboardModels.guestName(room),
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Check-in date'),
                  subtitle: Text(_fmt(checkInDate)),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      firstDate: DateTime.now().subtract(const Duration(days: 7)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      initialDate: checkInDate,
                    );
                    if (picked != null) setLocal(() => checkInDate = picked);
                  },
                ),
                AdminTimeSlotField(
                  label: 'Check-in time',
                  value: checkInTime,
                  onChanged: (t) => setLocal(() => checkInTime = t),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Check-out date'),
                  subtitle: Text(_fmt(checkOutDate)),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      firstDate: checkInDate,
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      initialDate: checkOutDate,
                    );
                    if (picked != null) setLocal(() => checkOutDate = picked);
                  },
                ),
                AdminTimeSlotField(
                  label: 'Check-out time',
                  value: checkOutTime,
                  onChanged: (t) => setLocal(() => checkOutTime = t),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Check in guest'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final inTime = checkInTime ?? const TimeOfDay(hour: 15, minute: 0);
    final outTime = checkOutTime ?? const TimeOfDay(hour: 11, minute: 0);

    final checkInAt = DateTime(
      checkInDate.year,
      checkInDate.month,
      checkInDate.day,
      inTime.hour,
      inTime.minute,
    );
    final checkOutAt = DateTime(
      checkOutDate.year,
      checkOutDate.month,
      checkOutDate.day,
      outTime.hour,
      outTime.minute,
    );

    setState(() => _busy = true);
    try {
      await portalDio().patch(
        '/admin/rooms/$roomId/status',
        data: {
          'status': 'checked_in',
          'check_in_at': checkInAt.toIso8601String(),
          'check_out_at': checkOutAt.toIso8601String(),
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Guest checked in.')),
      );
      await widget.onChanged();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(dioErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _bookingStatusLabel(Map<String, dynamic> b) {
    return AdminDashboardModels.bookingRecordStatusLabel(
      b,
      room: AdminDashboardModels.roomForBooking(b, widget.rooms),
    );
  }

  String _reservationStatusLabel(String status) =>
      AdminDashboardModels.reservationStatusLabel(status);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _viewTabs,
          tabs: const [
            Tab(text: 'List', icon: Icon(Icons.list_alt)),
            Tab(text: 'Calendar', icon: Icon(Icons.calendar_month)),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _viewTabs,
            children: [
              _listView(),
              _calendarView(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bookingTypeChips() {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'all', label: Text('All')),
        ButtonSegment(value: 'local', label: Text('Local')),
        ButtonSegment(value: 'online', label: Text('Online')),
      ],
      selected: {_recordFilter},
      onSelectionChanged: (s) => setState(() => _recordFilter = s.first),
    );
  }

  Widget _bookingRecordCard(Map<String, dynamic> b) {
    final ref = (b['booking_reference'] ?? b['id'] ?? '').toString();
    final type = (b['booking_type'] ?? 'local').toString();
    final roomLabel = [
      if ((b['room_number'] ?? '').toString().isNotEmpty)
        'Room ${b['room_number']}',
      if ((b['category_name'] ?? '').toString().isNotEmpty)
        b['category_name'],
      if ((b['room_display_name'] ?? '').toString().isNotEmpty)
        b['room_display_name'],
    ].where((s) => s.toString().isNotEmpty).join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: Icon(
          type == 'online' ? Icons.language : Icons.smartphone,
          color: type == 'online'
              ? Theme.of(context).colorScheme.tertiary
              : Theme.of(context).colorScheme.primary,
        ),
        title: Text((b['guest_name'] ?? 'Guest').toString()),
        subtitle: Text('$ref · ${_bookingStatusLabel(b)}'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detailRow('Booking ID', ref),
                _detailRow('Type', type == 'online' ? 'Online' : 'Local'),
                _detailRow('Contact', '${b['guest_phone'] ?? ''} · ${b['guest_email'] ?? ''}'),
                _detailRow(
                  'Check-in',
                  AdminDashboardModels.formatDisplayDate(b['check_in_date']),
                ),
                _detailRow(
                  'Check-out',
                  AdminDashboardModels.formatDisplayDate(b['check_out_date']),
                ),
                _detailRow('Rooms', '${b['rooms_booked'] ?? 1}'),
                _detailRow('Room', roomLabel.isEmpty ? '—' : roomLabel),
                _detailRow('Status', '${_bookingStatusLabel(b)} / ${b['payment_status'] ?? ''}'),
                _detailRow('Date booked', '${b['date_booked'] ?? b['created_at'] ?? '—'}'),
                _detailRow(
                  'Total',
                  '₱${((b['total_amount'] as num?) ?? 0).toStringAsFixed(0)}',
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          final ok = await showAdminManageBookingDialog(
                            context: context,
                            booking: b,
                          );
                          if (ok && mounted) await widget.onChanged();
                        },
                  icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                  label: const Text('Edit dates / cancel'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _listView() {
    final records = _filteredBookings;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        Text(
          'Bookings & reservations',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Customer portal bookings appear as booked rooms. Approve reservations to hold or activate stays.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 14),
        _bookingTypeChips(),
        const SizedBox(height: 10),
        TextField(
          controller: _searchCtrl,
          decoration: const InputDecoration(
            labelText: 'Search bookings',
            prefixIcon: Icon(Icons.search),
            isDense: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        Text(
          'Booking records (${records.length})',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        if (records.isEmpty)
          const Text('No bookings match this filter.')
        else
          ...records.map(_bookingRecordCard),
        const SizedBox(height: 20),
        Text('Check-in queue',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'Rooms marked booked or reserved — tap Check in when the guest arrives.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (_bookedRooms.isEmpty)
          const Text('No rooms awaiting check-in.')
        else
          ..._bookedRooms.map((r) => _bookingCard(r)),
        const SizedBox(height: 20),
        Text('Reservation requests',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        if (_pendingReservations.isEmpty)
          const Text('No pending reservation requests.')
        else
          ..._pendingReservations.map((r) => _reservationCard(r, pending: true)),
        const SizedBox(height: 16),
        Text('Approved reservations',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        if (_approvedReservations.isEmpty)
          const Text('No approved holds waiting for check-in date.')
        else
          ..._approvedReservations.map((r) => _reservationCard(r, pending: false)),
      ],
    );
  }

  Widget _bookingCard(Map<String, dynamic> room) {
    final canCheckIn = _canCheckInToday(room);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: const Icon(Icons.login),
        title: Text(
          'Room ${room['room_number']} · ${AdminDashboardModels.guestName(room)}',
        ),
        subtitle: Text(AdminDashboardModels.formatStayRange(room)),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Edit booking',
              onPressed: _busy
                  ? null
                  : () async {
                      final booking =
                          room['latest_booking'] as Map<String, dynamic>?;
                      if (booking == null) return;
                      final ok = await showAdminManageBookingDialog(
                        context: context,
                        booking: booking,
                      );
                      if (ok && mounted) await widget.onChanged();
                    },
              icon: const Icon(Icons.edit_calendar_outlined),
            ),
            FilledButton(
              onPressed: _busy || !canCheckIn ? null : () => _checkInRoom(room),
              child: Text(canCheckIn ? 'Check in' : 'Awaiting'),
            ),
          ],
        ),
        onTap: () {
          AdminRoomNavigation.openDetailById(
            AdminDashboardModels.roomIdOf(room),
            snackContext: context,
          );
        },
      ),
    );
  }

  Widget _reservationCard(Map<String, dynamic> r, {required bool pending}) {
    final id = _resolveId(r);
    final status = (r['status'] ?? '').toString();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => _showReservationDetails(r),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text((r['guest_name'] ?? 'Guest').toString(),
                  style: Theme.of(context).textTheme.titleSmall),
              Text(
                AdminDashboardModels.formatDateRange(
                  r['check_in_date'],
                  r['check_out_date'],
                ),
              ),
              Text('Status: ${_reservationStatusLabel(status)} · ${r['guest_phone'] ?? ''}'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  if (pending) ...[
                    FilledButton(
                      onPressed: _busy ? null : () => _approveReservation(id),
                      child: const Text('Approve'),
                    ),
                    OutlinedButton(
                      onPressed: _busy ? null : () => _rejectReservation(id),
                      child: const Text('Reject'),
                    ),
                  ],
                  if (!pending)
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () async {
                              final ok = await showAdminManageReservationDialog(
                                context: context,
                                reservation: r,
                              );
                              if (ok && mounted) await widget.onChanged();
                            },
                      icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                      label: const Text('Edit dates / cancel'),
                    ),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => const AdminChatHubScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.message_outlined, size: 18),
                    label: const Text('Message'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _calendarView() {
    final events = _eventsOnDay(_selectedDay);
    final monthBookings = _calendarStays.length;
    final awaitingCheckIn = AdminDashboardModels.bookedRoomCount(widget.rooms);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Active bookings: $monthBookings',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      Text(
                        'Rooms awaiting check-in: $awaitingCheckIn',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.event_seat_outlined),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        AdminMonthCalendar(
          focusedMonth: _month,
          selectedDay: _selectedDay,
          hasEvent: _hasCalendarEvent,
          eventCount: _bookingCountOnDay,
          onDaySelected: (d) => setState(() => _selectedDay = d),
          onMonthChanged: (m) => setState(() => _month = m),
        ),
        const SizedBox(height: 12),
        Text(
          '${_bookingCountOnDay(_selectedDay)} booking(s) on ${_fmt(_selectedDay)}',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        if (events.isEmpty)
          const Text('No current or upcoming bookings on this day.')
        else
          ...events.map((e) {
            final isRecord = e['type'] == 'booking_record';
            return Card(
              child: ListTile(
                leading: Icon(
                  isRecord ? Icons.hotel : Icons.event_available,
                ),
                title: Text(e['title'].toString()),
                subtitle: Text(e['subtitle'].toString()),
                onTap: () {
                  if (isRecord) {
                    _showBookingDetails(
                      e['booking'] as Map<String, dynamic>,
                    );
                  } else {
                    _showReservationDetails(
                      e['reservation'] as Map<String, dynamic>,
                    );
                  }
                },
              ),
            );
          }),
      ],
    );
  }
}
