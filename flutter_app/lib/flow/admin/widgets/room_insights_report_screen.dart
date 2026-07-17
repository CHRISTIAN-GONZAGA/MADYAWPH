import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../dio_client.dart';
import '../../../widgets/app_scaffold.dart';
import '../../../widgets/app_state_views.dart';

/// Most/least booked rooms, profit leaders, occupancy, maintenance frequency.
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
  DateTimeRange? _range;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _fmtDay(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await portalDio().get<Map<String, dynamic>>(
        '/reports/room-insights',
        queryParameters: {
          if (_range != null) 'from': _fmtDay(_range!.start),
          if (_range != null) 'to': _fmtDay(_range!.end),
        },
      );
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

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: _range ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 90)),
            end: now,
          ),
    );
    if (picked == null) return;
    setState(() => _range = picked);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppBar(
        title: const Text('Room insights'),
        actions: [
          IconButton(
            onPressed: _pickRange,
            icon: const Icon(Icons.date_range_outlined),
            tooltip: 'Change period',
          ),
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
                        'Period: ${_data?['from'] ?? '—'} → ${_data?['to'] ?? '—'}'
                        '${_data?['period_days'] != null ? ' · ${_data?['period_days']} days' : ''}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      _TotalsGrid(totals: (_data?['totals'] as Map?) ?? const {}),
                      const SizedBox(height: 12),
                      _StatusBreakdown(
                        breakdown: (_data?['status_breakdown'] as Map?) ?? const {},
                      ),
                      const SizedBox(height: 12),
                      _RoomTypeSection(
                        rows: (_data?['by_room_type'] as List?) ?? const [],
                      ),
                      _RoomRankSection(
                        title: 'Most booked rooms',
                        subtitle: 'Highest stay count',
                        rows: (_data?['most_booked'] as List?) ?? const [],
                        metricKey: 'bookings_count',
                        metricLabel: 'bookings',
                        secondaryKey: 'occupancy_rate',
                        secondaryLabel: '% occupancy',
                      ),
                      _RoomRankSection(
                        title: 'Least booked rooms',
                        subtitle: 'Lowest stay count',
                        rows: (_data?['least_booked'] as List?) ?? const [],
                        metricKey: 'bookings_count',
                        metricLabel: 'bookings',
                        secondaryKey: 'last_booked_at',
                        secondaryLabel: 'last booked',
                      ),
                      _RoomRankSection(
                        title: 'Most profit per room',
                        subtitle: 'Recognized revenue',
                        rows: (_data?['most_profit'] as List?) ?? const [],
                        metricKey: 'revenue',
                        metricLabel: '₱',
                        isMoney: true,
                        secondaryKey: 'avg_booking_value',
                        secondaryLabel: 'avg/booking',
                        secondaryIsMoney: true,
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

class _TotalsGrid extends StatelessWidget {
  const _TotalsGrid({required this.totals});
  final Map totals;

  String _money(num? v) => '₱${(v?.toDouble() ?? 0).toStringAsFixed(0)}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget tile(String label, String value) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(value,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );

    final items = <Widget>[
      tile('Rooms', '${totals['rooms'] ?? 0}'),
      tile('Bookings', '${totals['bookings'] ?? 0}'),
      tile('Revenue', _money(totals['revenue'] as num?)),
      tile(
        'Occupancy',
        '${(totals['occupancy_rate'] as num?)?.toDouble().toStringAsFixed(1) ?? '0'}%',
      ),
      tile('Avg / booking', _money(totals['avg_booking_value'] as num?)),
      tile('Occupied now', '${totals['occupied_now'] ?? 0}'),
      tile('Available now', '${totals['available_now'] ?? 0}'),
      tile('Maintenance', '${totals['maintenance_events'] ?? 0}'),
    ];

    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 0.95,
      children: items,
    );
  }
}

class _StatusBreakdown extends StatelessWidget {
  const _StatusBreakdown({required this.breakdown});
  final Map breakdown;

  @override
  Widget build(BuildContext context) {
    if (breakdown.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    const statusColors = <String, Color>{
      'available': Colors.green,
      'booked': Colors.orange,
      'checked_in': Colors.blue,
      'checked_out': Colors.blueGrey,
      'cleaning': Colors.teal,
      'maintenance': Colors.red,
      'reserved': Colors.purple,
    };

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Room status snapshot',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: breakdown.entries.map((e) {
                final status = e.key.toString();
                final color = statusColors[status] ?? scheme.outline;
                return Chip(
                  avatar: CircleAvatar(backgroundColor: color, radius: 5),
                  label: Text('${status.replaceAll('_', ' ')} · ${e.value}'),
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomTypeSection extends StatelessWidget {
  const _RoomTypeSection({required this.rows});
  final List rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Performance by category',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            Text('Bookings, revenue, and occupancy per room category',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            ...rows.take(10).map((raw) {
              final m = Map<String, dynamic>.from(raw as Map);
              final revenue = (m['revenue'] as num?)?.toDouble() ?? 0;
              final occupancy =
                  (m['occupancy_rate'] as num?)?.toDouble() ?? 0;
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text((m['label'] ?? '—').toString()),
                subtitle: Text(
                  '${m['rooms'] ?? 0} rooms · ${m['bookings'] ?? 0} bookings · ${occupancy.toStringAsFixed(1)}% occupancy',
                ),
                trailing: Text(
                  '₱${revenue.toStringAsFixed(0)}',
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

class _RoomRankSection extends StatelessWidget {
  const _RoomRankSection({
    required this.title,
    required this.subtitle,
    required this.rows,
    required this.metricKey,
    required this.metricLabel,
    this.isMoney = false,
    this.secondaryKey,
    this.secondaryLabel,
    this.secondaryIsMoney = false,
  });

  final String title;
  final String subtitle;
  final List rows;
  final String metricKey;
  final String metricLabel;
  final bool isMoney;
  final String? secondaryKey;
  final String? secondaryLabel;
  final bool secondaryIsMoney;

  String? _secondaryText(Map<String, dynamic> m) {
    if (secondaryKey == null) return null;
    final v = m[secondaryKey];
    if (v == null) return null;
    if (secondaryIsMoney) {
      return '₱${((v as num?)?.toDouble() ?? 0).toStringAsFixed(0)} ${secondaryLabel ?? ''}'.trim();
    }
    if (v is num) {
      return '$v ${secondaryLabel ?? ''}'.trim();
    }
    final s = v.toString();
    if (s.isEmpty) return null;
    return '${secondaryLabel ?? ''}: $s'.trim();
  }

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
                final type = (m['category_name'] ?? '').toString().isNotEmpty
                    ? (m['category_name'] ?? '').toString()
                    : (m['room_type'] ?? '').toString();
                final metric = m[metricKey];
                final metricText = isMoney
                    ? '₱${((metric as num?)?.toDouble() ?? 0).toStringAsFixed(0)}'
                    : metricKey == 'status'
                        ? (metric ?? '').toString()
                        : '${metric ?? 0} $metricLabel';
                final secondary = _secondaryText(m);
                final subtitleParts = <String>[
                  if (type.isNotEmpty) type,
                  if (secondary != null) secondary,
                ];
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('Room $no'),
                  subtitle: subtitleParts.isEmpty
                      ? null
                      : Text(subtitleParts.join(' · ')),
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
