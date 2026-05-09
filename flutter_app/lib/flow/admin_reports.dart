import 'package:dio/dio.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../dio_client.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/app_card.dart';
import '../widgets/app_state_views.dart';

/// Revenue and operations charts with daily / weekly / monthly / annual granularity.
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
  Map<String, dynamic>? _profitOverview;
  bool _loading = true;
  String? _error;
  String _granularity = 'week';

  static const _granularityLabels = {
    'day': 'Daily',
    'week': 'Weekly',
    'month': 'Monthly',
    'year': 'Annual',
  };

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
      final qp = {'granularity': _granularity};
      final sales = await portalDio().get<Map<String, dynamic>>(
        '/reports/sales/timeseries',
        queryParameters: qp,
      );
      final timeline = await portalDio().get<Map<String, dynamic>>(
        '/reports/activity/timeline',
        queryParameters: qp,
      );
      final transfers =
          await portalDio().get<Map<String, dynamic>>('/reports/transfers');
      final tasks =
          await portalDio().get<Map<String, dynamic>>('/reports/tasks/performance');
      final occupancy =
          await portalDio().get<Map<String, dynamic>>('/reports/room-occupancy');
      final overview =
          await portalDio().get<Map<String, dynamic>>('/reports/profit-overview');
      setState(() {
        _sales = sales.data;
        _timeline = timeline.data;
        _transfers = transfers.data;
        _tasks = tasks.data;
        _occupancy = occupancy.data;
        _profitOverview = overview.data;
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
        title: const Text('Reports & analytics'),
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
    final scheme = Theme.of(context).colorScheme;
    final salesSummary = (_sales?['totals'] as Map<String, dynamic>?) ?? {};
    final salesPoints = (_sales?['points'] as List<dynamic>?) ?? [];
    final timelinePoints = (_timeline?['points'] as List<dynamic>?) ?? [];
    final transferSummary =
        (_transfers?['summary'] as Map<String, dynamic>?) ?? {};
    final taskSummary = (_tasks?['summary'] as Map<String, dynamic>?) ?? {};
    final overview = _profitOverview ?? const {};

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total profit overview',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                    'Daily: ₱${_fmtNum((overview['daily'] as Map?)?['profit'] ?? 0)}'),
                Text(
                    'Weekly: ₱${_fmtNum((overview['weekly'] as Map?)?['profit'] ?? 0)}'),
                Text(
                    'Monthly: ₱${_fmtNum((overview['monthly'] as Map?)?['profit'] ?? 0)}'),
                Text(
                    'Annual: ₱${_fmtNum((overview['annual'] as Map?)?['profit'] ?? 0)}'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Period',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 10),
                SegmentedButton<String>(
                  segments: _granularityLabels.entries
                      .map(
                        (e) => ButtonSegment<String>(
                          value: e.key,
                          label: Text(e.value),
                        ),
                      )
                      .toList(),
                  selected: {_granularity},
                  onSelectionChanged: (s) {
                    setState(() => _granularity = s.first);
                    _load();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  label: 'Total revenue',
                  value:
                      '₱${_fmtNum(salesSummary['sales'] ?? salesSummary['gross_sales'] ?? 0)}',
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
                  label: 'Room transfers',
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
                Text(
                  'Occupancy',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Booked ${_occupancy?['booked_rooms'] ?? 0} / ${_occupancy?['total_rooms'] ?? 0} rooms (${_occupancy?['occupancy_rate'] ?? 0}%)',
                ),
              ],
            ),
          ),
          Text(
            'Revenue by period',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          AppSectionCard(
            child: SizedBox(
              height: 240,
              child: salesPoints.isEmpty
                  ? const Center(child: Text('No booking revenue in range.'))
                  : Padding(
                      padding: const EdgeInsets.only(
                          right: 12, top: 12, bottom: 4),
                      child: BarChart(
                        _salesBarData(salesPoints, scheme),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Bookings count',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          AppSectionCard(
            child: SizedBox(
              height: 220,
              child: salesPoints.isEmpty
                  ? const Center(child: Text('No bookings in range.'))
                  : Padding(
                      padding: const EdgeInsets.only(
                          right: 12, top: 12, bottom: 4),
                      child: LineChart(_bookingsLineData(salesPoints, scheme)),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Activity volume',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          AppSectionCard(
            child: SizedBox(
              height: 220,
              child: timelinePoints.isEmpty
                  ? const Center(child: Text('No activity logs in range.'))
                  : Padding(
                      padding: const EdgeInsets.only(
                          right: 12, top: 12, bottom: 4),
                      child: BarChart(
                        _activityBarData(timelinePoints, scheme),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Paid transactions',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          AppSectionCard(
            child: salesPoints.isEmpty
                ? const Text('No paid transactions in selected range.')
                : Column(
                    children: salesPoints
                        .expand((point) {
                          final p = point as Map<String, dynamic>;
                          final txns = (p['transactions'] as List<dynamic>? ?? const []);
                          return txns.take(10);
                        })
                        .take(30)
                        .map((txnRaw) {
                          final txn = txnRaw as Map<String, dynamic>;
                          final line = (txn['line'] ?? '').toString();
                          final amount =
                              ((txn['amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2);
                          final method =
                              (txn['payment_method'] ?? '').toString().trim();
                          final channelRaw =
                              (txn['payment_channel'] ?? '').toString().trim();
                          final channelLabel = switch (channelRaw.toLowerCase()) {
                            'cash' => 'Cash',
                            'online' => 'Online',
                            'unknown' => '',
                            _ => channelRaw.isEmpty ? '' : channelRaw,
                          };
                          final payBits = <String>[
                            if (method.isNotEmpty) method,
                            if (channelLabel.isNotEmpty) channelLabel,
                          ];
                          final payLine = payBits.isEmpty
                              ? 'Payment: —'
                              : 'Payment: ${payBits.join(' · ')}';
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.receipt_long_outlined),
                            title: Text(
                              line.isEmpty ? 'Transaction' : line,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            subtitle: Text(
                              'Guest: ${(txn['guest_name'] ?? '').toString()}\n$payLine',
                            ),
                            isThreeLine: true,
                            trailing: Text('₱$amount'),
                          );
                        })
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }

  BarChartData _salesBarData(List<dynamic> points, ColorScheme scheme) {
    final groups = <BarChartGroupData>[];
    final maxShow = points.length > 20 ? 20 : points.length;
    var maxY = 1.0;
    for (var i = 0; i < maxShow; i++) {
      final m = points[i] as Map<String, dynamic>;
      final v = (m['gross_sales'] ?? 0).toDouble();
      if (v > maxY) maxY = v;
      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: v,
              width: 10,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              color: scheme.primary,
            ),
          ],
        ),
      );
    }

    return BarChartData(
      maxY: maxY * 1.15,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: maxY > 0 ? maxY / 4 : 1,
        getDrawingHorizontalLine: (_) => FlLine(
          color: scheme.outlineVariant.withOpacity(0.5),
          strokeWidth: 1,
        ),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 42,
            getTitlesWidget: (v, _) => Text(
              v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : v.toInt().toString(),
              style: const TextStyle(fontSize: 10),
            ),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 28,
            getTitlesWidget: (xv, _) {
              final i = xv.toInt();
              if (i < 0 || i >= maxShow) return const SizedBox.shrink();
              final m = points[i] as Map<String, dynamic>;
              final raw = (m['period_label'] ?? '').toString();
              final short =
                  raw.length > 8 ? raw.substring(raw.length - 7) : raw;
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  short,
                  style: const TextStyle(fontSize: 9),
                ),
              );
            },
          ),
        ),
      ),
      barGroups: groups,
    );
  }

  LineChartData _bookingsLineData(List<dynamic> points, ColorScheme scheme) {
    final spots = <FlSpot>[];
    var maxY = 4.0;
    final n = points.length > 24 ? 24 : points.length;
    for (var i = 0; i < n; i++) {
      final m = points[i] as Map<String, dynamic>;
      final c = (m['booking_count'] ?? 0).toDouble();
      if (c > maxY) maxY = c;
      spots.add(FlSpot(i.toDouble(), c));
    }

    return LineChartData(
      minY: 0,
      maxY: maxY * 1.2,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) => FlLine(
          color: scheme.outlineVariant.withOpacity(0.45),
          strokeWidth: 1,
        ),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 28,
            getTitlesWidget: (v, _) => Text(
              v.toInt().toString(),
              style: const TextStyle(fontSize: 10),
            ),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 22,
            getTitlesWidget: (xv, _) {
              final i = xv.toInt();
              if (i < 0 || i >= n) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('$i', style: const TextStyle(fontSize: 9)),
              );
            },
          ),
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: scheme.tertiary,
          barWidth: 3,
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(
            show: true,
            color: scheme.tertiary.withOpacity(0.12),
          ),
        ),
      ],
    );
  }

  BarChartData _activityBarData(List<dynamic> points, ColorScheme scheme) {
    final groups = <BarChartGroupData>[];
    final maxShow = points.length > 16 ? 16 : points.length;
    var maxY = 1.0;
    for (var i = 0; i < maxShow; i++) {
      final m = points[i] as Map<String, dynamic>;
      final v = (m['total_events'] ?? 0).toDouble();
      if (v > maxY) maxY = v;
      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: v,
              width: 14,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              color: scheme.secondary,
            ),
          ],
        ),
      );
    }

    return BarChartData(
      maxY: maxY * 1.2,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) => FlLine(
          color: scheme.outlineVariant.withOpacity(0.45),
          strokeWidth: 1,
        ),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 28,
            getTitlesWidget: (v, _) => Text(
              v.toInt().toString(),
              style: const TextStyle(fontSize: 10),
            ),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 26,
            getTitlesWidget: (xv, _) {
              final i = xv.toInt();
              if (i < 0 || i >= maxShow) return const SizedBox.shrink();
              final m = points[i] as Map<String, dynamic>;
              final raw = (m['period_label'] ?? '').toString();
              final short =
                  raw.length > 6 ? raw.substring(raw.length - 5) : raw;
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(short, style: const TextStyle(fontSize: 9)),
              );
            },
          ),
        ),
      ),
      barGroups: groups,
    );
  }

  static String _fmtNum(Object? v) {
    final n = (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0;
    return n.toStringAsFixed(n >= 100 ? 0 : 2);
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
