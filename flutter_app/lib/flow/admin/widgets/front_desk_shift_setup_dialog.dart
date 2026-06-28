import 'package:flutter/material.dart';

import 'front_desk_shift.dart';

/// Required on front-desk login: set scheduled time in and time out.
Future<FrontDeskShift?> showFrontDeskShiftSetupDialog({
  required BuildContext context,
  required String userId,
  required String hotelId,
  required String staffName,
}) async {
  final now = DateTime.now();
  var timeIn = DateTime(now.year, now.month, now.day, now.hour, now.minute);
  var timeOut = timeIn.add(const Duration(hours: 8));

  return showDialog<FrontDeskShift>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        Future<void> pickTimeIn() async {
          final date = await showDatePicker(
            context: ctx,
            firstDate: now.subtract(const Duration(days: 1)),
            lastDate: now.add(const Duration(days: 30)),
            initialDate: timeIn,
          );
          if (date == null || !ctx.mounted) return;
          final time = await showTimePicker(
            context: ctx,
            initialTime: TimeOfDay.fromDateTime(timeIn),
          );
          if (time == null) return;
          setLocal(() {
            timeIn = DateTime(
              date.year,
              date.month,
              date.day,
              time.hour,
              time.minute,
            );
            if (!timeOut.isAfter(timeIn)) {
              timeOut = timeIn.add(const Duration(hours: 1));
            }
          });
        }

        Future<void> pickTimeOut() async {
          final date = await showDatePicker(
            context: ctx,
            firstDate: timeIn,
            lastDate: timeIn.add(const Duration(days: 30)),
            initialDate: timeOut.isBefore(timeIn) ? timeIn : timeOut,
          );
          if (date == null || !ctx.mounted) return;
          final time = await showTimePicker(
            context: ctx,
            initialTime: TimeOfDay.fromDateTime(timeOut),
          );
          if (time == null) return;
          final picked = DateTime(
            date.year,
            date.month,
            date.day,
            time.hour,
            time.minute,
          );
          if (!picked.isAfter(timeIn)) {
            if (!ctx.mounted) return;
            ScaffoldMessenger.of(ctx).showSnackBar(
              const SnackBar(
                content: Text('Time out must be after time in.'),
              ),
            );
            return;
          }
          setLocal(() => timeOut = picked);
        }

        String fmt(DateTime d) =>
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
            '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

        return AlertDialog(
          title: const Text('Start your shift'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Set your time in and scheduled time out. You can only clock out after the time out you set.',
                  style: Theme.of(ctx).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Time in'),
                  subtitle: Text(fmt(timeIn)),
                  trailing: const Icon(Icons.login),
                  onTap: pickTimeIn,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Time out'),
                  subtitle: Text(fmt(timeOut)),
                  trailing: const Icon(Icons.logout),
                  onTap: pickTimeOut,
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () {
                final startedAt = DateTime.now();
                Navigator.pop(
                  ctx,
                  FrontDeskShift(
                    userId: userId,
                    hotelId: hotelId,
                    staffName: staffName,
                    scheduledTimeIn: timeIn,
                    scheduledTimeOut: timeOut,
                    startedAt: startedAt.isBefore(timeIn) ? timeIn : startedAt,
                  ),
                );
              },
              child: const Text('Start shift'),
            ),
          ],
        );
      },
    ),
  );
}
