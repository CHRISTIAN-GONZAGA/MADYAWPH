import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';

import '../../../dio_client.dart';

/// Hotel admin / super admin: % of stay total required for online app bookings.
class AdminOnlineBookingDepositScreen extends StatefulWidget {
  const AdminOnlineBookingDepositScreen({super.key});

  @override
  State<AdminOnlineBookingDepositScreen> createState() =>
      _AdminOnlineBookingDepositScreenState();
}

class _AdminOnlineBookingDepositScreenState
    extends State<AdminOnlineBookingDepositScreen> {
  final _percentCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  double? _platformDefault;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _percentCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await portalDio()
          .get<Map<String, dynamic>>('/admin/settings/online-booking-deposit');
      if (!mounted) return;
      final percent =
          (res.data?['online_booking_deposit_percent'] as num?)?.toDouble() ??
              50;
      _platformDefault =
          (res.data?['platform_default_percent'] as num?)?.toDouble();
      _percentCtrl.text = percent == percent.roundToDouble()
          ? '${percent.toInt()}'
          : percent.toStringAsFixed(1);
      setState(() => _loading = false);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  Future<void> _save() async {
    final parsed = double.tryParse(_percentCtrl.text.trim());
    if (parsed == null || parsed < 0 || parsed > 100) {
      showAppMessage(context, 'Enter a percentage from 0 to 100.', isError: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await portalDio().patch(
        '/admin/settings/online-booking-deposit',
        data: {'online_booking_deposit_percent': parsed},
      );
      if (!mounted) return;
      setState(() => _saving = false);
      showAppMessage(
        context,
        'Online booking deposit set to '
        '${parsed.toStringAsFixed(parsed == parsed.roundToDouble() ? 0 : 1)}%.',
      );
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final platformNote = _platformDefault == null
        ? ''
        : ' Fallback default is ${_platformDefault!.toStringAsFixed(_platformDefault == _platformDefault!.roundToDouble() ? 0 : 1)}% until you save a hotel value.';

    return Scaffold(
      appBar: AppBar(title: const Text('Online booking deposit %')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'When guests or members book this hotel online in the app, they must pay this percent of the stay total up front. '
                  'Example: 50 means half the bill; 100 means pay in full before the booking is submitted.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (platformNote.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    platformNote.trim(),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: _percentCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Required deposit percent',
                    suffixText: '%',
                    helperText: '0–100. Use 100 to require full payment online.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving…' : 'Save'),
                ),
              ],
            ),
    );
  }
}
