import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';

import '../../../dio_client.dart';

/// Hotel admin / super admin: minimum % of room balance required at check-in.
class AdminMinCheckInPaymentScreen extends StatefulWidget {
  const AdminMinCheckInPaymentScreen({super.key});

  @override
  State<AdminMinCheckInPaymentScreen> createState() =>
      _AdminMinCheckInPaymentScreenState();
}

class _AdminMinCheckInPaymentScreenState
    extends State<AdminMinCheckInPaymentScreen> {
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
          .get<Map<String, dynamic>>('/admin/settings/min-check-in-payment');
      if (!mounted) return;
      final percent =
          (res.data?['min_check_in_payment_percent'] as num?)?.toDouble() ?? 50;
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
        '/admin/settings/min-check-in-payment',
        data: {'min_check_in_payment_percent': parsed},
      );
      if (!mounted) return;
      setState(() => _saving = false);
      showAppMessage(
        context,
        'Check-in payment requirement set to '
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
        : ' Platform default is ${_platformDefault!.toStringAsFixed(_platformDefault == _platformDefault!.roundToDouble() ? 0 : 1)}%.';

    return Scaffold(
      appBar: AppBar(title: const Text('Check-in payment %')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'When front desk checks a guest in, they must collect at least this percent of the remaining room balance. Example: 50 means half (or more) of the bill must be paid before check-in completes. The amount is deducted from the room fees.',
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
                    labelText: 'Minimum percent at check-in',
                    suffixText: '%',
                    helperText: '0–100. Use 0 to allow check-in without a deposit.',
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
