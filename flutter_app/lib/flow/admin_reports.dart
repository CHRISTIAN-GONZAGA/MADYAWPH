import 'package:dio/dio.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../dio_client.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/app_card.dart';
import '../widgets/app_state_views.dart';

/// Revenue and operations charts with daily / weekly / monthly / annual granularity.
class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key, this.embedded = false});

  final bool embedded;

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
  Map<String, dynamic>? _resellerPayments;
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
      final results = await Future.wait([
        portalDio().get<Map<String, dynamic>>(
          '/reports/sales/timeseries',
          queryParameters: qp,
        ),
        portalDio().get<Map<String, dynamic>>(
          '/reports/activity/timeline',
          queryParameters: qp,
        ),
        portalDio().get<Map<String, dynamic>>('/reports/transfers'),
        portalDio().get<Map<String, dynamic>>('/reports/tasks/performance'),
        portalDio().get<Map<String, dynamic>>('/reports/room-occupancy'),
        portalDio().get<Map<String, dynamic>>('/reports/profit-overview'),
        portalDio().get<Map<String, dynamic>>(
          '/reports/reseller-payments/timeseries',
          queryParameters: qp,
        ),
      ]);
      setState(() {
        _sales = results[0].data;
        _timeline = results[1].data;
        _transfers = results[2].data;
        _tasks = results[3].data;
        _occupancy = results[4].data;
        _profitOverview = results[5].data;
        _resellerPayments = results[6].data;
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
    final body = _buildBody();
    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Financial overview',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ),
          Expanded(child: body),
        ],
      );
    }
    return AppScaffold(
      appBar: AppBar(
        title: const Text('Reports & analytics'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: body,
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
    final resellerPay = _resellerPayments ?? const {};
    final resellerTotals = resellerPay['totals'] as Map<String, dynamic>? ?? {};
    final resellerPoints = (resellerPay['points'] as List<dynamic>?) ?? [];
    final reportFrom = (_sales?['from'] ?? '').toString();
    final reportTo = (_sales?['to'] ?? '').toString();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, widget.embedded ? 8 : 16, 16, 32),
        children: [
          AppSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!widget.embedded)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Financial overview',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                _PeriodFinanceRow(
                  label: 'Today (daily)',
                  data: overview['daily'] as Map<String, dynamic>?,
                ),
                const Divider(height: 20),
                _PeriodFinanceRow(
                  label: 'This week',
                  data: overview['weekly'] as Map<String, dynamic>?,
                ),
                const Divider(height: 20),
                _PeriodFinanceRow(
                  label: 'This month',
                  data: overview['monthly'] as Map<String, dynamic>?,
                ),
                const Divider(height: 20),
                _PeriodFinanceRow(
                  label: 'This year',
                  data: overview['annual'] as Map<String, dynamic>?,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reseller commissions (payouts)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Period total: ₱${_fmtNum(resellerTotals['total_paid'] ?? 0)}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  '${resellerTotals['payment_count'] ?? 0} payment(s)',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 16),
                _ResellerPeriodRow(
                  label: 'Today',
                  data: (overview['reseller_payments'] as Map?)?['daily']
                      as Map<String, dynamic>?,
                ),
                _ResellerPeriodRow(
                  label: 'This week',
                  data: (overview['reseller_payments'] as Map?)?['weekly']
                      as Map<String, dynamic>?,
                ),
                _ResellerPeriodRow(
                  label: 'This month',
                  data: (overview['reseller_payments'] as Map?)?['monthly']
                      as Map<String, dynamic>?,
                ),
                _ResellerPeriodRow(
                  label: 'This year',
                  data: (overview['reseller_payments'] as Map?)?['annual']
                      as Map<String, dynamic>?,
                ),
                if (resellerPoints.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Chart period breakdown',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  ...resellerPoints.whereType<Map>().map((p) {
                    final m = Map<String, dynamic>.from(p);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '${m['period_label']}: ₱${_fmtNum(m['total_paid'])} '
                        '(${m['payment_count']} payments)',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Chart period',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<String>(
                    segments: _granularityLabels.entries
                        .map(
                          (e) => ButtonSegment<String>(
                            value: e.key,
                            label: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: Text(e.value),
                            ),
                          ),
                        )
                        .toList(),
                    selected: {_granularity},
                    onSelectionChanged: (s) {
                      setState(() => _granularity = s.first);
                      _load();
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _KpiGrid(
            children: [
              _KpiCard(
                label: 'Net revenue',
                value:
                    '₱${_fmtNum(salesSummary['net_revenue'] ?? salesSummary['sales'] ?? salesSummary['gross_sales'] ?? 0)}',
                icon: Icons.payments_outlined,
              ),
              _KpiCard(
                label: 'Refunds',
                value: '₱${_fmtNum(salesSummary['refunds'] ?? 0)}',
                icon: Icons.money_off_outlined,
              ),
              _KpiCard(
                label: 'Bookings',
                value: '${salesSummary['bookings'] ?? 0}',
                icon: Icons.book_online_outlined,
              ),
              _KpiCard(
                label: 'Room transfers',
                value: '${transferSummary['count'] ?? 0}',
                icon: Icons.swap_horiz_outlined,
              ),
              _KpiCard(
                label: 'Task completion',
                value: '${taskSummary['completion_rate'] ?? 0}%',
                icon: Icons.task_alt_outlined,
              ),
            ],
          ),
          const SizedBox(height: 16),
          AppSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Occupancy',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Booked ${_occupancy?['booked_rooms'] ?? 0} / ${_occupancy?['total_rooms'] ?? 0} rooms',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  '${_occupancy?['occupancy_rate'] ?? 0}% occupancy',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _SectionTitle('Revenue by period'),
          const SizedBox(height: 10),
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
          const SizedBox(height: 20),
          _SectionTitle('Bookings count'),
          const SizedBox(height: 10),
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
          const SizedBox(height: 20),
          _SectionTitle('Activity volume'),
          const SizedBox(height: 10),
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
          const SizedBox(height: 20),
          _PaidTransactionsPanel(
            key: ValueKey('tx-$_granularity-$reportFrom-$reportTo'),
            granularity: _granularity,
            from: reportFrom,
            to: reportTo,
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
          color: scheme.outlineVariant.withValues(alpha: 0.5),
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
            reservedSize: 48,
            getTitlesWidget: (v, _) => Text(
              v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : v.toInt().toString(),
              style: const TextStyle(fontSize: 10),
            ),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 32,
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
          color: scheme.outlineVariant.withValues(alpha: 0.45),
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
            reservedSize: 32,
            getTitlesWidget: (v, _) => Text(
              v.toInt().toString(),
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
              if (i < 0 || i >= n) return const SizedBox.shrink();
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
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: scheme.tertiary,
          barWidth: 3,
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(
            show: true,
            color: scheme.tertiary.withValues(alpha: 0.12),
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
          color: scheme.outlineVariant.withValues(alpha: 0.45),
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
            reservedSize: 32,
            getTitlesWidget: (v, _) => Text(
              v.toInt().toString(),
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 520;
        final itemWidth = wide
            ? (constraints.maxWidth - 24) / 3
            : (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: children
              .map((c) => SizedBox(width: itemWidth, child: c))
              .toList(),
        );
      },
    );
  }
}

class _PaidTransactionsPanel extends StatefulWidget {
  const _PaidTransactionsPanel({
    super.key,
    required this.granularity,
    required this.from,
    required this.to,
  });

  final String granularity;
  final String from;
  final String to;

  @override
  State<_PaidTransactionsPanel> createState() => _PaidTransactionsPanelState();
}

class _PaidTransactionsPanelState extends State<_PaidTransactionsPanel> {
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  String? _error;
  int _page = 1;
  int _lastPage = 1;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _PaidTransactionsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.granularity != widget.granularity ||
        oldWidget.from != widget.from ||
        oldWidget.to != widget.to) {
      _page = 1;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await portalDio().get<Map<String, dynamic>>(
        '/reports/paid-transactions',
        queryParameters: {
          'granularity': widget.granularity,
          if (widget.from.isNotEmpty) 'from': widget.from,
          if (widget.to.isNotEmpty) 'to': widget.to,
          'page': _page,
          'per_page': 15,
        },
      );
      final meta = res.data?['meta'] as Map<String, dynamic>? ?? {};
      final data = (res.data?['data'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      setState(() {
        _rows = data;
        _page = (meta['current_page'] as num?)?.toInt() ?? _page;
        _lastPage = (meta['last_page'] as num?)?.toInt() ?? 1;
        _total = (meta['total'] as num?)?.toInt() ?? data.length;
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
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle('Paid transactions'),
        const SizedBox(height: 6),
        Text(
          _total > 0 ? '$_total transaction(s) in selected period' : 'No transactions',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 10),
        AppSectionCard(
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              : _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: _load,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : _rows.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('No paid transactions in selected range.'),
                        )
                      : Column(
                          children: [
                            ..._rows.map((txn) => _TransactionTile(txn: txn)),
                            if (_lastPage > 1) ...[
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    tooltip: 'Previous page',
                                    onPressed: _page > 1
                                        ? () {
                                            setState(() => _page -= 1);
                                            _load();
                                          }
                                        : null,
                                    icon: const Icon(Icons.chevron_left),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12),
                                    child: Text(
                                      'Page $_page of $_lastPage',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Next page',
                                    onPressed: _page < _lastPage
                                        ? () {
                                            setState(() => _page += 1);
                                            _load();
                                          }
                                        : null,
                                    icon: const Icon(Icons.chevron_right),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
        ),
      ],
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.txn});

  final Map<String, dynamic> txn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final line = (txn['line'] ?? '').toString();
    final amount =
        ((txn['amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2);
    final method = (txn['payment_method'] ?? '').toString().trim();
    final channelRaw = (txn['payment_channel'] ?? '').toString().trim();
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
    final guest = (txn['guest_name'] ?? '').toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.receipt_long_outlined, color: scheme.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.isEmpty ? 'Transaction' : line,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                if (guest.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Guest: $guest',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (payBits.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    payBits.join(' · '),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '₱$amount',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _PeriodFinanceRow extends StatelessWidget {
  const _PeriodFinanceRow({required this.label, this.data});

  final String label;
  final Map<String, dynamic>? data;

  @override
  Widget build(BuildContext context) {
    final revenue = (data?['gross_revenue'] ?? data?['revenue'] ?? 0);
    final refunds = (data?['refunds'] ?? 0);
    final reseller = (data?['reseller_commissions_paid'] ?? 0);
    final expenses = (data?['expenses'] ?? data?['refund_expense'] ?? 0);
    final net = (data?['profit'] ?? data?['net_revenue'] ?? revenue);
    final grossNet =
        (data?['profit_before_reseller_payouts'] ?? data?['net_revenue'] ?? revenue);
    final bookings = data?['bookings'] ?? 0;
    final amenity = (data?['amenity_revenue'] ?? 0);
    final room = (data?['room_revenue'] ?? 0);
    final transfers = (data?['transfer_adjustments'] ?? 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 10),
        _MetricLine(label: 'Gross revenue', value: '₱${_AdminReportsScreenState._fmtNum(revenue)}'),
        _MetricLine(label: 'Room revenue', value: '₱${_AdminReportsScreenState._fmtNum(room)}'),
        _MetricLine(label: 'Amenity revenue', value: '₱${_AdminReportsScreenState._fmtNum(amenity)}'),
        _MetricLine(label: 'Transfer adjustments', value: '₱${_AdminReportsScreenState._fmtNum(transfers)}'),
        const SizedBox(height: 6),
        _MetricLine(label: 'Refunds', value: '₱${_AdminReportsScreenState._fmtNum(refunds)}'),
        _MetricLine(label: 'Reseller payouts', value: '₱${_AdminReportsScreenState._fmtNum(reseller)}'),
        _MetricLine(label: 'Total expenses', value: '₱${_AdminReportsScreenState._fmtNum(expenses)}'),
        const SizedBox(height: 6),
        _MetricLine(
          label: 'Net before resellers',
          value: '₱${_AdminReportsScreenState._fmtNum(grossNet)}',
          emphasized: true,
        ),
        _MetricLine(
          label: 'Net profit',
          value: '₱${_AdminReportsScreenState._fmtNum(net)}',
          emphasized: true,
        ),
        const SizedBox(height: 4),
        Text(
          '$bookings paid booking(s)',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _MetricLine extends StatelessWidget {
  const _MetricLine({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: emphasized
                  ? Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      )
                  : Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResellerPeriodRow extends StatelessWidget {
  const _ResellerPeriodRow({required this.label, this.data});

  final String label;
  final Map<String, dynamic>? data;

  @override
  Widget build(BuildContext context) {
    final total = (data?['total_paid'] ?? 0);
    final count = data?['payment_count'] ?? 0;
    final resellers = data?['unique_resellers'] ?? 0;
    final byCat = data?['by_category'] as Map<String, dynamic>? ?? {};

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          _MetricLine(
            label: 'Total paid',
            value: '₱${_AdminReportsScreenState._fmtNum(total)}',
          ),
          _MetricLine(label: 'Payments', value: '$count'),
          _MetricLine(label: 'Resellers', value: '$resellers'),
          if (byCat.isNotEmpty) ...[
            const SizedBox(height: 4),
            _MetricLine(
              label: 'Taxi',
              value: '₱${_AdminReportsScreenState._fmtNum(byCat['taxi'] ?? 0)}',
            ),
            _MetricLine(
              label: 'Motorcycle',
              value: '₱${_AdminReportsScreenState._fmtNum(byCat['motorcycle'] ?? 0)}',
            ),
            _MetricLine(
              label: 'Individual',
              value: '₱${_AdminReportsScreenState._fmtNum(byCat['individual'] ?? 0)}',
            ),
          ],
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
    final scheme = Theme.of(context).colorScheme;
    return AppSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: scheme.primary, size: 22),
          const SizedBox(height: 10),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}
