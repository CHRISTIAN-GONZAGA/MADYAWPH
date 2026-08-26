import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';

import '../../dio_client.dart';

/// Hotel admin: breakfast serving clock. Kitchen sees guest pre-orders
/// two hours before this time.
class AdminBreakfastTimeScreen extends StatefulWidget {
  const AdminBreakfastTimeScreen({super.key});

  @override
  State<AdminBreakfastTimeScreen> createState() =>
      _AdminBreakfastTimeScreenState();
}

class _AdminBreakfastTimeScreenState extends State<AdminBreakfastTimeScreen> {
  TimeOfDay _time = const TimeOfDay(hour: 7, minute: 0);
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  TimeOfDay get _kitchenTime {
    final minutes = _time.hour * 60 + _time.minute - 120;
    final wrapped = (minutes % (24 * 60) + (24 * 60)) % (24 * 60);
    return TimeOfDay(hour: wrapped ~/ 60, minute: wrapped % 60);
  }

  String _hhmm(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await portalDio()
          .get<Map<String, dynamic>>('/admin/settings/breakfast-time');
      if (!mounted) return;
      final raw = (res.data?['breakfast_serving_time'] ?? '07:00').toString();
      final parts = raw.split(':');
      final hour = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 7;
      final minute = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
      setState(() {
        _time = TimeOfDay(
          hour: hour.clamp(0, 23),
          minute: minute.clamp(0, 59),
        );
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  Future<void> _pick() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
    );
    if (picked == null) return;
    setState(() => _time = picked);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await portalDio().patch<Map<String, dynamic>>(
        '/admin/settings/breakfast-time',
        data: {'breakfast_serving_time': _hhmm(_time)},
      );
      if (!mounted) return;
      setState(() => _saving = false);
      showAppMessage(
        context,
        'Breakfast is set for ${_time.format(context)}. '
        'Kitchen sees guest orders from ${_kitchenTime.format(context)}.',
      );
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final kitchen = _kitchenTime;

    return Scaffold(
      appBar: AppBar(title: const Text('Breakfast time')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Set when breakfast is served at this hotel. Guests can pick '
                  'their free breakfast as soon as they check in. Admin, front desk, '
                  'and super admin only see those orders 2 hours before this time.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Breakfast serving time'),
                  subtitle: Text(_time.format(context)),
                  trailing: FilledButton.tonal(
                    onPressed: _pick,
                    child: const Text('Change'),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  color: scheme.surfaceContainerHigh,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Kitchen window',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Orders appear on Amenities from ${kitchen.format(context)} '
                          '(2 hours before ${_time.format(context)}).',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving…' : 'Save breakfast time'),
                ),
              ],
            ),
    );
  }
}
