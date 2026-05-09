import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../dio_client.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/app_card.dart';
import '../widgets/app_state_views.dart';

class AdminBookingsScreen extends StatefulWidget {
  const AdminBookingsScreen({super.key});

  @override
  State<AdminBookingsScreen> createState() => _AdminBookingsScreenState();
}

class _AdminBookingsScreenState extends State<AdminBookingsScreen> {
  List<dynamic> _bookings = const [];
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
      final b = await portalDio().get<Map<String, dynamic>>('/bookings');
      final d = await portalDio().get<Map<String, dynamic>>('/admin/dashboard');
      setState(() {
        _bookings = (b.data?['data'] as List?) ?? const [];
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

  Future<void> _bookingAction(String id, String action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await portalDio().put('/bookings/$id/$action');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Booking $action done.')));
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
    return AppScaffold(
      appBar: AppBar(
        title: const Text('Booking operations'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh))
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
          Text('Reservations', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_reservations.isEmpty)
            const Text('No reservation requests.')
          else
            ..._reservations.take(30).map((r) {
              final m = r as Map<String, dynamic>;
              return AppSectionCard(
                child: ListTile(
                  leading: const Icon(Icons.event_available_outlined),
                  title: Text((m['guest_name'] ?? 'Guest').toString()),
                  subtitle: Text(
                    'Ref: ${(m['external_reference'] ?? '').toString()} · '
                    'Status: ${(m['status'] ?? '').toString()}',
                  ),
                ),
              );
            }),
          const SizedBox(height: 16),
          Text('Bookings', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_bookings.isEmpty)
            const Text('No bookings yet.')
          else
            ..._bookings.map((b) {
              final m = b as Map<String, dynamic>;
              final id = (m['id'] ?? m['_id'] ?? '').toString();
              return AppSectionCard(
                child: ListTile(
                  leading: const Icon(Icons.bed_outlined),
                  title: Text((m['guest_name'] ?? 'Guest').toString()),
                  subtitle: Text(
                    'Ref: ${(m['booking_reference'] ?? '').toString()} · '
                    'Status: ${(m['status'] ?? '').toString()}',
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) => _bookingAction(id, v),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'cancel', child: Text('Cancel')),
                      PopupMenuItem(value: 'complete', child: Text('Complete')),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
