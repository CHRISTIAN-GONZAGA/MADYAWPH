import 'package:dio/dio.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';
import 'package:flutter/material.dart';
import '../../dio_client.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/chat_attachment.dart';

/// Upload QR Ph for online guest payments and verify payment references.
class AdminOnlinePaymentScreen extends StatefulWidget {
  const AdminOnlinePaymentScreen({super.key});

  @override
  State<AdminOnlinePaymentScreen> createState() =>
      _AdminOnlinePaymentScreenState();
}

class _AdminOnlinePaymentScreenState extends State<AdminOnlinePaymentScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  String? _qrUrl;
  bool _loadingQr = true;
  bool _uploading = false;
  final _refCtrl = TextEditingController();
  List<Map<String, dynamic>> _refResults = const [];
  bool _searching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadQr();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _refCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadQr() async {
    setState(() {
      _loadingQr = true;
      _error = null;
    });
    try {
      final res = await portalDio().get<Map<String, dynamic>>(
        '/admin/hotel/payment-qr',
      );
      if (!mounted) return;
      setState(() {
        _qrUrl = (res.data?['qr_url'] ?? '').toString();
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

  Future<void> _uploadQr() async {
    final file = await ChatAttachment.pick(context);
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      final form = await ChatAttachment.formWithImage(
        fields: const {},
        file: file,
        fileField: 'image_file',
      );
      final res = await portalDio().post<Map<String, dynamic>>(
        '/admin/hotel/payment-qr',
        data: form,
      );
      if (!mounted) return;
      setState(() {
        _qrUrl = (res.data?['qr_url'] ?? '').toString();
      });
      showAppMessage(context, 'Payment QR updated.');
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
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
            Tab(text: 'QR Ph code'),
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
                'Guests who choose Online payment during booking will see this QR code to pay via GCash, Maya, or other QR Ph apps.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 20),
              if (_loadingQr)
                const Center(child: CircularProgressIndicator())
              else if (_error != null)
                Text(_error!, style: TextStyle(color: scheme.error))
              else if ((_qrUrl ?? '').isNotEmpty)
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: NetworkMediaImage(
                      url: _qrUrl!,
                      width: 260,
                      height: 260,
                      fit: BoxFit.contain,
                    ),
                  ),
                )
              else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(Icons.qr_code_2, size: 64, color: scheme.outline),
                        const SizedBox(height: 12),
                        const Text(
                          'No payment QR uploaded yet.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              AppPrimaryButton(
                label: _uploading ? 'Uploading…' : 'Upload / replace QR image',
                onPressed: _uploading ? null : _uploadQr,
              ),
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
                    title: Text(ref, style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(
                      '$guest · $method · $status'
                      '${total > 0 ? ' · ₱${total.toStringAsFixed(0)}' : ''}',
                    ),
                    isThreeLine: true,
                  ),
                );
              }),
              if (_refResults.isEmpty && _refCtrl.text.length >= 3 && !_searching)
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
