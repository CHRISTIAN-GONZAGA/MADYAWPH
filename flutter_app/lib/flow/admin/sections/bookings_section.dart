import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../dio_client.dart';
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
    required this.onChanged,
  });

  final List<Map<String, dynamic>> rooms;
  final List<dynamic> reservations;
  final Future<void> Function() onChanged;

  @override
  State<BookingsSection> createState() => _BookingsSectionState();
}

class _BookingsSectionState extends State<BookingsSection>
    with SingleTickerProviderStateMixin {
  late final TabController _viewTabs;
  DateTime _selectedDay = DateTime.now();
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _viewTabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
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

  List<Map<String, dynamic>> get _approvedReservations => _resList
      .where((r) {
        final s = (r['status'] ?? '').toString();
        return s == 'approved' || s == 'reserved';
      })
      .toList();

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

  bool _hasCalendarEvent(DateTime day) {
    for (final r in _bookedRooms) {
      if (_onDay(day, (r['current_check_in'] ?? '').toString()) ||
          _onDay(day, (r['current_check_out'] ?? '').toString())) {
        return true;
      }
    }
    for (final res in _resList) {
      if (_onDay(day, res['check_in_date']?.toString()) ||
          _onDay(day, res['check_out_date']?.toString())) {
        return true;
      }
    }
    return false;
  }

  List<Map<String, dynamic>> _eventsOnDay(DateTime day) {
    final out = <Map<String, dynamic>>[];
    for (final r in _bookedRooms) {
      if (_onDay(day, (r['current_check_in'] ?? '').toString()) ||
          _onDay(day, (r['current_check_out'] ?? '').toString())) {
        out.add({
          'type': 'booking',
          'title': 'Room ${r['room_number']} · ${AdminDashboardModels.guestName(r)}',
          'subtitle': AdminDashboardModels.formatStayRange(r),
          'room': r,
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

  Future<void> _approveReservation(String id) async {
    if (_busy || id.isEmpty) return;
    setState(() => _busy = true);
    try {
      final res = await portalDio()
          .post<Map<String, dynamic>>('/admin/reservations/$id/approve');
      if (!mounted) return;
      final activated = res.data?['activated'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            activated
                ? 'Reservation approved and converted to booking.'
                : 'Reservation approved. Will activate on check-in date.',
          ),
        ),
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
    TimeOfDay? checkInTime = const TimeOfDay(hour: 15, minute: 0);
    TimeOfDay? checkOutTime = const TimeOfDay(hour: 11, minute: 0);

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

  Widget _listView() {
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
        const SizedBox(height: 16),
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
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        AdminMonthCalendar(
          focusedMonth: _month,
          selectedDay: _selectedDay,
          hasEvent: _hasCalendarEvent,
          onDaySelected: (d) => setState(() => _selectedDay = d),
          onMonthChanged: (m) => setState(() => _month = m),
        ),
        const SizedBox(height: 12),
        Text(
          'Events on ${_fmt(_selectedDay)}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        if (events.isEmpty)
          const Text('No bookings or reservations on this day.')
        else
          ...events.map((e) {
            final isBooking = e['type'] == 'booking';
            return Card(
              child: ListTile(
                leading: Icon(
                  isBooking ? Icons.hotel : Icons.event_available,
                ),
                title: Text(e['title'].toString()),
                subtitle: Text(e['subtitle'].toString()),
                onTap: () {
                  if (isBooking) {
                    final room = e['room'] as Map<String, dynamic>;
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => AdminRoomDetailScreen(
                          roomId: (room['id'] ?? '').toString(),
                        ),
                      ),
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
