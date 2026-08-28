import 'package:dio/dio.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';
import 'package:flutter/material.dart';

import '../dio_client.dart';
import '../widgets/insufficient_hotel_credits.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/app_card.dart';
import '../widgets/app_state_views.dart';
import '../widgets/payment_proof_picker.dart';
import '../utils/money_format.dart';

/// Approve or reject public reservation requests (future stays).
class AdminBookingsScreen extends StatefulWidget {
  const AdminBookingsScreen({super.key});

  @override
  State<AdminBookingsScreen> createState() => _AdminBookingsScreenState();
}

class _AdminBookingsScreenState extends State<AdminBookingsScreen> {
  List<dynamic> _reservations = const [];
  double _currentCredits = 0;
  String? _error;
  bool _loading = true;
  bool _busy = false;

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
      final d = await portalDio().get<Map<String, dynamic>>('/admin/dashboard');
      final credits = d.data?['credits'] as Map<String, dynamic>?;
      setState(() {
        _reservations = (d.data?['reservations'] as List?) ?? const [];
        _currentCredits =
            (credits?['currentCredits'] as num?)?.toDouble() ?? 0;
        _loading = false;
      });
    } on DioException catch (e) {
      setState(() {
        _error = dioErrorMessage(e);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _approve(String id) async {
    if (_busy || id.isEmpty) return;

    Map<String, dynamic>? reservation;
    for (final raw in _reservations) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      if ((map['id'] ?? map['_id'] ?? '').toString() == id) {
        reservation = map;
        break;
      }
    }
    final meta = reservation?['metadata'];
    final metaMap = meta is Map
        ? Map<String, dynamic>.from(meta)
        : const <String, dynamic>{};
    final guestName =
        (reservation?['guest_name'] ?? 'Guest').toString();
    final payRef = (reservation?['payment_reference'] ??
            metaMap['payment_reference'] ??
            '—')
        .toString();
    final payShot = (reservation?['payment_screenshot_url'] ??
            metaMap['payment_screenshot_url'] ??
            '')
        .toString();
    final totalPaid = (reservation?['amount_paid'] as num?)?.toDouble() ??
        (reservation?['estimated_total'] as num?)?.toDouble() ??
        (metaMap['amount_paid'] as num?)?.toDouble() ??
        (metaMap['estimated_total'] as num?)?.toDouble() ??
        0;

    final reviewOk = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Review online payment'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Guest: $guestName',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('Payment reference: $payRef'),
              const SizedBox(height: 12),
              GuestStayDocuments(
                guestIdUrl: GuestStayDocuments.urlFrom(reservation, 'guest_id_url'),
                paymentScreenshotUrl: payShot,
                discountIdUrl: GuestStayDocuments.urlFrom(reservation, 'discount_id_url'),
                requireIdAndReceipt: true,
              ),
              const SizedBox(height: 6),
              Text(
                'Total paid: ${formatMoney(totalPaid)}',
                style: const TextStyle(fontWeight: FontWeight.w800),
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
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (reviewOk != true || !mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm approval?'),
        content: Text(
          'Approve prepaid online booking for $guestName?\n\n'
          'Ref: $payRef\n'
          'Total paid: ${formatMoney(totalPaid)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Go back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    if (!await guardHotelCreditsBeforeApproval(
      context,
      currentCredits: _currentCredits,
    )) {
      return;
    }
    setState(() => _busy = true);
    try {
      await portalDio().post<Map<String, dynamic>>('/admin/reservations/$id/approve');
      if (!mounted) return;
      showAppMessage(context, 'Reservation approved. Room is held until check-in date.');
      await _load();
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

  Future<void> _reject(String id) async {
    if (_busy || id.isEmpty) return;
    setState(() => _busy = true);
    try {
      await portalDio().post<Map<String, dynamic>>('/admin/reservations/$id/reject');
      if (!mounted) return;
      showAppMessage(context, 'Reservation request rejected.');
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppBar(
        title: const Text('Reservation requests'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const AppLoadingView();
    if (_error != null) return AppErrorView(message: _error!, onRetry: _load);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(
            'Approve requests to reserve the room from the guest’s check-in date. '
            'The app promotes approved holds to active bookings automatically on that date.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (_reservations.isEmpty)
            const Text('No reservation requests.')
          else
            ..._reservations.map((r) {
              final m = r as Map<String, dynamic>;
              final id = (m['id'] ?? m['_id'] ?? '').toString();
              final status = (m['status'] ?? '').toString();
              final pending = status == 'pending_approval';
              return AppSectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_available_outlined),
                      title: Text((m['guest_name'] ?? 'Guest').toString()),
                      subtitle: Text(
                        [
                          'Ref: ${(m['external_reference'] ?? '').toString()}',
                          'Status: $status',
                          if ((m['check_in_date'] ?? '').toString().isNotEmpty)
                            'Check-in: ${m['check_in_date']}',
                          if ((m['check_out_date'] ?? '').toString().isNotEmpty)
                            'Check-out: ${m['check_out_date']}',
                        ].join('\n'),
                      ),
                    ),
                    if (pending && id.isNotEmpty)
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _busy ? null : () => _reject(id),
                              child: const Text('Reject'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              onPressed: _busy ? null : () => _approve(id),
                              child: const Text('Approve'),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
