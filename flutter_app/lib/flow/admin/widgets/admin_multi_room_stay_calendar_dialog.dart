import 'package:dio/dio.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';
import 'package:flutter/material.dart';

import '../../../dio_client.dart';
import '../../../widgets/admin_month_calendar.dart';
import '../admin_dashboard_models.dart';
import 'admin_walk_in_stay_calendar_dialog.dart';
import 'hourly_billing.dart';
import 'multi_room_booking_summary.dart';

/// Combined stay calendar for multiple rooms (blocks dates when any room is occupied).
Future<WalkInStayDates?> showMultiRoomWalkInStayCalendar({
  required BuildContext context,
  required List<Map<String, dynamic>> rooms,
}) {
  if (rooms.isEmpty) {
    return Future.value(null);
  }
  if (rooms.length == 1) {
    return showWalkInRoomStayCalendar(context: context, room: rooms.first);
  }

  for (final room in rooms) {
    if (AdminDashboardModels.roomIdOf(room).isEmpty) {
      showAppMessage(context, 'A selected room is missing an ID. Refresh and try again.');
      return Future.value(null);
    }
  }

  return showDialog<WalkInStayDates>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (dialogContext) => _MultiRoomStayCalendarDialog(rooms: rooms),
  );
}

class _MultiRoomStayCalendarDialog extends StatefulWidget {
  const _MultiRoomStayCalendarDialog({required this.rooms});

  final List<Map<String, dynamic>> rooms;

  @override
  State<_MultiRoomStayCalendarDialog> createState() =>
      _MultiRoomStayCalendarDialogState();
}

class _MultiRoomStayCalendarDialogState extends State<_MultiRoomStayCalendarDialog> {
  final Map<String, List<Map<String, dynamic>>> _staysByRoom = {};
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
    _hourly = widget.rooms.every(HourlyBilling.isHourly);
    _month = DateTime(_today.year, _today.month);
    _loadStays();
  }

  Future<void> _loadStays() async {
    try {
      final futures = widget.rooms.map((room) async {
        final roomId = AdminDashboardModels.roomIdOf(room);
        final res = await portalDio().get<Map<String, dynamic>>(
          '/admin/rooms/$roomId/stay-calendar',
        );
        final raw = res.data?['stays'];
        final stays = <Map<String, dynamic>>[];
        if (raw is List) {
          for (final item in raw) {
            if (item is Map) {
              stays.add(Map<String, dynamic>.from(item));
            }
          }
        }
        return MapEntry(roomId, stays);
      });
      final entries = await Future.wait(futures);
      if (!mounted) return;
      setState(() {
        _staysByRoom
          ..clear()
          ..addEntries(entries);
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

  bool _hasEvent(DateTime day) {
    for (final stays in _staysByRoom.values) {
      if (stays.any((s) => _stayOnDay(s, day))) return true;
    }
    return false;
  }

  int _eventCount(DateTime day) {
    var count = 0;
    for (final stays in _staysByRoom.values) {
      count += stays.where((s) => _stayOnDay(s, day)).length;
    }
    return count;
  }

  bool _rangeOverlapsStays(
    List<Map<String, dynamic>> stays,
    DateTime start,
    DateTime end,
  ) {
    final rangeStart = DateUtils.dateOnly(start);
    final rangeEnd = DateUtils.dateOnly(end);
    for (final stay in stays) {
      final inD = AdminDashboardModels.parseDate(
        (stay['check_in_date'] ?? '').toString(),
      );
      final outD = AdminDashboardModels.parseDate(
        (stay['check_out_date'] ?? '').toString(),
      );
      if (inD == null || outD == null) continue;
      final stayStart = DateUtils.dateOnly(inD);
      final stayEnd = DateUtils.dateOnly(outD);
      if (rangeStart == stayEnd && stayStart.isBefore(stayEnd)) {
        continue;
      }
      if (!rangeEnd.isBefore(stayStart) && !rangeStart.isAfter(stayEnd)) {
        return true;
      }
    }
    return false;
  }

  bool _rangeOverlapsAnyRoom(DateTime start, DateTime end) {
    for (final stays in _staysByRoom.values) {
      if (_rangeOverlapsStays(stays, start, end)) return true;
    }
    return false;
  }

  DateTime _defaultCheckOutFor(DateTime checkIn) {
    if (_hourly) return checkIn;
    return checkIn.add(const Duration(days: 1));
  }

  WalkInStayDates? _resolveSelection() {
    final checkIn = _checkIn;
    if (checkIn == null) return null;
    final checkOut = _checkOut ?? _defaultCheckOutFor(checkIn);
    if (_hourly) {
      if (checkOut.isBefore(checkIn)) return null;
    } else if (!checkOut.isAfter(checkIn)) {
      return null;
    }
    if (_rangeOverlapsAnyRoom(checkIn, checkOut)) return null;
    return WalkInStayDates(checkIn: checkIn, checkOut: checkOut);
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _onDaySelected(DateTime day) {
    if (day.isBefore(_today)) return;
    setState(() {
      if (_checkIn == null || _checkOut != null) {
        _checkIn = day;
        final autoOut = _defaultCheckOutFor(day);
        _checkOut = _rangeOverlapsAnyRoom(day, autoOut) ? null : autoOut;
        return;
      }
      if (day.isBefore(_checkIn!)) {
        _checkIn = day;
        final autoOut = _defaultCheckOutFor(day);
        _checkOut = _rangeOverlapsAnyRoom(day, autoOut) ? null : autoOut;
        return;
      }
      if (_hourly) {
        _checkOut = day;
      } else if (day.isAfter(_checkIn!)) {
        _checkOut = day;
      } else {
        _checkIn = day;
        final autoOut = _defaultCheckOutFor(day);
        _checkOut = _rangeOverlapsAnyRoom(day, autoOut) ? null : autoOut;
      }
    });
  }

  String get _roomLabel {
    final numbers = widget.rooms
        .map((r) => (r['room_number'] ?? '—').toString())
        .toList()
      ..sort();
    if (numbers.length <= 4) {
      return numbers.join(', ');
    }
    return '${numbers.take(3).join(', ')} +${numbers.length - 3} more';
  }

  @override
  Widget build(BuildContext context) {
    final selectedDay = _checkOut ?? _checkIn ?? _today;
    final selection = _resolveSelection();
    final previewCheckOut =
        _checkIn == null ? null : (_checkOut ?? _defaultCheckOutFor(_checkIn!));
    final rangeLabel = _checkIn == null
        ? 'Tap check-in date (1 night is selected automatically)'
        : previewCheckOut == null
            ? 'Check-in: ${_fmt(_checkIn!)} · choose check-out'
            : 'Stay: ${_fmt(_checkIn!)} → ${_fmt(previewCheckOut)}';

    final dialogWidth = MediaQuery.sizeOf(context).width.clamp(360.0, 520.0);

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
                '${widget.rooms.length} rooms · Select dates',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Rooms: $_roomLabel',
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
                            Text(
                              rangeLabel,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 12),
                            AdminMonthCalendar(
                              focusedMonth: _month,
                              selectedDay: selectedDay,
                              hasEvent: _hasEvent,
                              eventCount: _eventCount,
                              dayCellExtent: 48,
                              onMonthChanged: (m) => setState(() => _month = m),
                              onDaySelected: _onDaySelected,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Marked days are booked on at least one selected room. '
                              'Choose dates open for all ${widget.rooms.length} rooms.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (_checkIn != null &&
                                previewCheckOut != null &&
                                _rangeOverlapsAnyRoom(
                                    _checkIn!, previewCheckOut)) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Selected dates overlap a stay on one or more rooms.',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            if (_checkIn != null &&
                                previewCheckOut != null &&
                                !_rangeOverlapsAnyRoom(
                                    _checkIn!, previewCheckOut)) ...[
                              const SizedBox(height: 12),
                              MultiRoomBookingTotalSummary(
                                rooms: widget.rooms,
                                checkIn: _checkIn!,
                                checkOut: previewCheckOut,
                                compact: true,
                              ),
                            ],
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _loading || selection == null
                        ? null
                        : () => Navigator.of(context).pop(selection),
                    child: const Text('Continue'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Returns true when [start, end] overlaps any loaded stay list.
bool walkInRangeOverlapsStays(
  List<Map<String, dynamic>> stays,
  DateTime start,
  DateTime end,
) {
  final rangeStart = DateUtils.dateOnly(start);
  final rangeEnd = DateUtils.dateOnly(end);
  for (final stay in stays) {
    final inD = AdminDashboardModels.parseDate(
      (stay['check_in_date'] ?? '').toString(),
    );
    final outD = AdminDashboardModels.parseDate(
      (stay['check_out_date'] ?? '').toString(),
    );
    if (inD == null || outD == null) continue;
    final stayStart = DateUtils.dateOnly(inD);
    final stayEnd = DateUtils.dateOnly(outD);
    if (rangeStart == stayEnd && stayStart.isBefore(stayEnd)) continue;
    if (!rangeEnd.isBefore(stayStart) && !rangeStart.isAfter(stayEnd)) {
      return true;
    }
  }
  return false;
}

bool walkInRangeOverlapsAnyRoomStays(
  Map<String, List<Map<String, dynamic>>> staysByRoom,
  DateTime start,
  DateTime end,
) {
  for (final stays in staysByRoom.values) {
    if (walkInRangeOverlapsStays(stays, start, end)) return true;
  }
  return false;
}

Future<Map<String, List<Map<String, dynamic>>>> loadStayCalendarsForRooms(
  List<Map<String, dynamic>> rooms,
) async {
  final out = <String, List<Map<String, dynamic>>>{};
  await Future.wait(rooms.map((room) async {
    final roomId = AdminDashboardModels.roomIdOf(room);
    if (roomId.isEmpty) return;
    final res = await portalDio().get<Map<String, dynamic>>(
      '/admin/rooms/$roomId/stay-calendar',
    );
    final raw = res.data?['stays'];
    final stays = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) stays.add(Map<String, dynamic>.from(item));
      }
    }
    out[roomId] = stays;
  }));
  return out;
}
