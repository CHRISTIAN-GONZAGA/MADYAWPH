import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../dio_client.dart';
import '../widgets/app_card.dart';
import '../widgets/app_input.dart';
import '../widgets/app_state_views.dart';

class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  Map<String, dynamic>? _sales;
  Map<String, dynamic>? _timeline;
  Map<String, dynamic>? _transfers;
  Map<String, dynamic>? _tasks;
  Map<String, dynamic>? _occupancy;
  bool _loading = true;
  String? _error;
  String _granularity = 'week';

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
      final sales = await portalDio().get<Map<String, dynamic>>(
        '/reports/sales/timeseries',
        queryParameters: {'granularity': _granularity},
      );
      final timeline = await portalDio().get<Map<String, dynamic>>(
        '/reports/activity/timeline',
        queryParameters: {'granularity': _granularity},
      );
      final transfers =
          await portalDio().get<Map<String, dynamic>>('/reports/transfers');
      final tasks =
          await portalDio().get<Map<String, dynamic>>('/reports/tasks/performance');
      final occupancy =
          await portalDio().get<Map<String, dynamic>>('/reports/room-occupancy');
      setState(() {
        _sales = sales.data;
        _timeline = timeline.data;
        _transfers = transfers.data;
        _tasks = tasks.data;
        _occupancy = occupancy.data;
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports Center'),
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
    final salesSummary = (_sales?['totals'] as Map<String, dynamic>?) ?? {};
    final timelinePoints = (_timeline?['points'] as List<dynamic>?) ?? [];
    final transferSummary = (_transfers?['summary'] as Map<String, dynamic>?) ?? {};
    final taskSummary = (_tasks?['summary'] as Map<String, dynamic>?) ?? {};
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          AppSectionCard(
            child: Row(
              children: [
                Expanded(
                  child: AppSelect<String>(
                    label: 'Report period',
                    value: _granularity,
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _granularity = v);
                      _load();
                    },
                    items: const [
                      DropdownMenuItem(value: 'day', child: Text('Daily')),
                      DropdownMenuItem(value: 'week', child: Text('Weekly')),
                      DropdownMenuItem(value: 'month', child: Text('Monthly')),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  label: 'Sales',
                  value: '₱${(salesSummary['sales'] ?? 0).toString()}',
                  icon: Icons.payments_outlined,
                ),
              ),
              Expanded(
                child: _KpiCard(
                  label: 'Bookings',
                  value: '${salesSummary['bookings'] ?? 0}',
                  icon: Icons.book_online_outlined,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  label: 'Transfers',
                  value: '${transferSummary['count'] ?? 0}',
                  icon: Icons.swap_horiz_outlined,
                ),
              ),
              Expanded(
                child: _KpiCard(
                  label: 'Task completion',
                  value: '${taskSummary['completion_rate'] ?? 0}%',
                  icon: Icons.task_alt_outlined,
                ),
              ),
            ],
          ),
          AppSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Occupancy', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(
                  'Booked ${_occupancy?['booked_rooms'] ?? 0} / ${_occupancy?['total_rooms'] ?? 0} rooms (${_occupancy?['occupancy_rate'] ?? 0}%)',
                ),
              ],
            ),
          ),
          AppSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Activity timeline', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (timelinePoints.isEmpty)
                  const Text('No activity found.')
                else
                  ...timelinePoints.take(12).map((p) {
                    final m = p as Map<String, dynamic>;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.timeline_outlined),
                      title: Text((m['period_label'] ?? '').toString()),
                      subtitle: Text('Events: ${(m['total_events'] ?? 0)}'),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AdminActivityLogsScreen extends StatefulWidget {
  const AdminActivityLogsScreen({super.key});

  @override
  State<AdminActivityLogsScreen> createState() => _AdminActivityLogsScreenState();
}

class _AdminActivityLogsScreenState extends State<AdminActivityLogsScreen> {
  List<dynamic> _logs = const [];
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
      final res = await portalDio().get<Map<String, dynamic>>('/activity-logs');
      setState(() {
        _logs = (res.data?['data'] as List<dynamic>? ?? []);
        _loading = false;
      });
    } on DioException catch (e) {
      setState(() {
        _error = dioErrorMessage(e);
        _loading = false;
      });
    }
  }

  String _groupLabel(DateTime? dt) {
    if (dt == null) return 'Older';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(d).inDays;
    if (diff == 0) return 'Today';
    if (diff <= 7) return 'This Week';
    return 'Older';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Activity Logs')),
      body: _loading
          ? const AppLoadingView()
          : _error != null
              ? AppErrorView(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    ..._logs.map((l) {
                      final m = l as Map<String, dynamic>;
                      final created = DateTime.tryParse(
                          (m['created_at'] ?? '').toString());
                      return AppSectionCard(
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.history_outlined),
                          title: Text((m['action'] ?? 'Activity').toString()),
                          subtitle: Text(
                            '${_groupLabel(created)} · ${(created ?? DateTime.now()).toLocal()}',
                          ),
                        ),
                      );
                    }),
                  ],
                ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelMedium),
                Text(value, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
