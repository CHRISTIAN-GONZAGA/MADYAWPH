import 'package:flutter/material.dart';

/// 30-minute time slots for check-in / check-out selection.
class AdminTimeSlotField extends StatelessWidget {
  const AdminTimeSlotField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final TimeOfDay? value;
  final ValueChanged<TimeOfDay?> onChanged;

  static List<TimeOfDay> get slots {
    final out = <TimeOfDay>[];
    for (var h = 0; h < 24; h++) {
      out.add(TimeOfDay(hour: h, minute: 0));
      out.add(TimeOfDay(hour: h, minute: 30));
    }
    return out;
  }

  /// Snap arbitrary clock time to the nearest 30-minute slot offered in [slots].
  static TimeOfDay snapToSlot(TimeOfDay time) {
    final total = time.hour * 60 + time.minute;
    final snapped = ((total + 15) ~/ 30) * 30;
    final clamped = snapped % (24 * 60);

    return TimeOfDay(hour: clamped ~/ 60, minute: clamped % 60);
  }

  static String format(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final p = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $p';
  }

  @override
  Widget build(BuildContext context) {
    final slot = value != null ? snapToSlot(value!) : null;
    final selected = slot != null
        ? '${slot.hour.toString().padLeft(2, '0')}:${slot.minute.toString().padLeft(2, '0')}'
        : null;

    return DropdownButtonFormField<String>(
      initialValue: selected,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.schedule),
      ),
      items: slots
          .map(
            (t) => DropdownMenuItem(
              value:
                  '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
              child: Text(format(t)),
            ),
          )
          .toList(),
      onChanged: (v) {
        if (v == null) {
          onChanged(null);
          return;
        }
        final parts = v.split(':');
        onChanged(TimeOfDay(
          hour: int.parse(parts[0]),
          minute: int.parse(parts[1]),
        ));
      },
    );
  }
}
