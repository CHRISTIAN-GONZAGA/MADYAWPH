import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';

import '../../../dio_client.dart';
import '../../../widgets/admin_month_calendar.dart';
import '../admin_dashboard_models.dart';

/// Read-only calendar of bookings/reservations for one room.
Future<void> showRoomBookingCalendar({
  required BuildContext context,
  required Map<String, dynamic> room,
}) {
  final roomId = AdminDashboardModels.roomIdOf(room);
  if (roomId.isEmpty) {
    showAppMessage(context, 'Room ID missing. Refresh and try again.');
    return Future.value();
  }

  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _RoomBookingCalendarDialog(
      room: room,
      roomId: roomId,
    ),
  );
}

class _RoomBookingCalendarDialog extends StatefulWidget {
  const _RoomBookingCalendarDialog({
    required this.room,
    required this.roomId,
  });

  final Map<String, dynamic> room;
  final String roomId;

  @override
  State<_RoomBookingCalendarDialog> createState() =>
      _RoomBookingCalendarDialogState();
}

class _RoomBookingCalendarDialogState extends State<_RoomBookingCalendarDialog> {
  List<Map<String, dynamic>> _stays = const [];
  var _loading = true;
  String? _error;
  late DateTime _month;
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    final today = DateUtils.dateOnly(DateTime.now());
    _month = DateTime(today.year, today.month);
    _selectedDay = today;
    _loadStays();
  }

  Future<void> _loadStays() async {
    try {
      final res = await portalDio().get<Map<String, dynamic>>(
        '/admin/rooms/${widget.roomId}/stay-calendar',
      );
      final raw = res.data?['stays'];
      if (!mounted) return;
      setState(() {
        if (raw is List) {
          _stays = raw
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList();
        }
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = dioErrorMessage(e);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  bool _stayOnDay(Map<String, dynamic> stay, DateTime day) {
    final inD = AdminDashboardModels.parseDate(
      (stay['check_in_date'] ?? '').toString(),
    );
    final outD = AdminDashboardModels.parseDate(
      (stay['check_out_date'] ?? '').toString(),
    );
    if (inD == null || outD == null) return false;
    final d = DateUtils.dateOnly(day);
    final start = DateUtils.dateOnly(inD);
    final end = DateUtils.dateOnly(outD);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  bool _hasEvent(DateTime day) => _stays.any((s) => _stayOnDay(s, day));

  int _eventCount(DateTime day) =>
      _stays.where((s) => _stayOnDay(s, day)).length;

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final eventsForDay =
        _stays.where((s) => _stayOnDay(s, _selectedDay)).toList();
    final dialogWidth = MediaQuery.sizeOf(context).width.clamp(360.0, 520.0);
    final roomNo = (widget.room['room_number'] ?? '—').toString();

    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: dialogWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Room $roomNo · Booking calendar',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Marked days have a booking or reservation. Tap a day for details.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: _loading
                      ? const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_error != null) ...[
                              Text(
                                _error!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                            AdminMonthCalendar(
                              focusedMonth: _month,
                              selectedDay: _selectedDay,
                              hasEvent: _hasEvent,
                              eventCount: _eventCount,
                              dayCellExtent: 48,
                              onMonthChanged: (m) => setState(() => _month = m),
                              onDaySelected: (day) =>
                                  setState(() => _selectedDay = day),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'On ${_fmt(_selectedDay)}',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 6),
                            if (eventsForDay.isEmpty)
                              Text(
                                'No booking on this day.',
                                style: Theme.of(context).textTheme.bodySmall,
                              )
                            else
                              ...eventsForDay.map((stay) {
                                final type = (stay['type'] ?? 'stay').toString();
                                final guest =
                                    (stay['guest_name'] ?? 'Guest').toString();
                                final status =
                                    (stay['status'] ?? '').toString();
                                final range =
                                    AdminDashboardModels.formatDateRange(
                                  stay['check_in_date'],
                                  stay['check_out_date'],
                                );
                                final label = switch (type) {
                                  'reservation' => 'Reservation',
                                  'room_hold' => 'Room hold',
                                  _ => 'Booking',
                                };
                                final statusSuffix =
                                    status.isEmpty ? '' : ' · $status';
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Text(
                                    '$label · $guest · $range$statusSuffix',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                );
                              }),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
