import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../dio_client.dart';
import '../../../widgets/insufficient_hotel_credits.dart';
import '../admin_dashboard_models.dart';
import '../../admin_bookings.dart';
import '../../admin_chat.dart';

class ReservationSection extends StatefulWidget {
  const ReservationSection({
    super.key,
    required this.reservations,
    required this.onChanged,
    this.currentCredits = 0,
    this.onTopUpCredits,
  });

  final List<dynamic> reservations;
  final Future<void> Function() onChanged;
  final double currentCredits;
  final VoidCallback? onTopUpCredits;

  @override
  State<ReservationSection> createState() => _ReservationSectionState();
}

class _ReservationSectionState extends State<ReservationSection> {
  bool _busy = false;

  Future<void> _approve(String id) async {
    if (_busy || id.isEmpty) return;
    if (!await guardHotelCreditsBeforeApproval(
      context,
      currentCredits: widget.currentCredits,
      onTopUp: widget.onTopUpCredits,
    )) {
      return;
    }
    setState(() => _busy = true);
    try {
      await portalDio().post('/admin/reservations/$id/approve');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reservation approved.')),
      );
      await widget.onChanged();
    } on DioException catch (e) {
      if (!mounted) return;
      if (isHotelCreditsApprovalError(e)) {
        await handleHotelCreditsApprovalError(
          context,
          e,
          onTopUp: widget.onTopUpCredits,
        );
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(dioErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject(String id) async {
    if (_busy || id.isEmpty) return;
    setState(() => _busy = true);
    try {
      await portalDio().post('/admin/reservations/$id/reject');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reservation rejected.')),
      );
      await widget.onChanged();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(dioErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _resolveId(Map<String, dynamic> r) =>
      (r['id'] ?? r['_id'] ?? '').toString();

  String _mediaUrl(String raw) {
    if (raw.isEmpty) return raw;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    final base = portalDio().options.baseUrl;
    final root = base.replaceAll(RegExp(r'/api/v1$'), '');
    return raw.startsWith('/') ? '$root$raw' : '$root/$raw';
  }

  String _statusLabel(String? s) {
    final v = (s ?? '').toString();
    if (v == 'pending_approval') return 'Pending';
    if (v == 'approved' || v == 'reserved') return 'Confirmed';
    if (v == 'rejected') return 'Rejected';
    return v.isEmpty ? 'Pending' : v;
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.reservations.whereType<Map<String, dynamic>>().toList();

    if (list.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          Text(
            'Reservations',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          const Text('No incoming reservation requests.'),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const AdminBookingsScreen(),
                ),
              );
            },
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open full booking screen'),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: list.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Reservation requests',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const AdminBookingsScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Full screen'),
                ),
              ],
            ),
          );
        }
        final r = list[i - 1];
        final id = _resolveId(r);
        final status = _statusLabel(r['status']?.toString());
        final meta = r['metadata'] as Map<String, dynamic>?;
        final discountUrl = _mediaUrl(meta?['discount_id_url']?.toString() ?? '');

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        (r['guest_name'] ?? 'Guest').toString(),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Chip(label: Text(status)),
                  ],
                ),
                Text('Ref: ${r['external_reference'] ?? ''}'),
                Text(
                  'Check-in: ${AdminDashboardModels.formatDateRange(r['check_in_date'], r['check_out_date'])}',
                ),
                Text('Phone: ${r['guest_phone'] ?? ''}'),
                if (discountUrl.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Verification ID',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      discountUrl,
                      height: 120,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => SelectableText(
                        discountUrl,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    if (status == 'Pending') ...[
                      FilledButton(
                        onPressed: _busy ? null : () => _approve(id),
                        child: const Text('Approve'),
                      ),
                      OutlinedButton(
                        onPressed: _busy ? null : () => _reject(id),
                        child: const Text('Reject'),
                      ),
                    ],
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => const AdminChatHubScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.message_outlined),
                      label: const Text('Message'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
