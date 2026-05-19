import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../dio_client.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/app_state_views.dart';

/// Completed stays surfaced when rooms leave checkout → maintenance (guest cleared).
class GuestListHistoryScreen extends StatefulWidget {
  const GuestListHistoryScreen({super.key});

  @override
  State<GuestListHistoryScreen> createState() => _GuestListHistoryScreenState();
}

class _GuestListHistoryScreenState extends State<GuestListHistoryScreen> {
  List<dynamic> _rows = const [];
  String? _error;
  bool _loading = true;

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
          await portalDio().get<Map<String, dynamic>>('/admin/guest-history');
      setState(() {
        _rows = (res.data?['data'] as List<dynamic>?) ?? const [];
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

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppBar(
        title: const Text('Guest list history'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const AppLoadingView();
    if (_error != null) {
      return AppErrorView(message: _error!, onRetry: _load);
    }
    if (_rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No completed stays recorded yet. Entries appear after checkout clears guest data from a room.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _rows.length,
        itemBuilder: (context, i) {
          final m = _rows[i] as Map<String, dynamic>;
          final ref = (m['booking_reference'] ?? '').toString();
          final guest = (m['guest_name'] ?? '').toString();
          final roomNo = (m['room_number'] ?? '').toString();
          final ci = (m['check_in_date'] ?? '').toString();
          final co = (m['check_out_date'] ?? '').toString();
          final checkedOutAt = (m['checked_out_display'] ?? '').toString();
          final phone = (m['guest_phone'] ?? '').toString();
          return Card(
            child: ListTile(
              leading: const Icon(Icons.history_edu_outlined),
              title: Text(guest.isEmpty ? 'Guest' : guest),
              subtitle: Text(
                [
                  if (roomNo.isNotEmpty) 'Room $roomNo',
                  if (ref.isNotEmpty) 'Ref: $ref',
                  if (ci.isNotEmpty) 'Check-in: $ci',
                  if (co.isNotEmpty) 'Scheduled departure: $co',
                  if (checkedOutAt.isNotEmpty) 'Checked out: $checkedOutAt',
                  if (phone.isNotEmpty) phone,
                ].join('\n'),
              ),
              isThreeLine: true,
            ),
          );
        },
      ),
    );
  }
}
