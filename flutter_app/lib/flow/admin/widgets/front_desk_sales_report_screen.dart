import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';

import '../../../dio_client.dart';
import '../../../utils/money_format.dart';
import '../../../widgets/admin_month_calendar.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/app_scaffold.dart';
import '../../../widgets/app_state_views.dart';

/// Frontdesk sales: account list → period / calendar day drill-down.
class FrontDeskSalesReportScreen extends StatefulWidget {
  const FrontDeskSalesReportScreen({super.key});

  @override
  State<FrontDeskSalesReportScreen> createState() =>
      _FrontDeskSalesReportScreenState();
}

class _FrontDeskSalesReportScreenState extends State<FrontDeskSalesReportScreen> {
  String _granularity = 'day';
  DateTime _anchor = DateUtils.dateOnly(DateTime.now());
  Map<String, dynamic>? _summary;
  bool _loading = true;
  String? _error;

  static const _labels = {
    'day': 'Daily',
    'week': 'Weekly',
    'month': 'Monthly',
    'year': 'Annual',
  };

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
      final res = await portalDio().get<Map<String, dynamic>>(
        '/reports/frontdesk-sales/summary',
        queryParameters: {
          'granularity': _granularity,
          'anchor_date': _fmt(_anchor),
        },
      );
      if (!mounted) return;
      setState(() {
        _summary = res.data;
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
        title: const Text('Front desk sales'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) return const AppLoadingView();
    if (_error != null) return AppErrorView(message: _error!, onRetry: _load);

    final totals = (_summary?['totals'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final accounts = (_summary?['accounts'] as List?) ?? const [];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Sales by front desk account',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap an account to open daily / weekly / monthly / annual detail and a sales calendar.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _labels.entries.map((e) {
              return ChoiceChip(
                label: Text(e.value),
                selected: _granularity == e.key,
                onSelected: (_) {
                  setState(() => _granularity = e.key);
                  _load();
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Anchor date'),
            subtitle: Text(_fmt(_anchor)),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 1)),
                initialDate: _anchor,
              );
              if (picked == null) return;
              setState(() => _anchor = DateUtils.dateOnly(picked));
              await _load();
            },
          ),
          AppSectionCard(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: _Metric(
                      label: 'Product sales',
                      value:
                          '₱${parseJsonDouble(totals['sales']).toStringAsFixed(2)}',
                    ),
                  ),
                  Expanded(
                    child: _Metric(
                      label: 'Payments',
                      value:
                          '₱${parseJsonDouble(totals['payments']).toStringAsFixed(2)}',
                    ),
                  ),
                  Expanded(
                    child: _Metric(
                      label: 'Orders',
                      value: '${totals['order_count'] ?? 0}',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (accounts.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.person_outline),
                title: Text('No front desk accounts found.'),
              ),
            ),
          ...accounts.map((raw) {
            final row = Map<String, dynamic>.from(raw as Map);
            final name = (row['username'] ?? 'Front desk').toString();
            final sales = parseJsonDouble(row['total_sales']);
            final orders = row['order_count'] ?? 0;
            return Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.badge_outlined)),
                title: Text(name),
                subtitle: Text(
                  'Amenities ₱${parseJsonDouble(row['amenity_sales']).toStringAsFixed(2)}'
                  ' · Manual ₱${parseJsonDouble(row['manual_sales']).toStringAsFixed(2)}'
                  ' · $orders orders',
                ),
                trailing: Text(
                  '₱${sales.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => _FrontDeskAccountSalesScreen(
                        userId: (row['user_id'] ?? '').toString(),
                        username: name,
                        initialGranularity: _granularity,
                        initialAnchor: _anchor,
                      ),
                    ),
                  );
                },
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _FrontDeskAccountSalesScreen extends StatefulWidget {
  const _FrontDeskAccountSalesScreen({
    required this.userId,
    required this.username,
    required this.initialGranularity,
    required this.initialAnchor,
  });

  final String userId;
  final String username;
  final String initialGranularity;
  final DateTime initialAnchor;

  @override
  State<_FrontDeskAccountSalesScreen> createState() =>
      _FrontDeskAccountSalesScreenState();
}

class _FrontDeskAccountSalesScreenState
    extends State<_FrontDeskAccountSalesScreen> {
  late DateTime _month;
  Map<String, dynamic>? _calendar;
  Map<String, dynamic>? _dayDetail;
  DateTime? _selectedDay;
  bool _loading = true;
  bool _loadingDay = false;
  String? _error;

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _month = DateTime(widget.initialAnchor.year, widget.initialAnchor.month);
    _selectedDay = widget.initialAnchor;
    _loadCalendar();
  }

  Future<void> _loadCalendar() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await portalDio().get<Map<String, dynamic>>(
        '/reports/frontdesk-sales/calendar',
        queryParameters: {
          'user_id': widget.userId,
          'month': _fmt(_month),
        },
      );
      if (!mounted) return;
      setState(() {
        _calendar = res.data;
        _loading = false;
      });
      if (_selectedDay != null) {
        await _loadDay(_selectedDay!);
      }
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = dioErrorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _loadDay(DateTime day) async {
    setState(() {
      _selectedDay = DateUtils.dateOnly(day);
      _loadingDay = true;
    });
    try {
      final res = await portalDio().get<Map<String, dynamic>>(
        '/reports/frontdesk-sales/day',
        queryParameters: {
          'user_id': widget.userId,
          'date': _fmt(day),
        },
      );
      if (!mounted) return;
      setState(() {
        _dayDetail = res.data;
        _loadingDay = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _loadingDay = false);
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  Map<String, double> _salesByDay() {
    final days = (_calendar?['days'] as List?) ?? const [];
    final map = <String, double>{};
    for (final raw in days) {
      if (raw is! Map) continue;
      final date = (raw['date'] ?? '').toString();
      if (date.isEmpty) continue;
      map[date] = parseJsonDouble(raw['total_sales']);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final byDay = _salesByDay();
    final summary =
        (_dayDetail?['summary'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
    final transactions = (_dayDetail?['transactions'] as List?) ?? const [];

    return AppScaffold(
      appBar: AppBar(title: Text(widget.username)),
      body: _loading
          ? const AppLoadingView()
          : _error != null
              ? AppErrorView(message: _error!, onRetry: _loadCalendar)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Sales calendar',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tap a day to see product charges and payments recorded by this front desk account.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    AdminMonthCalendar(
                      focusedMonth: _month,
                      selectedDay: _selectedDay ?? DateUtils.dateOnly(DateTime.now()),
                      hasEvent: (day) {
                        final key = _fmt(day);
                        return (byDay[key] ?? 0) > 0;
                      },
                      eventCount: (day) {
                        final key = _fmt(day);
                        final v = byDay[key] ?? 0;
                        return v > 0 ? 1 : 0;
                      },
                      onMonthChanged: (m) {
                        setState(() => _month = m);
                        _loadCalendar();
                      },
                      onDaySelected: _loadDay,
                    ),
                    const SizedBox(height: 16),
                    if (_selectedDay != null) ...[
                      Text(
                        'Sales on ${_fmt(_selectedDay!)}',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      const SizedBox(height: 8),
                      if (_loadingDay)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else ...[
                        AppSectionCard(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _Metric(
                                    label: 'Sales',
                                    value:
                                        '₱${parseJsonDouble(summary['total_sales']).toStringAsFixed(2)}',
                                  ),
                                ),
                                Expanded(
                                  child: _Metric(
                                    label: 'Payments',
                                    value:
                                        '₱${parseJsonDouble(summary['payments_collected']).toStringAsFixed(2)}',
                                  ),
                                ),
                                Expanded(
                                  child: _Metric(
                                    label: 'Orders',
                                    value: '${summary['order_count'] ?? 0}',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (transactions.isEmpty)
                          const Card(
                            child: ListTile(
                              title: Text('No sales recorded on this day.'),
                            ),
                          ),
                        ...transactions.map((raw) {
                          final tx = Map<String, dynamic>.from(raw as Map);
                          final complimentary = tx['complimentary'] == true;
                          final amount = parseJsonDouble(tx['amount']);
                          return Card(
                            child: ListTile(
                              title: Text((tx['label'] ?? tx['type'] ?? 'Charge')
                                  .toString()),
                              subtitle: Text(
                                '${(tx['type'] ?? '').toString()}'
                                '${complimentary ? ' · Complimentary' : ''}',
                              ),
                              trailing: Text(
                                complimentary
                                    ? 'Free'
                                    : '₱${amount.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ],
                  ],
                ),
    );
  }
}
