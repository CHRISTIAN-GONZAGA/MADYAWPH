import 'package:flutter/material.dart';

/// Simple month grid calendar with selectable day and event markers.
class AdminMonthCalendar extends StatefulWidget {
  const AdminMonthCalendar({
    super.key,
    required this.focusedMonth,
    required this.selectedDay,
    required this.onDaySelected,
    required this.hasEvent,
    this.onMonthChanged,
  });

  final DateTime focusedMonth;
  final DateTime selectedDay;
  final ValueChanged<DateTime> onDaySelected;
  final bool Function(DateTime day) hasEvent;
  final ValueChanged<DateTime>? onMonthChanged;

  @override
  State<AdminMonthCalendar> createState() => _AdminMonthCalendarState();
}

class _AdminMonthCalendarState extends State<AdminMonthCalendar> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    _month = DateTime(widget.focusedMonth.year, widget.focusedMonth.month);
  }

  @override
  void didUpdateWidget(AdminMonthCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _month = DateTime(widget.focusedMonth.year, widget.focusedMonth.month);
  }

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
    });
    widget.onMonthChanged?.call(_month);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final first = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateUtils.getDaysInMonth(_month.year, _month.month);
    final startWeekday = first.weekday % 7;
    final today = DateUtils.dateOnly(DateTime.now());

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _shiftMonth(-1),
                ),
                Expanded(
                  child: Text(
                    '${_month.year} · ${_monthName(_month.month)}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _shiftMonth(1),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: ['S', 'M', 'T', 'W', 'T', 'F', 'S']
                  .map(
                    (d) => Expanded(
                      child: Center(
                        child: Text(
                          d,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 6),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              itemCount: startWeekday + daysInMonth,
              itemBuilder: (context, i) {
                if (i < startWeekday) return const SizedBox.shrink();
                final day = i - startWeekday + 1;
                final date = DateTime(_month.year, _month.month, day);
                final selected = DateUtils.isSameDay(date, widget.selectedDay);
                final isToday = DateUtils.isSameDay(date, today);
                final marker = widget.hasEvent(date);

                return Material(
                  color: selected
                      ? scheme.primary
                      : isToday
                          ? scheme.primaryContainer.withValues(alpha: 0.5)
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => widget.onDaySelected(date),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$day',
                          style: TextStyle(
                            fontWeight:
                                selected || isToday ? FontWeight.w700 : null,
                            color: selected
                                ? scheme.onPrimary
                                : scheme.onSurface,
                          ),
                        ),
                        if (marker)
                          Container(
                            width: 5,
                            height: 5,
                            margin: const EdgeInsets.only(top: 2),
                            decoration: BoxDecoration(
                              color: selected
                                  ? scheme.onPrimary
                                  : scheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _monthName(int m) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return names[m - 1];
  }
}
