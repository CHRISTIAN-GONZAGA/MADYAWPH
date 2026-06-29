import 'package:dio/dio.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../dio_client.dart';
import '../../../widgets/chat_attachment.dart';
import '../../../widgets/hotel_credits_policy.dart';
import '../../../widgets/insufficient_hotel_credits.dart';

/// Reseller onboarding, QR codes, scan-to-pay commission, and payment history.
class ResellersSection extends StatefulWidget {
  const ResellersSection({
    super.key,
    required this.onRefresh,
  });

  final Future<void> Function() onRefresh;

  @override
  State<ResellersSection> createState() => _ResellersSectionState();
}

class _ResellersSectionState extends State<ResellersSection>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  List<Map<String, dynamic>> _resellers = [];
  List<Map<String, dynamic>> _payments = [];
  Map<String, dynamic>? _paymentSummary;
  bool _loading = true;
  bool _busy = false;
  bool _scanning = false;

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  String _category = 'taxi';
  XFile? _idFile;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        portalDio().get<Map<String, dynamic>>('/admin/resellers'),
        portalDio().get<Map<String, dynamic>>('/admin/resellers/payments'),
      ]);
      if (!mounted) return;
      final list = (results[0].data?['data'] as List?) ?? const [];
      final payData = results[1].data ?? {};
      setState(() {
        _resellers = list.whereType<Map>().map(Map<String, dynamic>.from).toList();
        _payments =
            ((payData['data'] as List?) ?? const []).whereType<Map>().map(Map<String, dynamic>.from).toList();
        _paymentSummary = payData['summary'] as Map<String, dynamic>?;
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  Future<void> _createReseller() async {
    if (_busy) return;
    if (!AdminCreditsGate.canPerformActions(context)) {
      AdminCreditsGate.showActionsBlockedMessage(context);
      return;
    }
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      showAppMessage(context, 'Enter reseller name.');
      return;
    }
    if (_idFile == null) {
      showAppMessage(context, 'Upload a government-issued ID or license.');
      return;
    }

    setState(() => _busy = true);
    try {
      final form = await ChatAttachment.formWithImage(
        fields: {
          'name': name,
          'phone': _phoneCtrl.text.trim(),
          'email': _emailCtrl.text.trim(),
          'category': _category,
        },
        file: _idFile!,
        fileField: 'id_file',
      );
      final res = await portalDio().post<Map<String, dynamic>>(
        '/admin/resellers',
        data: form,
        options: Options(
          contentType: 'multipart/form-data',
          headers: {Headers.acceptHeader: 'application/json'},
        ),
      );
      if (!mounted) return;
      final created = Map<String, dynamic>.from(res.data?['reseller'] as Map? ?? {});
      showAppMessage(context, 'Reseller "${created['name']}" added.');
      _nameCtrl.clear();
      _phoneCtrl.clear();
      _emailCtrl.clear();
      setState(() => _idFile = null);
      await _load();
      await widget.onRefresh();
      if (created.isNotEmpty) {
        _showQrDialog(created);
      }
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showQrDialog(Map<String, dynamic> reseller) {
    final payload = (reseller['qr_payload'] ?? '').toString();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('QR — ${reseller['name']}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (payload.isNotEmpty)
                QrImageView(
                  data: payload,
                  version: QrVersions.auto,
                  size: 220,
                  backgroundColor: Colors.white,
                ),
              const SizedBox(height: 12),
              Text(
                'Category: ${reseller['category']}',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _lookupCode(String code) async {
    if (_busy || code.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _scanning = false;
    });
    try {
      final res = await portalDio().post<Map<String, dynamic>>(
        '/admin/resellers/lookup',
        data: {'code': code.trim()},
      );
      if (!mounted) return;
      final reseller =
          Map<String, dynamic>.from(res.data?['reseller'] as Map? ?? {});
      final wallet =
          Map<String, dynamic>.from(res.data?['hotel_wallet'] as Map? ?? {});
      final hotelBalance =
          (wallet['current_credits'] as num?)?.toDouble() ?? 0;
      await _showCommissionDialog(reseller, hotelBalance);
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showCommissionDialog(
    Map<String, dynamic> reseller,
    double hotelBalance,
  ) async {
    if (!mounted) return;

    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final id = (reseller['id'] ?? '').toString();
    final idUrl = (reseller['id_document_url'] ?? '').toString();

    final paid = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(reseller['name']?.toString() ?? 'Reseller'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _infoRow('Category', '${reseller['category']}'),
              _infoRow('Phone', '${reseller['phone'] ?? '—'}'),
              if ((reseller['email'] ?? '').toString().isNotEmpty)
                _infoRow('Email', '${reseller['email']}'),
              _infoRow(
                'Total commissions paid',
                '₱${(reseller['total_commissions_paid'] as num?)?.toStringAsFixed(2) ?? '0'}',
              ),
              if (idUrl.isNotEmpty) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    ChatAttachment.resolveMediaUrl(idUrl),
                    height: 100,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Record how much the hotel paid this partner in cash or bank transfer. '
                'This is tracked in activity logs and reports — not deducted from your credits wallet.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Commission amount (PHP) *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Record payment'),
          ),
        ],
      ),
    );

    final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
    final note = noteCtrl.text.trim();
    amountCtrl.dispose();
    noteCtrl.dispose();

    if (paid != true || id.isEmpty || amount <= 0) return;

    setState(() => _busy = true);
    try {
      await portalDio().post<Map<String, dynamic>>(
        '/admin/resellers/$id/commissions',
        data: {'amount': amount, 'note': note},
      );
      if (!mounted) return;
      showAppMessage(
        context,
        'Partner commission ₱${amount.toStringAsFixed(2)} recorded for reports.',
      );
      await _load();
      await widget.onRefresh();
    } on DioException catch (e) {
      if (!mounted) return;
      if (isHotelCreditsApprovalError(e)) {
        await handleHotelCreditsApprovalError(context, e);
      } else {
        showAppMessage(context, dioErrorMessage(e), isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodyMedium,
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            'Resellers',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Add'),
            Tab(text: 'Scan & pay'),
            Tab(text: 'Payments'),
            Tab(text: 'Directory'),
          ],
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _buildAddTab(scheme),
                    _buildScanTab(scheme),
                    _buildPaymentsTab(scheme),
                    _buildDirectoryTab(scheme),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildAddTab(ColorScheme scheme) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        Text(
          'Register a reseller (taxi, motorcycle, or individual). Upload government ID or license.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Full name *',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Phone',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Email',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _category,
          decoration: const InputDecoration(
            labelText: 'Category *',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'taxi', child: Text('Taxi')),
            DropdownMenuItem(value: 'motorcycle', child: Text('Motorcycle')),
            DropdownMenuItem(value: 'individual', child: Text('Individual')),
          ],
          onChanged: _busy ? null : (v) => setState(() => _category = v ?? 'taxi'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () async {
                  final file = await ChatAttachment.pickRoomImageFromGallery(context);
                  if (file != null) setState(() => _idFile = file);
                },
          icon: const Icon(Icons.badge_outlined),
          label: Text(_idFile == null ? 'Upload ID / license *' : 'ID selected: ${_idFile!.name}'),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _createReseller,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.person_add_alt_1),
          label: const Text('Add reseller & generate QR'),
        ),
      ],
    );
  }

  Widget _buildScanTab(ColorScheme scheme) {
    if (_scanning) {
      return Column(
        children: [
          Expanded(
            child: MobileScanner(
              onDetect: (capture) {
                for (final code in capture.barcodes) {
                  final raw = code.rawValue;
                  if (raw != null && raw.isNotEmpty) {
                    _lookupCode(raw);
                    break;
                  }
                }
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: OutlinedButton(
              onPressed: () => setState(() => _scanning = false),
              child: const Text('Cancel scan'),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        FilledButton.icon(
          onPressed: _busy ? null : () => setState(() => _scanning = true),
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Scan reseller QR with camera'),
        ),
        const SizedBox(height: 16),
        Text(
          'After scanning, you will see the reseller\'s details and can enter a commission amount. '
          'The commission is deducted from your hotel wallet credits.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildPaymentsTab(ColorScheme scheme) {
    final total = (_paymentSummary?['total_commissions_paid'] as num?)?.toDouble() ?? 0;
    final count = (_paymentSummary?['count'] as num?)?.toInt() ?? _payments.length;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          Card(
            color: scheme.primaryContainer.withValues(alpha: 0.4),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Reseller payments (last 30 days)',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Text(
                    '$count payment(s) · Total commissions ₱${total.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Included in Reports & analytics under reseller commissions.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_payments.isEmpty)
            const Text('No reseller commission payments in this period.')
          else
            ..._payments.map((p) {
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(Icons.payments_outlined, color: scheme.primary),
                  title: Text('${p['reseller_name']} · ₱${p['amount']}'),
                  subtitle: Text(
                    '${p['reseller_category']} · ${p['created_at']}\n'
                    '${p['note'] ?? ''}\n'
                    'Hotel balance after: ₱${p['hotel_balance_after'] ?? p['balance_after']}',
                  ),
                  isThreeLine: true,
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildDirectoryTab(ColorScheme scheme) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          if (_resellers.isEmpty)
            const Text('No resellers yet. Use the Add tab to register one.')
          else
            ..._resellers.map((r) {
              final idUrl = (r['id_document_url'] ?? '').toString();
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ExpansionTile(
                  leading: CircleAvatar(
                    child: Icon(_categoryIcon(r['category']?.toString())),
                  ),
                  title: Text(r['name']?.toString() ?? 'Reseller'),
                  subtitle: Text(
                    '${r['category']} · Credits ₱${r['current_credits']}',
                  ),
                  children: [
                    if (idUrl.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Image.network(
                          ChatAttachment.resolveMediaUrl(idUrl),
                          height: 120,
                          fit: BoxFit.cover,
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _showQrDialog(r),
                            icon: const Icon(Icons.qr_code),
                            label: const Text('Show QR'),
                          ),
                          FilledButton.icon(
                            onPressed: _busy
                                ? null
                                : () {
                                    final payload =
                                        (r['qr_payload'] ?? '').toString();
                                    if (payload.isNotEmpty) {
                                      _lookupCode(payload);
                                    }
                                  },
                            icon: const Icon(Icons.paid_outlined),
                            label: const Text('Pay commission'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  IconData _categoryIcon(String? cat) {
    switch (cat) {
      case 'taxi':
        return Icons.local_taxi_outlined;
      case 'motorcycle':
        return Icons.two_wheeler_outlined;
      default:
        return Icons.person_outline;
    }
  }
}
