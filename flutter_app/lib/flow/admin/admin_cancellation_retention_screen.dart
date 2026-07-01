import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';

import '../../../dio_client.dart';

class AdminCancellationRetentionScreen extends StatefulWidget {
  const AdminCancellationRetentionScreen({super.key});

  @override
  State<AdminCancellationRetentionScreen> createState() =>
      _AdminCancellationRetentionScreenState();
}

class _AdminCancellationRetentionScreenState
    extends State<AdminCancellationRetentionScreen> {
  final _percentCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;

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
          .get<Map<String, dynamic>>('/admin/settings/cancellation-retention');
      if (!mounted) return;
      final percent =
          (res.data?['cancellation_retention_percent'] as num?)?.toDouble() ?? 0;
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
        '/admin/settings/cancellation-retention',
        data: {'cancellation_retention_percent': parsed},
      );
      if (!mounted) return;
      setState(() => _saving = false);
      showAppMessage(
        context,
        'Cancellation retention set to ${parsed.toStringAsFixed(parsed == parsed.roundToDouble() ? 0 : 1)}%.',
      );
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cancellation retention')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'When a paid booking is cancelled, revenue reports count only this percentage of the booking value. The remainder is treated as refunded to the guest.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _percentCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Retention percent',
                    suffixText: '%',
                    helperText: 'Example: 20 means the hotel keeps 20% on cancellations.',
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
