import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../dio_client.dart';
import '../../../utils/money_format.dart';
import '../../../widgets/app_scaffold.dart';

/// Blocks hotel portal access when subscription trial/payment is due.
Future<bool> ensureHotelSubscriptionAccess(BuildContext context) async {
  try {
    final res = await portalDio().get<Map<String, dynamic>>('/hotel/subscription');
    final data = res.data ?? const <String, dynamic>{};
    final status = (data['status'] ?? '').toString();
    if (status == 'trial' || status == 'active') {
      return true;
    }
    if (!context.mounted) return false;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => HotelSubscriptionGateScreen(initial: data),
      ),
    );
    return false;
  } on DioException catch (e) {
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(dioErrorMessage(e))),
    );
    return true;
  } catch (_) {
    return true;
  }
}

class HotelSubscriptionGateScreen extends StatefulWidget {
  const HotelSubscriptionGateScreen({super.key, required this.initial});

  final Map<String, dynamic> initial;

  @override
  State<HotelSubscriptionGateScreen> createState() =>
      _HotelSubscriptionGateScreenState();
}

class _HotelSubscriptionGateScreenState extends State<HotelSubscriptionGateScreen> {
  late Map<String, dynamic> _data;
  final _refCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _data = Map<String, dynamic>.from(widget.initial);
  }

  @override
  void dispose() {
    _refCtrl.dispose();
    super.dispose();
  }

  String get _status => (_data['status'] ?? '').toString();
  bool get _showPayUi => _data['show_payment_ui'] == true;
  bool get _canSubmit => _data['can_submit_payment'] == true;

  Future<void> _refresh() async {
    final res = await portalDio().get<Map<String, dynamic>>('/hotel/subscription');
    if (!mounted) return;
    final next = res.data ?? const <String, dynamic>{};
    final status = (next['status'] ?? '').toString();
    if (status == 'trial' || status == 'active') {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _data = Map<String, dynamic>.from(next));
  }

  Future<void> _submit() async {
    final ref = _refCtrl.text.trim();
    if (ref.isEmpty) {
      setState(() => _error = 'Enter the payment reference number.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await portalDio().post<Map<String, dynamic>>(
        '/hotel/subscription/payment',
        data: {'payment_reference': ref},
      );
      if (!mounted) return;
      setState(() {
        _data = Map<String, dynamic>.from(res.data ?? const {});
        _busy = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = dioErrorMessage(e);
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fee = parseJsonDouble(_data['subscription_fee']);
    final qr = (_data['subscription_qr_url'] ?? '').toString();

    // Non-dismissible processing screen for all roles.
    if (_status == 'processing') {
      return PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor: scheme.surface,
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 56,
                      height: 56,
                      child: CircularProgressIndicator(strokeWidth: 4),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Processing payment',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Central admin is reviewing your subscription payment. '
                      'This screen stays open until approval.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Check status'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      child: AppScaffold(
        appBar: AppBar(
          title: const Text('Payment required'),
          automaticallyImplyLeading: false,
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          children: [
            Icon(Icons.lock_outline, size: 48, color: scheme.error),
            const SizedBox(height: 12),
            Text(
              'Payment required',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              _showPayUi
                  ? 'Your free trial has ended. Pay via QR Ph and submit the reference number for central admin approval.'
                  : 'Your hotel subscription payment is required. Ask an admin or super admin to complete payment.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            if (_showPayUi) ...[
              const SizedBox(height: 20),
              Text(
                'Amount due: ${formatPeso(fee)}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 12),
              if (qr.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Image.network(
                      qr,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const ColoredBox(
                        color: Color(0xFFECEFF1),
                        child: Center(child: Text('QR unavailable')),
                      ),
                    ),
                  ),
                )
              else
                const Card(
                  child: ListTile(
                    title: Text('QR Ph not configured yet'),
                    subtitle: Text('Central admin must upload the subscription QR.'),
                  ),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: _refCtrl,
                decoration: const InputDecoration(
                  labelText: 'Payment reference number',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _canSubmit ? _submit() : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: scheme.error)),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy || !_canSubmit ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Submit for approval'),
              ),
            ],
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                HapticFeedback.selectionClick();
                SystemNavigator.pop();
              },
              child: const Text('Close app'),
            ),
          ],
        ),
      ),
    );
  }
}
