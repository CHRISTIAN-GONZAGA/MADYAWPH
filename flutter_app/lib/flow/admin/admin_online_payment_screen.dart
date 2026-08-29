import 'package:dio/dio.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';
import 'package:flutter/material.dart';
import '../../dio_client.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/chat_attachment.dart';
import '../../utils/money_format.dart';

/// Upload a payment QR per method (QR Ph, GCash, PayMaya, Maribank, bank
/// transfer) and verify payment references.
class AdminOnlinePaymentScreen extends StatefulWidget {
  const AdminOnlinePaymentScreen({super.key});

  @override
  State<AdminOnlinePaymentScreen> createState() =>
      _AdminOnlinePaymentScreenState();
}

class _AdminOnlinePaymentScreenState extends State<AdminOnlinePaymentScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  List<Map<String, dynamic>> _methods = const [];
  final Map<String, TextEditingController> _nameCtrls = {};
  final Map<String, TextEditingController> _numberCtrls = {};
  final Map<String, TextEditingController> _notesCtrls = {};
  bool _loadingQr = true;
  String? _busyMethod;
  final _refCtrl = TextEditingController();
  List<Map<String, dynamic>> _refResults = const [];
  bool _searching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadMethods();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _refCtrl.dispose();
    for (final ctrl in [
      ..._nameCtrls.values,
      ..._numberCtrls.values,
      ..._notesCtrls.values,
    ]) {
      ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _loadMethods() async {
    setState(() {
      _loadingQr = true;
      _error = null;
    });
    try {
      final res = await portalDio().get<Map<String, dynamic>>(
        '/admin/hotel/payment-methods',
      );
      if (!mounted) return;
      setState(() {
        _applyMethods(res.data?['methods']);
        _loadingQr = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = dioErrorMessage(e);
        _loadingQr = false;
      });
    }
  }

  void _applyMethods(dynamic raw) {
    final list = (raw as List?) ?? const [];
    _methods = list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    for (final method in _methods) {
      final key = (method['key'] ?? '').toString();
      if (key.isEmpty) continue;
      _controllerFor(_nameCtrls, key).text =
          (method['account_name'] ?? '').toString();
      _controllerFor(_numberCtrls, key).text =
          (method['account_number'] ?? '').toString();
      _controllerFor(_notesCtrls, key).text =
          (method['instructions'] ?? '').toString();
    }
  }

  TextEditingController _controllerFor(
    Map<String, TextEditingController> store,
    String key,
  ) =>
      store.putIfAbsent(key, TextEditingController.new);

  Future<void> _uploadMethodQr(String key, String label) async {
    final file = await ChatAttachment.pick(context);
    if (file == null) return;
    setState(() => _busyMethod = key);
    try {
      final form = await ChatAttachment.formWithImage(
        fields: const {},
        file: file,
        fileField: 'image_file',
      );
      final res = await portalDio().post<Map<String, dynamic>>(
        '/admin/hotel/payment-methods/$key/qr',
        data: form,
      );
      if (!mounted) return;
      setState(() => _applyMethods(res.data?['methods']));
      showAppMessage(context, '$label QR updated.');
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _busyMethod = null);
    }
  }

  Future<void> _removeMethodQr(String key, String label) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove $label QR?'),
        content: Text('Guests will no longer see $label as a payment option.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busyMethod = key);
    try {
      final res = await portalDio().delete<Map<String, dynamic>>(
        '/admin/hotel/payment-methods/$key/qr',
      );
      if (!mounted) return;
      setState(() => _applyMethods(res.data?['methods']));
      showAppMessage(context, '$label QR removed.');
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _busyMethod = null);
    }
  }

  Future<void> _saveMethodDetails(String key, String label) async {
    setState(() => _busyMethod = key);
    try {
      final res = await portalDio().patch<Map<String, dynamic>>(
        '/admin/hotel/payment-methods/$key',
        data: {
          'account_name': _controllerFor(_nameCtrls, key).text.trim(),
          'account_number': _controllerFor(_numberCtrls, key).text.trim(),
          'instructions': _controllerFor(_notesCtrls, key).text.trim(),
        },
      );
      if (!mounted) return;
      setState(() => _applyMethods(res.data?['methods']));
      showAppMessage(context, '$label details saved.');
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _busyMethod = null);
    }
  }

  Widget _methodCard(ColorScheme scheme, Map<String, dynamic> method) {
    final key = (method['key'] ?? '').toString();
    final label = (method['label'] ?? key).toString();
    final hint = (method['hint'] ?? '').toString();
    final qrUrl = (method['qr_url'] ?? '').toString();
    final hasQr = qrUrl.isNotEmpty;
    final busy = _busyMethod == key;
    final isBank = key == 'bank_transfer';

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      if (hint.isNotEmpty)
                        Text(
                          hint,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: method['configured'] == true
                        ? scheme.primaryContainer
                        : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    method['configured'] == true ? 'Live' : 'Not set',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: method['configured'] == true
                              ? scheme.onPrimaryContainer
                              : scheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (hasQr)
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: NetworkMediaImage(
                    url: qrUrl,
                    width: 190,
                    height: 190,
                    fit: BoxFit.contain,
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(vertical: 26),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Column(
                  children: [
                    Icon(Icons.qr_code_2, size: 46, color: scheme.outline),
                    const SizedBox(height: 8),
                    Text(
                      'No $label QR yet',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: busy ? null : () => _uploadMethodQr(key, label),
                    icon: const Icon(Icons.upload_outlined, size: 18),
                    label: Text(hasQr ? 'Replace QR' : 'Upload QR'),
                  ),
                ),
                if (hasQr) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Remove QR',
                    onPressed: busy ? null : () => _removeMethodQr(key, label),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controllerFor(_nameCtrls, key),
              decoration: InputDecoration(
                labelText: isBank ? 'Account name' : 'Account name (optional)',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _controllerFor(_numberCtrls, key),
              keyboardType:
                  isBank ? TextInputType.text : TextInputType.phone,
              decoration: InputDecoration(
                labelText: isBank ? 'Account number' : 'Mobile number',
                hintText: isBank ? '1234-5678-9012' : '09171234567',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _controllerFor(_notesCtrls, key),
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Note shown to guests (optional)',
                hintText: 'e.g. Use InstaPay, send the receipt to the front desk',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            AppPrimaryButton(
              label: busy ? 'Saving…' : 'Save $label details',
              onPressed: busy ? null : () => _saveMethodDetails(key, label),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _searchRefs() async {
    final q = _refCtrl.text.trim();
    if (q.length < 3) {
      showAppMessage(context, 'Enter at least 3 characters.');
      return;
    }
    setState(() => _searching = true);
    try {
      final res = await portalDio().get<Map<String, dynamic>>(
        '/admin/payment-references/search',
        queryParameters: {'q': q},
      );
      if (!mounted) return;
      final raw = res.data?['results'] as List<dynamic>? ?? const [];
      setState(() {
        _refResults = raw
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AppScaffold(
      appBar: AppBar(
        title: const Text('Online payments'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Payment QRs'),
            Tab(text: 'Verify payment'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Upload one QR per payment method. Guests booking a room see a button '
                'for every method you set up here and scan the matching code — nothing '
                'opens their wallet app automatically.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              Text(
                'Payment methods',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              if (_loadingQr)
                const Center(child: CircularProgressIndicator())
              else if (_error != null)
                Text(_error!, style: TextStyle(color: scheme.error))
              else
                for (final method in _methods) _methodCard(scheme, method),
            ],
          ),
          ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Search by payment reference (e.g. PAY20260530…) to confirm a guest completed an online transfer.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _refCtrl,
                decoration: InputDecoration(
                  labelText: 'Payment reference',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: _searching
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search),
                    onPressed: _searching ? null : _searchRefs,
                  ),
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _searchRefs(),
              ),
              const SizedBox(height: 16),
              ..._refResults.map((r) {
                final ref = (r['reference'] ?? '').toString();
                final guest = (r['guest_name'] ?? '').toString();
                final method = (r['payment_method'] ?? '').toString();
                final status = (r['payment_status'] ?? '').toString();
                final total = (r['total_amount'] as num?)?.toDouble() ?? 0;
                final type = (r['type'] ?? '').toString();

                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: Icon(
                      type == 'booking'
                          ? Icons.receipt_long
                          : Icons.pending_actions_outlined,
                    ),
                    title: Text(
                      ref,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      '$guest · $method · $status'
                      '${total > 0 ? ' · ${formatMoney(total, decimals: 0)}' : ''}',
                    ),
                    isThreeLine: true,
                  ),
                );
              }),
              if (_refResults.isEmpty &&
                  _refCtrl.text.length >= 3 &&
                  !_searching)
                const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Center(child: Text('No matching references found.')),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
