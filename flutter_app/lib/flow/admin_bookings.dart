import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../dio_client.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/app_card.dart';
import '../widgets/app_state_views.dart';

/// Approve or reject public reservation requests (future stays).
class AdminBookingsScreen extends StatefulWidget {
  const AdminBookingsScreen({super.key});

  @override
  State<AdminBookingsScreen> createState() => _AdminBookingsScreenState();
}

class _AdminBookingsScreenState extends State<AdminBookingsScreen> {
  List<dynamic> _reservations = const [];
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
      setState(() {
        _reservations = (d.data?['reservations'] as List?) ?? const [];
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
    setState(() => _busy = true);
    try {
      await portalDio().post<Map<String, dynamic>>('/admin/reservations/$id/approve');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reservation approved. Room is held until check-in date.')),
      );
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dioErrorMessage(e))),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reservation request rejected.')),
      );
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dioErrorMessage(e))),
      );
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
