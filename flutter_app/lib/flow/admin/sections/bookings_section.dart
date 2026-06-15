import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../dio_client.dart';
import '../../../widgets/insufficient_hotel_credits.dart';
import '../../../widgets/admin_month_calendar.dart';
import '../../../widgets/admin_time_slot_field.dart';
import '../admin_dashboard_models.dart';
import '../../admin_rooms.dart';
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

  List<Map<String, dynamic>> get _bookedRooms => widget.rooms
      .where((r) => AdminDashboardModels.statusOf(r) == 'booked')
      .toList();

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

  /// Current and upcoming stays from dashboard booking records.
  List<Map<String, dynamic>> get _calendarBookings {
    final today = DateUtils.dateOnly(DateTime.now());
    return widget.bookings.where((b) {
      final status = (b['status'] ?? '').toString().toLowerCase();
      if (status == 'cancelled' || status == 'completed') {
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
  }

  bool _bookingActiveOnDay(Map<String, dynamic> b, DateTime day) {
    final checkIn = AdminDashboardModels.parseDate(
      (b['check_in_date'] ?? '').toString(),
    );
    final checkOut = AdminDashboardModels.parseDate(
      (b['check_out_date'] ?? '').toString(),
    );
    if (checkIn == null || checkOut == null) {
      return false;
    }
    final d = DateUtils.dateOnly(day);
    if (DateUtils.isSameDay(d, checkIn)) {
      return true;
    }
    return d.isAfter(checkIn) && d.isBefore(checkOut);
  }

  int _bookingCountOnDay(DateTime day) =>
      _calendarBookings.where((b) => _bookingActiveOnDay(b, day)).length;

  bool _hasCalendarEvent(DateTime day) => _bookingCountOnDay(day) > 0;

  List<Map<String, dynamic>> _eventsOnDay(DateTime day) {
    final out = <Map<String, dynamic>>[];
    for (final b in _calendarBookings) {
      if (_bookingActiveOnDay(b, day)) {
        out.add({
          'type': 'booking_record',
          'booking': b,
          'title':
              '${b['guest_name']} · Room ${b['room_number'] ?? '—'}',
          'subtitle':
              '${AdminDashboardModels.formatBookingDuration(b)} · ${b['status']}',
        });
      }
    }
    for (final res in _resList) {
      if (_onDay(day, res['check_in_date']?.toString()) ||
          _onDay(day, res['check_out_date']?.toString())) {
        out.add({
          'type': 'reservation',
          'title': '${res['guest_name']} · ${res['status']}',
          'subtitle':
              '${res['check_in_date']} → ${res['check_out_date']}',
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
            _detailRow('Check-in', '${b['check_in_date']}'),
            _detailRow('Check-out', '${b['check_out_date']}'),
            _detailRow('Nights', '${b['nights'] ?? '—'}'),
            _detailRow('Type', '${b['booking_type'] ?? 'local'}'),
            _detailRow('Status', '${b['status']} / ${b['payment_status'] ?? ''}'),
            _detailRow('Total', '₱${(b['total_amount'] as num?) ?? 0}'),
            _detailRow('Booked on', '${b['date_booked'] ?? b['created_at'] ?? '—'}'),
          ],
        ),
      ),
    );
  }

  Future<void> _approveReservation(String id) async {
    if (_busy || id.isEmpty) return;
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
    final roomId = (room['id'] ?? '').toString();
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
        subtitle: Text('$ref · ${(b['status'] ?? '').toString()}'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detailRow('Booking ID', ref),
                _detailRow('Type', type == 'online' ? 'Online' : 'Local'),
                _detailRow('Contact', '${b['guest_phone'] ?? ''} · ${b['guest_email'] ?? ''}'),
                _detailRow('Check-in', '${b['check_in_date'] ?? '—'}'),
                _detailRow('Check-out', '${b['check_out_date'] ?? '—'}'),
                _detailRow('Rooms', '${b['rooms_booked'] ?? 1}'),
                _detailRow('Room', roomLabel.isEmpty ? '—' : roomLabel),
                _detailRow('Status', '${b['status'] ?? ''} / ${b['payment_status'] ?? ''}'),
                _detailRow('Date booked', '${b['date_booked'] ?? b['created_at'] ?? '—'}'),
                _detailRow(
                  'Total',
                  '₱${((b['total_amount'] as num?) ?? 0).toStringAsFixed(0)}',
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
        Text('Check-in queue (booked)',
            style: Theme.of(context).textTheme.titleSmall),
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
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: const Icon(Icons.login),
        title: Text(
          'Room ${room['room_number']} · ${AdminDashboardModels.guestName(room)}',
        ),
        subtitle: Text(AdminDashboardModels.formatStayRange(room)),
        isThreeLine: true,
        trailing: FilledButton(
          onPressed: _busy ? null : () => _checkInRoom(room),
          child: const Text('Check in'),
        ),
        onTap: () {
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => AdminRoomDetailScreen(
                roomId: (room['id'] ?? '').toString(),
              ),
            ),
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
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text((r['guest_name'] ?? 'Guest').toString(),
                style: Theme.of(context).textTheme.titleSmall),
            Text('${r['check_in_date']} → ${r['check_out_date']}'),
            Text('Status: $status · ${r['guest_phone'] ?? ''}'),
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
    );
  }

  Widget _calendarView() {
    final events = _eventsOnDay(_selectedDay);
    final monthBookings = _calendarBookings.length;
    final bookedRooms = AdminDashboardModels.activeStayRoomCount(widget.rooms);
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
                        'Rooms currently booked/occupied: $bookedRooms',
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
                  }
                },
              ),
            );
          }),
      ],
    );
  }
}
