import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../dio_client.dart';
import '../../../widgets/admin_month_calendar.dart';
import '../admin_dashboard_models.dart';
import 'hourly_billing.dart';

class WalkInStayDates {
  const WalkInStayDates({
    required this.checkIn,
    required this.checkOut,
  });

  final DateTime checkIn;
  final DateTime checkOut;
}

/// Room calendar shown before guest details in admin walk-in booking.
Future<WalkInStayDates?> showWalkInRoomStayCalendar({
  required BuildContext context,
  required Map<String, dynamic> room,
  List<Map<String, dynamic>>? prefetchedStays,
}) {
  final roomId = AdminDashboardModels.roomIdOf(room);
  if (roomId.isEmpty && prefetchedStays == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Room ID missing. Refresh and try again.')),
    );
    return Future.value(null);
  }

  return showDialog<WalkInStayDates>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _WalkInStayCalendarDialog(
      room: room,
      roomId: roomId,
      prefetchedStays: prefetchedStays,
    ),
  );
}

class _WalkInStayCalendarDialog extends StatefulWidget {
  const _WalkInStayCalendarDialog({
    required this.room,
    required this.roomId,
    this.prefetchedStays,
  });

  final Map<String, dynamic> room;
  final String roomId;
  final List<Map<String, dynamic>>? prefetchedStays;

  @override
  State<_WalkInStayCalendarDialog> createState() =>
      _WalkInStayCalendarDialogState();
}

class _WalkInStayCalendarDialogState extends State<_WalkInStayCalendarDialog> {
  List<Map<String, dynamic>> _stays = const [];
  var _loading = true;
  String? _error;
  late final DateTime _today;
  late final bool _hourly;
  late DateTime _month;
  DateTime? _checkIn;
  DateTime? _checkOut;

  @override
  void initState() {
    super.initState();
    _today = DateUtils.dateOnly(DateTime.now());
    _hourly = HourlyBilling.isHourly(widget.room);
    _month = DateTime(_today.year, _today.month);
    if (widget.prefetchedStays != null) {
      _stays = widget.prefetchedStays!;
      _loading = false;
    } else {
      _loadStays();
    }
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

  bool _rangeOverlapsStay(DateTime start, DateTime end) {
    final rangeStart = DateUtils.dateOnly(start);
    final rangeEnd = DateUtils.dateOnly(end);
    for (final stay in _stays) {
      final inD = AdminDashboardModels.parseDate(
        (stay['check_in_date'] ?? '').toString(),
      );
      final outD = AdminDashboardModels.parseDate(
        (stay['check_out_date'] ?? '').toString(),
      );
      if (inD == null || outD == null) continue;
      final stayStart = DateUtils.dateOnly(inD);
      final stayEnd = DateUtils.dateOnly(outD);
      if (!rangeEnd.isBefore(stayStart) && !rangeStart.isAfter(stayEnd)) {
        return true;
      }
    }
    return false;
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _onDaySelected(DateTime day) {
    if (day.isBefore(_today)) return;
    setState(() {
      if (_checkIn == null || _checkOut != null) {
        _checkIn = day;
        _checkOut = null;
        return;
      }
      if (day.isBefore(_checkIn!)) {
        _checkIn = day;
        _checkOut = null;
        return;
      }
      if (_hourly) {
        _checkOut = day;
      } else if (day.isAfter(_checkIn!)) {
        _checkOut = day;
      } else {
        _checkIn = day;
        _checkOut = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedDay = _checkOut ?? _checkIn ?? _today;
    final rangeLabel = _checkIn == null
        ? 'Tap check-in date'
        : _checkOut == null
            ? 'Check-in: ${_fmt(_checkIn!)} · tap check-out'
            : 'Stay: ${_fmt(_checkIn!)} → ${_fmt(_checkOut!)}';

    final rangeValid = _checkIn != null &&
        _checkOut != null &&
        (_hourly
            ? !_checkOut!.isBefore(_checkIn!)
            : _checkOut!.isAfter(_checkIn!)) &&
        !_rangeOverlapsStay(_checkIn!, _checkOut!);

    final eventsForDay =
        _stays.where((s) => _stayOnDay(s, selectedDay)).toList();
    final errorMessage = _error;

    return AlertDialog(
      title: Text('Room ${widget.room['room_number'] ?? '—'} · Select dates'),
      content: SizedBox(
        width: 360,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (errorMessage != null) ...[
                      Text(
                        errorMessage,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Text(
                      rangeLabel,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 8),
                    AdminMonthCalendar(
                      focusedMonth: _month,
                      selectedDay: selectedDay,
                      hasEvent: _hasEvent,
                      eventCount: _eventCount,
                      onMonthChanged: (m) => setState(() => _month = m),
                      onDaySelected: _onDaySelected,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Booked / reserved days are marked. Select open dates for the new stay.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (_checkIn != null &&
                        _checkOut != null &&
                        _rangeOverlapsStay(_checkIn!, _checkOut!)) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Selected dates overlap an existing stay.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (eventsForDay.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        'On ${_fmt(selectedDay)}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      ...eventsForDay.map((stay) {
                        final type = (stay['type'] ?? 'stay').toString();
                        final guest =
                            (stay['guest_name'] ?? 'Guest').toString();
                        final range = AdminDashboardModels.formatDateRange(
                          stay['check_in_date'],
                          stay['check_out_date'],
                        );
                        final label = switch (type) {
                          'reservation' => 'Reservation',
                          'room_hold' => 'Room hold',
                          _ => 'Booking',
                        };
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '$label · $guest · $range',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _loading || !rangeValid
              ? null
              : () {
                  Navigator.of(context).pop(
                    WalkInStayDates(
                      checkIn: _checkIn!,
                      checkOut: _checkOut!,
                    ),
                  );
                },
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
