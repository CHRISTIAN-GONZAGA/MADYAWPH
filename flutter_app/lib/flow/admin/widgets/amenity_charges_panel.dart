import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';

import '../../../dio_client.dart';
import '../admin_dashboard_models.dart';

/// Lists recent amenity/manual charges with delete (admin) or request (front desk).
class AmenityChargesPanel extends StatefulWidget {
  const AmenityChargesPanel({
    super.key,
    required this.isFrontDesk,
    required this.onChanged,
  });

  final bool isFrontDesk;
  final Future<void> Function() onChanged;

  @override
  State<AmenityChargesPanel> createState() => _AmenityChargesPanelState();
}

class _AmenityChargesPanelState extends State<AmenityChargesPanel> {
  List<Map<String, dynamic>> _charges = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res =
          await portalDio().get<Map<String, dynamic>>('/admin/amenity-charges');
      if (!mounted) return;
      setState(() {
        _charges = (res.data?['data'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .toList() ??
            const [];
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = dioErrorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _deleteCharge(Map<String, dynamic> charge) async {
    final id = AdminDashboardModels.documentIdOf(charge);
    if (id.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove charge?'),
        content: Text(
          'Remove "${charge['label']}" (₱${charge['amount']}) from '
          'room ${charge['room_number']}?',
        ),
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
    if (confirmed != true || !mounted) return;

    try {
      await portalDio().delete('/billing/charges/$id');
      await _load();
      await widget.onChanged();
      if (!mounted) return;
      showAppMessage(context, 'Charge removed.');
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  Future<void> _requestDelete(Map<String, dynamic> charge) async {
    final id = AdminDashboardModels.documentIdOf(charge);
    if (id.isEmpty) return;

    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Request charge removal'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Admin must approve removing "${charge['label']}" '
              'from room ${charge['room_number']}.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send request'),
          ),
        ],
      ),
    );
    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    if (confirmed != true || !mounted) return;

    try {
      await portalDio().post(
        '/billing/charges/$id/delete-request',
        data: {
          if (reason.isNotEmpty) 'reason': reason,
        },
      );
      await _load();
      if (!mounted) return;
      showAppMessage(
        context,
        'Removal request sent to admin.',
        title: 'Request submitted',
      );
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_charges.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No amenity charges yet.'),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _charges.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final c = _charges[i];
          final pendingId = (c['pending_delete_request_id'] ?? '').toString();
          final amount = (c['amount'] as num?)?.toDouble() ?? 0;

          return Card(
            child: ListTile(
              title: Text((c['label'] ?? 'Charge').toString()),
              subtitle: Text(
                [
                  if ((c['room_number'] ?? '').toString().isNotEmpty)
                    'Room ${c['room_number']}',
                  if ((c['guest_name'] ?? '').toString().isNotEmpty)
                    c['guest_name'].toString(),
                  '₱${amount.toStringAsFixed(2)}',
                ].join(' · '),
              ),
              trailing: pendingId.isNotEmpty
                  ? const Chip(label: Text('Pending'))
                  : IconButton(
                      icon: Icon(
                        widget.isFrontDesk
                            ? Icons.send_outlined
                            : Icons.delete_outline,
                      ),
                      tooltip: widget.isFrontDesk
                          ? 'Request removal'
                          : 'Remove charge',
                      onPressed: () => widget.isFrontDesk
                          ? _requestDelete(c)
                          : _deleteCharge(c),
                    ),
            ),
          );
        },
      ),
    );
  }
}
