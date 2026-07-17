import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';

import '../../../dio_client.dart';

/// Hotel admin / super admin: late check-out grace period and fee amount.
class AdminLateCheckoutFeeScreen extends StatefulWidget {
  const AdminLateCheckoutFeeScreen({super.key});

  @override
  State<AdminLateCheckoutFeeScreen> createState() =>
      _AdminLateCheckoutFeeScreenState();
}

class _AdminLateCheckoutFeeScreenState
    extends State<AdminLateCheckoutFeeScreen> {
  final _graceCtrl = TextEditingController();
  final _feeCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  int? _platformGrace;
  double? _platformFee;

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
          .get<Map<String, dynamic>>('/admin/settings/late-checkout-fee');
      if (!mounted) return;
      final grace =
          (res.data?['late_checkout_grace_minutes'] as num?)?.toInt() ?? 15;
      final fee =
          (res.data?['late_checkout_fee_amount'] as num?)?.toDouble() ?? 500;
      _platformGrace =
          (res.data?['platform_default_grace_minutes'] as num?)?.toInt();
      _platformFee =
          (res.data?['platform_default_fee_amount'] as num?)?.toDouble();
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
        '/admin/settings/late-checkout-fee',
        data: {
          'late_checkout_grace_minutes': grace,
          'late_checkout_fee_amount': fee,
        },
      );
      if (!mounted) return;
      setState(() => _saving = false);
      showAppMessage(
        context,
        'Late check-out: $grace min grace · ₱${fee.toStringAsFixed(fee == fee.roundToDouble() ? 0 : 2)} fee.',
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
      appBar: AppBar(title: const Text('Late check-out fee')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'When a guest checks out after the scheduled time plus the grace period, the late check-out fee is added automatically. Example: scheduled 11:00 with 15 minutes grace → fee applies from 11:16 onward.',
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
                        'Minutes past scheduled check-out before the fee applies. Use 0 for no grace.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _feeCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Late check-out fee',
                    prefixText: '₱ ',
                    helperText: 'Fixed amount charged after grace. Use 0 to disable.',
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
