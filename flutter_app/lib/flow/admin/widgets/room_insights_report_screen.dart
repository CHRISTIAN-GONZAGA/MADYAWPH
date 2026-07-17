import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../dio_client.dart';
import '../../../widgets/app_scaffold.dart';
import '../../../widgets/app_state_views.dart';

/// Most/least booked rooms, profit leaders, maintenance frequency.
class RoomInsightsReportScreen extends StatefulWidget {
  const RoomInsightsReportScreen({super.key});

  @override
  State<RoomInsightsReportScreen> createState() =>
      _RoomInsightsReportScreenState();
}

class _RoomInsightsReportScreenState extends State<RoomInsightsReportScreen> {
  Map<String, dynamic>? _data;
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
          await portalDio().get<Map<String, dynamic>>('/reports/room-insights');
      if (!mounted) return;
      setState(() {
        _data = res.data;
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = dioErrorMessage(e);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
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
        title: const Text('Room insights'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const AppLoadingView()
          : _error != null
              ? AppErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: [
                      Text(
                        'Period: ${_data?['from'] ?? '—'} → ${_data?['to'] ?? '—'}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      _TotalsRow(totals: (_data?['totals'] as Map?) ?? const {}),
                      const SizedBox(height: 16),
                      _RoomRankSection(
                        title: 'Most booked rooms',
                        subtitle: 'Highest stay count',
                        rows: (_data?['most_booked'] as List?) ?? const [],
                        metricKey: 'bookings_count',
                        metricLabel: 'bookings',
                      ),
                      _RoomRankSection(
                        title: 'Least booked rooms',
                        subtitle: 'Lowest stay count',
                        rows: (_data?['least_booked'] as List?) ?? const [],
                        metricKey: 'bookings_count',
                        metricLabel: 'bookings',
                      ),
                      _RoomRankSection(
                        title: 'Most profit per room',
                        subtitle: 'Recognized revenue',
                        rows: (_data?['most_profit'] as List?) ?? const [],
                        metricKey: 'revenue',
                        metricLabel: '₱',
                        isMoney: true,
                      ),
                      _RoomRankSection(
                        title: 'Most frequent maintenance',
                        subtitle: 'Maintenance tasks logged',
                        rows: (_data?['most_maintenance'] as List?) ?? const [],
                        metricKey: 'maintenance_events',
                        metricLabel: 'events',
                      ),
                      _RoomRankSection(
                        title: 'Currently cleaning',
                        subtitle: 'Rooms in cleaning status now',
                        rows: (_data?['currently_cleaning'] as List?) ?? const [],
                        metricKey: 'status',
                        metricLabel: '',
                      ),
                      _RoomRankSection(
                        title: 'Currently maintenance',
                        subtitle: 'Rooms flagged for repair',
                        rows:
                            (_data?['currently_maintenance'] as List?) ?? const [],
                        metricKey: 'status',
                        metricLabel: '',
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _TotalsRow extends StatelessWidget {
  const _TotalsRow({required this.totals});
  final Map totals;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget tile(String label, String value) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(value,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
                Text(label, style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
        );
    return Row(
      children: [
        tile('Rooms', '${totals['rooms'] ?? 0}'),
        const SizedBox(width: 8),
        tile('Bookings', '${totals['bookings'] ?? 0}'),
        const SizedBox(width: 8),
        tile(
          'Revenue',
          '₱${((totals['revenue'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}',
        ),
      ],
    );
  }
}

class _RoomRankSection extends StatelessWidget {
  const _RoomRankSection({
    required this.title,
    required this.subtitle,
    required this.rows,
    required this.metricKey,
    required this.metricLabel,
    this.isMoney = false,
  });

  final String title;
  final String subtitle;
  final List rows;
  final String metricKey;
  final String metricLabel;
  final bool isMoney;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('No data for this period.'),
              )
            else
              ...rows.take(8).map((raw) {
                final m = Map<String, dynamic>.from(raw as Map);
                final no = (m['room_number'] ?? '—').toString();
                final type = (m['room_type'] ?? '').toString();
                final metric = m[metricKey];
                final metricText = isMoney
                    ? '₱${((metric as num?)?.toDouble() ?? 0).toStringAsFixed(0)}'
                    : metricKey == 'status'
                        ? (metric ?? '').toString()
                        : '${metric ?? 0} $metricLabel';
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('Room $no'),
                  subtitle: type.isEmpty ? null : Text(type),
                  trailing: Text(
                    metricText,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
