import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../dio_client.dart';
import '../../../widgets/admin_month_calendar.dart';

/// Sales calendar + daily/weekly/monthly/annual summary for admin tabs.
class AdminSalesPanel extends StatefulWidget {
  const AdminSalesPanel({super.key});

  @override
  State<AdminSalesPanel> createState() => _AdminSalesPanelState();
}

class _AdminSalesPanelState extends State<AdminSalesPanel> {
  DateTime _selected = DateUtils.dateOnly(DateTime.now());
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  Map<String, dynamic>? _daySales;
  Map<String, dynamic>? _overview;
  Set<String> _eventDays = {};
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final from = DateTime(_month.year, _month.month, 1);
      final to = DateTime(_month.year, _month.month + 1, 0);
      final sales = await portalDio().get<Map<String, dynamic>>(
        '/reports/sales/timeseries',
        queryParameters: {
          'granularity': 'day',
          'from': _fmt(from),
          'to': _fmt(to),
        },
      );
      final overview = await portalDio().get<Map<String, dynamic>>(
        '/reports/profit-overview',
        queryParameters: {'anchor_date': _fmt(_selected)},
      );
      final points = (sales.data?['points'] as List?) ?? [];
      final markers = <String>{};
      for (final p in points) {
        if (p is! Map) continue;
        final label = (p['period_label'] ?? '').toString();
        if (label.isNotEmpty) markers.add(label);
      }
      Map<String, dynamic>? dayPoint;
      final sel = _fmt(_selected);
      for (final p in points) {
        if (p is Map && (p['period_label'] ?? '').toString() == sel) {
          dayPoint = Map<String, dynamic>.from(p);
          break;
        }
      }
      if (!mounted) return;
      setState(() {
        _eventDays = markers;
        _daySales = dayPoint;
        _overview = overview.data;
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(dioErrorMessage(e))));
    }
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final overview = _overview ?? {};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        AdminMonthCalendar(
          focusedMonth: _month,
          selectedDay: _selected,
          hasEvent: (d) => _eventDays.contains(_fmt(d)),
          onDaySelected: (d) {
            setState(() => _selected = d);
            _loadAll();
          },
          onMonthChanged: (m) {
            setState(() => _month = m);
            _loadAll();
          },
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sales on ${_fmt(_selected)}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  '₱${(_daySales?['gross_sales'] ?? 0).toString()}',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
                Text(
                  '${_daySales?['booking_count'] ?? 0} paid booking(s)',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Sales summary',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        _SummaryRow(
          label: 'Daily',
          data: overview['daily'] as Map<String, dynamic>?,
        ),
        _SummaryRow(
          label: 'Weekly',
          data: overview['weekly'] as Map<String, dynamic>?,
        ),
        _SummaryRow(
          label: 'Monthly',
          data: overview['monthly'] as Map<String, dynamic>?,
        ),
        _SummaryRow(
          label: 'Annual',
          data: overview['annual'] as Map<String, dynamic>?,
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, this.data});
  final String label;
  final Map<String, dynamic>? data;

  @override
  Widget build(BuildContext context) {
    final net = (data?['net_revenue'] ?? data?['gross_revenue'] ?? 0).toString();
    final bookings = '${data?['bookings'] ?? 0}';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(label),
        subtitle: Text('$bookings booking(s)'),
        trailing: Text(
          '₱$net',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
