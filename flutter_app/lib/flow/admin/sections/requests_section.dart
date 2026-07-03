import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';

import '../../../dio_client.dart';
import '../admin_dashboard_models.dart';

/// Admin hub for front desk requests (charge removals, date changes).
class RequestsSection extends StatefulWidget {
  const RequestsSection({
    super.key,
    required this.onChanged,
  });

  final Future<void> Function() onChanged;

  @override
  State<RequestsSection> createState() => _RequestsSectionState();
}

class _RequestsSectionState extends State<RequestsSection> {
  List<Map<String, dynamic>> _items = const [];
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
          await portalDio().get<Map<String, dynamic>>('/admin/approval-hub');
      if (!mounted) return;
      setState(() {
        _items = (res.data?['items'] as List?)
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

  Future<void> _approve(Map<String, dynamic> item) async {
    final kind = (item['kind'] ?? '').toString();
    try {
      switch (kind) {
        case 'charge_deletion':
          final requestId = (item['staff_request_id'] ?? '').toString();
          if (requestId.isEmpty) return;
          await portalDio().post('/admin/staff-requests/$requestId/approve');
          break;
        case 'booking_date_change':
          final bookingId = (item['booking_id'] ?? '').toString();
          if (bookingId.isEmpty) return;
          await portalDio()
              .post('/admin/bookings/$bookingId/date-change/approve');
          break;
        case 'reservation_date_change':
          final reservationId = (item['reservation_id'] ?? '').toString();
          if (reservationId.isEmpty) return;
          await portalDio().post(
            '/admin/reservations/$reservationId/date-change/approve',
          );
          break;
      }
      await _load();
      await widget.onChanged();
      if (!mounted) return;
      showAppMessage(context, 'Request approved.');
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  Future<void> _reject(Map<String, dynamic> item) async {
    final kind = (item['kind'] ?? '').toString();
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject request?'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(
            labelText: 'Reason (optional)',
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    if (confirmed != true || !mounted) return;

    try {
      switch (kind) {
        case 'charge_deletion':
          final requestId = (item['staff_request_id'] ?? '').toString();
          if (requestId.isEmpty) return;
          await portalDio().post(
            '/admin/staff-requests/$requestId/reject',
            data: {if (reason.isNotEmpty) 'reason': reason},
          );
          break;
        case 'booking_date_change':
          final bookingId = (item['booking_id'] ?? '').toString();
          if (bookingId.isEmpty) return;
          await portalDio().post(
            '/admin/bookings/$bookingId/date-change/reject',
            data: {if (reason.isNotEmpty) 'reason': reason},
          );
          break;
        case 'reservation_date_change':
          final reservationId = (item['reservation_id'] ?? '').toString();
          if (reservationId.isEmpty) return;
          await portalDio().post(
            '/admin/reservations/$reservationId/date-change/reject',
            data: {if (reason.isNotEmpty) 'reason': reason},
          );
          break;
      }
      await _load();
      await widget.onChanged();
      if (!mounted) return;
      showAppMessage(context, 'Request rejected.');
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  Future<void> _dismissStaffRequest(Map<String, dynamic> item) async {
    final requestId = (item['staff_request_id'] ?? '').toString();
    if (requestId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove request?'),
        content: const Text(
          'This clears the request from the queue without approving or rejecting it. '
          'The charge stays on the guest bill — use this for test requests.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove request'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await portalDio().delete('/admin/staff-requests/$requestId');
      await _load();
      await widget.onChanged();
      if (!mounted) return;
      showAppMessage(context, 'Request removed. The charge was not changed.');
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  bool _canDismiss(Map<String, dynamic> item) {
    final kind = (item['kind'] ?? '').toString();
    final requestId = (item['staff_request_id'] ?? '').toString();
    return requestId.isNotEmpty && kind == 'charge_deletion';
  }

  String _dateDetail(Map<String, dynamic> item) {
    final payload = item['payload'];
    if (payload is! Map) return '';
    final inDate = payload['check_in_date'] ?? payload['check_in_at'];
    final outDate = payload['check_out_date'] ?? payload['check_out_at'];
    if (inDate == null && outDate == null) return '';
    return 'Requested: ${AdminDashboardModels.formatDisplayDate(inDate)} → '
        '${AdminDashboardModels.formatDisplayDate(outDate)}';
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

    return RefreshIndicator(
      onRefresh: _load,
      child: _items.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 120),
                Center(child: Text('No pending front desk requests.')),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              itemCount: _items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final item = _items[i];
                final detail = _dateDetail(item);
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          (item['title'] ?? 'Request').toString(),
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text((item['subtitle'] ?? '').toString()),
                        if (detail.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            detail,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          'From ${item['requested_by'] ?? 'Front desk'}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _reject(item),
                                child: const Text('Reject'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton(
                                onPressed: () => _approve(item),
                                child: const Text('Approve'),
                              ),
                            ),
                          ],
                        ),
                        if (_canDismiss(item)) ...[
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () => _dismissStaffRequest(item),
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: const Text('Remove request (keep charge)'),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
