import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../dio_client.dart';
import '../../../widgets/admin_month_calendar.dart';
import '../../../widgets/app_scaffold.dart';
import '../../../widgets/app_state_views.dart';

/// Reseller commission payouts calendar + totals.
class ResellerCommissionsReportScreen extends StatefulWidget {
  const ResellerCommissionsReportScreen({super.key});

  @override
  State<ResellerCommissionsReportScreen> createState() =>
      _ResellerCommissionsReportScreenState();
}

class _ResellerCommissionsReportScreenState
    extends State<ResellerCommissionsReportScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selected = DateUtils.dateOnly(DateTime.now());
  Map<String, double> _byDay = {};
  Map<String, dynamic>? _overview;
  bool _loading = true;
  String? _error;

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

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
      final start = DateTime(_month.year, _month.month, 1);
      final end = DateTime(_month.year, _month.month + 1, 0);
      final res = await portalDio().get<Map<String, dynamic>>(
        '/reports/reseller-payments/timeseries',
        queryParameters: {
          'granularity': 'day',
          'from': _fmt(start),
          'to': _fmt(end),
        },
      );
      final profit = await portalDio().get<Map<String, dynamic>>(
        '/reports/profit-overview',
        queryParameters: {'anchor_date': _fmt(_selected)},
      );
      final points = (res.data?['points'] as List?) ?? [];
      final byDay = <String, double>{};
      for (final raw in points) {
        if (raw is! Map) continue;
        final label = (raw['period_label'] ?? '').toString();
        if (label.isEmpty) continue;
        byDay[label] =
            ((raw['total_paid'] as num?)?.toDouble() ?? 0).toDouble();
      }
      if (!mounted) return;
      setState(() {
        _byDay = byDay;
        _overview = profit.data;
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
    final dayTotal = _byDay[_fmt(_selected)] ?? 0.0;
    final periods = (_overview?['periods'] as Map?) ?? {};
    return AppScaffold(
      appBar: AppBar(
        title: const Text('Reseller commissions'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const AppLoadingView()
          : _error != null
              ? AppErrorView(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    Text(
                      'Selected day: ₱${dayTotal.toStringAsFixed(2)}',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 12),
                    AdminMonthCalendar(
                      focusedMonth: _month,
                      selectedDay: _selected,
                      hasEvent: (d) => (_byDay[_fmt(d)] ?? 0) > 0,
                      eventCount: (d) =>
                          ((_byDay[_fmt(d)] ?? 0) > 0) ? 1 : 0,
                      onMonthChanged: (m) {
                        setState(() => _month = m);
                        _load();
                      },
                      onDaySelected: (d) {
                        setState(() => _selected = d);
                        _load();
                      },
                    ),
                    const SizedBox(height: 16),
                    ...['daily', 'weekly', 'monthly', 'annual'].map((key) {
                      final row = periods[key];
                      final paid = row is Map
                          ? ((row['reseller_commissions_paid'] as num?)
                                  ?.toDouble() ??
                              (row['reseller_payments'] as num?)?.toDouble() ??
                              0)
                          : 0.0;
                      return Card(
                        child: ListTile(
                          title: Text(key[0].toUpperCase() + key.substring(1)),
                          trailing: Text(
                            '₱${paid.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
    );
  }
}
