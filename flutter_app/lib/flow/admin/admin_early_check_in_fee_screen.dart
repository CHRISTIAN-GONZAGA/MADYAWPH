import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';

import '../../../dio_client.dart';

/// Hotel admin / super admin: early check-in grace period and fee amount.
class AdminEarlyCheckInFeeScreen extends StatefulWidget {
  const AdminEarlyCheckInFeeScreen({super.key});

  @override
  State<AdminEarlyCheckInFeeScreen> createState() =>
      _AdminEarlyCheckInFeeScreenState();
}

class _AdminEarlyCheckInFeeScreenState
    extends State<AdminEarlyCheckInFeeScreen> {
  final _graceCtrl = TextEditingController();
  final _feeCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  int? _platformGrace;
  double? _platformFee;
  String _standardTime = '15:00';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _graceCtrl.dispose();
    _feeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await portalDio()
          .get<Map<String, dynamic>>('/admin/settings/early-check-in-fee');
      if (!mounted) return;
      final grace =
          (res.data?['early_check_in_grace_minutes'] as num?)?.toInt() ?? 15;
      final fee =
          (res.data?['early_check_in_fee_amount'] as num?)?.toDouble() ?? 500;
      _platformGrace =
          (res.data?['platform_default_grace_minutes'] as num?)?.toInt();
      _platformFee =
          (res.data?['platform_default_fee_amount'] as num?)?.toDouble();
      _standardTime =
          (res.data?['standard_check_in_time'] ?? '15:00').toString();
      _graceCtrl.text = '$grace';
      _feeCtrl.text = fee == fee.roundToDouble()
          ? '${fee.toInt()}'
          : fee.toStringAsFixed(2);
      setState(() => _loading = false);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  Future<void> _save() async {
    final grace = int.tryParse(_graceCtrl.text.trim());
    final fee = double.tryParse(_feeCtrl.text.trim());
    if (grace == null || grace < 0 || grace > 720) {
      showAppMessage(
        context,
        'Enter grace minutes from 0 to 720.',
        isError: true,
      );
      return;
    }
    if (fee == null || fee < 0) {
      showAppMessage(context, 'Enter a fee amount of 0 or more.', isError: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await portalDio().patch(
        '/admin/settings/early-check-in-fee',
        data: {
          'early_check_in_grace_minutes': grace,
          'early_check_in_fee_amount': fee,
        },
      );
      if (!mounted) return;
      setState(() => _saving = false);
      showAppMessage(
        context,
        'Early check-in: $grace min grace · ₱${fee.toStringAsFixed(fee == fee.roundToDouble() ? 0 : 2)} fee.',
      );
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final platformNote = (_platformGrace == null && _platformFee == null)
        ? ''
        : ' Platform default: ${_platformGrace ?? 15} min grace, '
            '₱${(_platformFee ?? 500).toStringAsFixed((_platformFee ?? 500) == (_platformFee ?? 500).roundToDouble() ? 0 : 2)}.';

    return Scaffold(
      appBar: AppBar(title: const Text('Early check-in fee')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'For nightly rooms, standard check-in is $_standardTime. '
                  'When a guest arrives before that time minus the grace period, '
                  'the early check-in fee is added automatically. '
                  'Example: $_standardTime with 15 minutes grace → fee applies when arriving before '
                  '${_standardTime == '15:00' ? '2:45 PM' : 'the threshold'}. '
                  'Hourly rooms are not charged this fee. Set fee to 0 to disable.',
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
                  controller: _graceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Grace period',
                    suffixText: 'minutes',
                    helperText:
                        'Minutes before standard check-in that stay free. Use 0 for no grace.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _feeCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Early check-in fee',
                    prefixText: '₱ ',
                    helperText:
                        'Fixed amount charged when arriving too early. Use 0 to disable.',
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
