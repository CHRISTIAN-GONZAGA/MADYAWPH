import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../dio_client.dart';
import '../../../widgets/chat_attachment.dart';
import '../../../widgets/hotel_credits_policy.dart';

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
  Map<String, dynamic>? _scannedReseller;
  bool _loading = true;
  bool _busy = false;
  bool _scanning = false;

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _openingCreditsCtrl = TextEditingController(text: '0');
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
    _openingCreditsCtrl.dispose();
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(dioErrorMessage(e))));
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter reseller name.')),
      );
      return;
    }
    if (_idFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Upload a government-issued ID or license.')),
      );
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
          'opening_credits': double.tryParse(_openingCreditsCtrl.text.trim()) ?? 0,
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reseller "${created['name']}" added.')),
      );
      _nameCtrl.clear();
      _phoneCtrl.clear();
      _emailCtrl.clear();
      _openingCreditsCtrl.text = '0';
      setState(() => _idFile = null);
      await _load();
      await widget.onRefresh();
      if (created.isNotEmpty) {
        _showQrDialog(created);
      }
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(dioErrorMessage(e))));
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
                'Category: ${reseller['category']}\n'
                'Credits: ₱${reseller['current_credits']}',
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
    setState(() => _busy = true);
    try {
      final res = await portalDio().post<Map<String, dynamic>>(
        '/admin/resellers/lookup',
        data: {'code': code.trim()},
      );
      if (!mounted) return;
      setState(() {
        _scannedReseller = Map<String, dynamic>.from(res.data?['reseller'] as Map? ?? {});
        _scanning = false;
      });
      _tabs.animateTo(1);
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(dioErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _payCommission(Map<String, dynamic> reseller) async {
    if (_busy) return;
    if (!AdminCreditsGate.canPerformActions(context)) {
      AdminCreditsGate.showActionsBlockedMessage(context);
      return;
    }
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final id = (reseller['id'] ?? '').toString();
    final balance = (reseller['current_credits'] as num?)?.toDouble() ?? 0;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Pay commission — ${reseller['name']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Available reseller credits: ₱${balance.toStringAsFixed(2)}'),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Commission amount (PHP)',
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
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Pay')),
        ],
      ),
    );
    final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
    final note = noteCtrl.text.trim();
    amountCtrl.dispose();
    noteCtrl.dispose();
    if (ok != true || id.isEmpty) return;

    setState(() => _busy = true);
    try {
      await portalDio().post<Map<String, dynamic>>(
        '/admin/resellers/$id/commissions',
        data: {
          'amount': amount,
          'note': note,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Commission recorded and deducted from reseller credits.')),
      );
      setState(() => _scannedReseller = null);
      await _load();
      await widget.onRefresh();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(dioErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _topUpReseller(Map<String, dynamic> reseller) async {
    if (_busy) return;
    final amountCtrl = TextEditingController();
    final id = (reseller['id'] ?? '').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add credits — ${reseller['name']}'),
        content: TextField(
          controller: amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Amount (PHP)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
    amountCtrl.dispose();
    if (ok != true || id.isEmpty) return;

    setState(() => _busy = true);
    try {
      await portalDio().post('/admin/resellers/$id/credits', data: {
        'amount': amount,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reseller credits updated.')),
      );
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(dioErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
        TextField(
          controller: _openingCreditsCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Opening credit balance (PHP)',
            helperText: 'Commission payouts deduct from this balance.',
            border: OutlineInputBorder(),
          ),
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

    final scanned = _scannedReseller;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        FilledButton.icon(
          onPressed: _busy ? null : () => setState(() => _scanning = true),
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Scan reseller QR with camera'),
        ),
        const SizedBox(height: 16),
        if (scanned == null)
          Text(
            'Scan a reseller QR code to view their profile and pay a custom commission. '
            'The amount is deducted from that reseller\'s credit balance.',
            style: Theme.of(context).textTheme.bodySmall,
          )
        else ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    scanned['name']?.toString() ?? 'Reseller',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text('Category: ${scanned['category']}'),
                  Text('Phone: ${scanned['phone'] ?? '—'}'),
                  Text(
                    'Credits: ₱${(scanned['current_credits'] as num?)?.toStringAsFixed(2) ?? '0'}',
                  ),
                  Text(
                    'Total paid: ₱${(scanned['total_commissions_paid'] as num?)?.toStringAsFixed(2) ?? '0'}',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton(
                        onPressed: _busy ? null : () => _payCommission(scanned),
                        child: const Text('Pay commission'),
                      ),
                      OutlinedButton(
                        onPressed: _busy ? null : () => _topUpReseller(scanned),
                        child: const Text('Add credits'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
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
                    'Balance after: ₱${p['balance_after']}',
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
                          OutlinedButton.icon(
                            onPressed: _busy ? null : () => _topUpReseller(r),
                            icon: const Icon(Icons.add_card),
                            label: const Text('Add credits'),
                          ),
                          FilledButton.icon(
                            onPressed: _busy
                                ? null
                                : () {
                                    setState(() => _scannedReseller = r);
                                    _tabs.animateTo(1);
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
