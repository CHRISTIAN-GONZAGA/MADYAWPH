import 'dart:async';

import 'package:flutter/material.dart';
/// Full date + live time for admin dashboard header.
class AdminLiveClock extends StatefulWidget {
  const AdminLiveClock({
    super.key,
    this.textStyle,
    this.align = TextAlign.end,
    this.compact = false,
  });

  final TextStyle? textStyle;
  final TextAlign align;
  /// Shorter date line for tight header rows.
  final bool compact;

  @override
  State<AdminLiveClock> createState() => _AdminLiveClockState();
}

class _AdminLiveClockState extends State<AdminLiveClock> {
  Timer? _timer;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final date = widget.compact ? _formatDateCompact(_now) : _formatDate(_now);
    final time = _formatTime(_now);
    final style = widget.textStyle ??
        Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: widget.compact ? 11 : null,
            );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: widget.align == TextAlign.end
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          date,
          style: style,
          textAlign: widget.align,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          time,
          style: (widget.compact
                  ? Theme.of(context).textTheme.titleSmall
                  : Theme.of(context).textTheme.titleMedium)
              ?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
          textAlign: widget.align,
        ),
      ],
    );
  }

  static String _formatDateCompact(DateTime dt) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${days[dt.weekday - 1]}, ${months[dt.month - 1]} ${dt.day}';
  }

  static String _formatDate(DateTime dt) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${days[dt.weekday - 1]}, ${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  static String _formatTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    final ap = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m:$s $ap';
  }
}
