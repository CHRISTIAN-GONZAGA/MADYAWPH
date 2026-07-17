import 'package:dio/dio.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dio_client.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/app_card.dart';
import '../widgets/app_state_views.dart';
import '../widgets/admin_month_calendar.dart';
import 'admin/widgets/admin_dev_error_panel.dart';
import 'admin/widgets/admin_reports_ui.dart';
import 'admin/widgets/amenities_report_screen.dart';
import 'admin/widgets/front_desk_sales_report_screen.dart';
import 'admin/widgets/hotel_period_report_screen.dart';
import 'admin/widgets/reseller_commissions_report_screen.dart';
import 'admin/widgets/room_insights_report_screen.dart';

/// Revenue and operations charts with daily / weekly / monthly / annual granularity.
class AdminReportsLegacyScreen extends StatefulWidget {
  const AdminReportsLegacyScreen({
    super.key,
    this.embedded = false,
    this.isFrontDesk = false,
  });

  final bool embedded;
  final bool isFrontDesk;

  @override
  State<AdminReportsLegacyScreen> createState() =>
      _AdminReportsLegacyScreenState();
}

class _AdminReportsLegacyScreenState extends State<AdminReportsLegacyScreen> {
  Map<String, dynamic>? _sales;
  Map<String, dynamic>? _timeline;
  Map<String, dynamic>? _transfers;
  Map<String, dynamic>? _tasks;
  Map<String, dynamic>? _occupancy;
  Map<String, dynamic>? _profitOverview;
  Map<String, dynamic>? _resellerPayments;
  String? _resellerPaymentsError;
  String? _resellerSectionError;
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  String _granularity = 'week';
  DateTime _selectedDay = DateUtils.dateOnly(DateTime.now());
  DateTime _commissionMonth =
      DateTime(DateTime.now().year, DateTime.now().month);
  Map<String, double> _commissionByDay = {};

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

  String _fmtDay(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static Map<String, dynamic>? _asStringKeyedMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  bool _hasAnyReportData() {
    return _sales != null ||
        _timeline != null ||
        _transfers != null ||
        _tasks != null ||
        _occupancy != null ||
        _profitOverview != null ||
        _resellerPayments != null;
  }

  Future<Map<String, dynamic>?> _safeReportGet(
    String path, {
    Map<String, dynamic>? queryParameters,
    void Function(String message)? onError,
  }) async {
    try {
      final res = await portalDio().get<Map<String, dynamic>>(
        path,
        queryParameters: queryParameters,
      );
      return res.data;
    } on DioException catch (e) {
      onError?.call(dioErrorMessage(e));
      return null;
    } catch (e, stack) {
      onError?.call(AdminDevErrorPanel.formatError(e, stack));
      return null;
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent || _profitOverview == null) {
      setState(() {
        if (!silent) {
          _loading = true;
        } else {
          _refreshing = true;
        }
        _error = null;
        _resellerPaymentsError = null;
        _resellerSectionError = null;
      });
    } else {
      setState(() => _refreshing = true);
    }
    try {
      final monthStart = DateTime(_commissionMonth.year, _commissionMonth.month, 1);
      final monthEnd = DateTime(_commissionMonth.year, _commissionMonth.month + 1, 0);
      final qp = {'granularity': _granularity};
      final commissionQp = {
        'granularity': 'day',
        'from': _fmtDay(monthStart),
        'to': _fmtDay(monthEnd),
      };
      final failures = <String>[];
      String? resellerPaymentsError;

      // Load core KPIs first so the screen can paint sooner.
      final primary = await Future.wait<Map<String, dynamic>?>([
        _safeReportGet('/reports/sales/timeseries', queryParameters: qp),
        _safeReportGet(
          '/reports/profit-overview',
          queryParameters: {'anchor_date': _fmtDay(_selectedDay)},
        ),
        _safeReportGet('/reports/room-occupancy'),
      ]);
      if (mounted) {
        setState(() {
          if (primary[0] != null) _sales = primary[0];
          if (primary[1] != null) _profitOverview = primary[1];
          if (primary[2] != null) _occupancy = primary[2];
          if (!silent) _loading = false;
        });
      }

      final secondary = await Future.wait<Map<String, dynamic>?>([
        _safeReportGet('/reports/activity/timeline', queryParameters: qp),
        _safeReportGet('/reports/transfers'),
        _safeReportGet('/reports/tasks/performance'),
        _safeReportGet(
          '/reports/reseller-payments/timeseries',
          queryParameters: commissionQp,
          onError: (message) => resellerPaymentsError = message,
        ),
      ]);

      final sales = primary[0];
      if (sales == null) failures.add('sales');
      final profitOverview = primary[1];
      if (profitOverview == null) failures.add('profit overview');
      final occupancy = primary[2];
      if (occupancy == null) failures.add('occupancy');
      final timeline = secondary[0];
      if (timeline == null) failures.add('activity');
      final transfers = secondary[1];
      if (transfers == null) failures.add('transfers');
      final tasks = secondary[2];
      if (tasks == null) failures.add('tasks');
      final resellerPayments = secondary[3];
      if (resellerPayments == null && resellerPaymentsError == null) {
        resellerPaymentsError =
            'Reseller commissions request returned no data.';
      }
      if (resellerPayments == null) failures.add('reseller commissions');

      final commissionPoints =
          (resellerPayments?['points'] as List<dynamic>?) ?? const [];
      final byDay = <String, double>{};
      String? resellerSectionError;
      try {
        for (final raw in commissionPoints) {
          if (raw is! Map) continue;
          final label = (raw['period_label'] ?? '').toString();
          if (label.isEmpty) continue;
          byDay[label] = _parseAmount(raw['total_paid']);
        }
      } catch (e, stack) {
        resellerSectionError = AdminDevErrorPanel.formatError(e, stack);
      }
      if (!mounted) return;
      setState(() {
        if (sales != null) _sales = sales;
        if (timeline != null) _timeline = timeline;
        if (transfers != null) _transfers = transfers;
        if (tasks != null) _tasks = tasks;
        if (occupancy != null) _occupancy = occupancy;
        if (profitOverview != null) _profitOverview = profitOverview;
        if (resellerPayments != null) _resellerPayments = resellerPayments;
        _commissionByDay = byDay;
        _resellerPaymentsError = resellerPaymentsError;
        _resellerSectionError = resellerSectionError;
        if (resellerSectionError == null) {
          try {
            _validateResellerSectionData(
              overview: profitOverview ?? _profitOverview,
              resellerPay: resellerPayments ?? _resellerPayments,
            );
          } catch (e, stack) {
            _resellerSectionError = AdminDevErrorPanel.formatError(e, stack);
          }
        }
        _loading = false;
        _refreshing = false;
        if (failures.isNotEmpty && _profitOverview == null && _sales == null) {
          _error =
              'Could not load reports (${failures.join(', ')}). Pull to retry.';
        } else if (failures.isNotEmpty) {
          _error =
              'Some report sections failed to load (${failures.join(', ')}). Showing available data.';
        } else {
          _error = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
        _refreshing = false;
      });
    }
  }

  void _copyReportForPrint(BuildContext context, String body) {
    Clipboard.setData(ClipboardData(text: body));
    showAppMessage(context, 'Report copied. Paste into any app to print or share.');
  }

  void _openPrintableReport(
    BuildContext context, {
    required String title,
    required String printBody,
    required Widget child,
  }) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (ctx) => _ReportPrintableScreen(
          title: title,
          printBody: printBody,
          onPrint: () => _copyReportForPrint(ctx, printBody),
          child: child,
        ),
      ),
    );
  }

  void _openFinancePeriod(
    BuildContext context, {
    required String buttonLabel,
    required String periodKey,
  }) {
    final range = _rangeForPeriod(periodKey, _selectedDay);
    openHotelPeriodReport(
      context: context,
      timeIn: range.start,
      timeOut: range.end,
      title: '$buttonLabel revenue',
      subtitle: 'Hotel-wide report (not tied to front desk shifts)',
    );
  }

  ({DateTime start, DateTime end}) _rangeForPeriod(
    String periodKey,
    DateTime anchor,
  ) {
    switch (periodKey) {
      case 'weekly':
        final start = anchor.subtract(Duration(days: anchor.weekday - 1));
        final end = start.add(const Duration(days: 6));
        return (
          start: DateTime(start.year, start.month, start.day),
          end: DateTime(end.year, end.month, end.day, 23, 59, 59),
        );
      case 'monthly':
        return (
          start: DateTime(anchor.year, anchor.month, 1),
          end: DateTime(anchor.year, anchor.month + 1, 0, 23, 59, 59),
        );
      case 'annual':
        return (
          start: DateTime(anchor.year, 1, 1),
          end: DateTime(anchor.year, 12, 31, 23, 59, 59),
        );
      case 'daily':
      default:
        return (
          start: DateTime(anchor.year, anchor.month, anchor.day),
          end: DateTime(anchor.year, anchor.month, anchor.day, 23, 59, 59),
        );
    }
  }

  void _openTimeseriesReport(
    BuildContext context, {
    required String title,
    required List<dynamic> points,
    required String emptyLabel,
    required String Function(Map<String, dynamic> point) valueLabel,
    required String Function(Map<String, dynamic> point) subtitleLabel,
  }) {
    final printBody = _formatTimeseriesPrint(
      title,
      points,
      valueLabel: valueLabel,
      subtitleLabel: subtitleLabel,
      emptyLabel: emptyLabel,
    );
    _openPrintableReport(
      context,
      title: title,
      printBody: printBody,
      child: _ReportTimeseriesList(
        points: points,
        emptyLabel: emptyLabel,
        valueLabel: valueLabel,
        subtitleLabel: subtitleLabel,
        onRowTap: (point) {
          final label = (point['period_label'] ?? 'Period').toString();
          _openPrintableReport(
            context,
            title: label,
            printBody: _formatTimeseriesPointPrint(
              title,
              point,
              valueLabel: valueLabel,
              subtitleLabel: subtitleLabel,
            ),
            child: _TimeseriesPointDetail(
              label: label,
              value: valueLabel(point),
              subtitle: subtitleLabel(point),
            ),
          );
        },
      ),
    );
  }

  void _openKpiDetail(
    BuildContext context, {
    required String label,
    required String value,
    String? detail,
  }) {
    final body = StringBuffer()
      ..writeln(label)
      ..writeln()
      ..writeln(value);
    if (detail != null && detail.isNotEmpty) {
      body
        ..writeln()
        ..writeln(detail);
    }
    _openPrintableReport(
      context,
      title: label,
      printBody: body.toString(),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            if (detail != null && detail.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(detail),
            ],
          ],
        ),
      ),
    );
  }

  static String _formatTimeseriesPrint(
    String title,
    List<dynamic> points, {
    required String Function(Map<String, dynamic> point) valueLabel,
    required String Function(Map<String, dynamic> point) subtitleLabel,
    required String emptyLabel,
  }) {
    final buf = StringBuffer()..writeln(title)..writeln();
    if (points.isEmpty) {
      buf.writeln(emptyLabel);
      return buf.toString();
    }
    for (final raw in points) {
      if (raw is! Map) continue;
      final point = Map<String, dynamic>.from(raw);
      final label = (point['period_label'] ?? 'Period').toString();
      buf.writeln('$label: ${valueLabel(point)} (${subtitleLabel(point)})');
    }
    return buf.toString();
  }

  static String _formatTimeseriesPointPrint(
    String sectionTitle,
    Map<String, dynamic> point, {
    required String Function(Map<String, dynamic> point) valueLabel,
    required String Function(Map<String, dynamic> point) subtitleLabel,
  }) {
    final label = (point['period_label'] ?? 'Period').toString();
    return '''
$sectionTitle — $label

${valueLabel(point)}
${subtitleLabel(point)}
''';
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody();
    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_refreshing) const LinearProgressIndicator(minHeight: 2),
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
                  onPressed: () => _load(silent: true),
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
          IconButton(onPressed: () => _load(silent: true), icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          if (_refreshing) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _profitOverview == null) {
      return RefreshIndicator(
        onRefresh: () => _load(silent: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(16, widget.embedded ? 8 : 16, 16, 32),
          children: const [
            SizedBox(height: 220, child: AppLoadingView()),
          ],
        ),
      );
    }
    if (_error != null && !_hasAnyReportData()) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(16, widget.embedded ? 8 : 16, 16, 32),
          children: [
            SizedBox(
              height: 280,
              child: AppErrorView(message: _error!, onRetry: _load),
            ),
          ],
        ),
      );
    }
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
    final resellerOverview =
        _asStringKeyedMap(overview['reseller_payments']);
    final monthDaysWithPayouts = resellerPoints.where((raw) {
      if (raw is! Map) return false;
      return _parseAmount(raw['total_paid']) > 0;
    }).toList();
    final selectedDayCommission =
        _commissionByDay[_fmtDay(_selectedDay)] ?? 0.0;
    final isToday = DateUtils.isSameDay(_selectedDay, DateTime.now());
    final reportFrom = (_sales?['from'] ?? '').toString();
    final reportTo = (_sales?['to'] ?? '').toString();

    return RefreshIndicator(
      onRefresh: () => _load(silent: true),
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, widget.embedded ? 8 : 16, 16, 32),
        children: [
          if (_error != null && _hasAnyReportData()) ...[
            Card(
              color: scheme.errorContainer.withValues(alpha: 0.35),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _error!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onErrorContainer,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (!widget.embedded)
            ReportsHeroHeader(
              selectedDateLabel: isToday
                  ? 'Today · ${_fmtDay(_selectedDay)}'
                  : _fmtDay(_selectedDay),
              onRefresh: () => _load(silent: true),
              isRefreshing: _refreshing,
            ),
          if (!widget.embedded) const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.point_of_sale_outlined),
              title: const Text('Front desk sales reports'),
              subtitle: const Text(
                'Daily, weekly, monthly, and annual sales by front desk account, with calendar drill-down.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const FrontDeskSalesReportScreen(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          if (reportFrom.isNotEmpty || reportTo.isNotEmpty) ...[
            ReportsDataRangeBanner(
              from: reportFrom,
              to: reportTo,
              granularityLabel:
                  _granularityLabels[_granularity] ?? _granularity,
            ),
            const SizedBox(height: 16),
          ],
          ReportsSection(
            title: 'Financial overview',
            subtitle: isToday
                ? 'Today (${_fmtDay(_selectedDay)})'
                : 'Selected: ${_fmtDay(_selectedDay)}',
            icon: Icons.account_balance_wallet_outlined,
            accent: scheme.primary,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final tileWidth = (constraints.maxWidth - 12) / 2;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: tileWidth,
                      child: ReportsPeriodTile(
                        label: 'Daily',
                        subtitle: _fmtDay(_selectedDay),
                        icon: Icons.today_outlined,
                        accent: scheme.primary,
                        onTap: () => _openFinancePeriod(
                          context,
                          buttonLabel: 'Daily',
                          periodKey: 'daily',
                        ),
                      ),
                    ),
                    SizedBox(
                      width: tileWidth,
                      child: ReportsPeriodTile(
                        label: 'Weekly',
                        subtitle: 'This week',
                        icon: Icons.date_range_outlined,
                        accent: scheme.tertiary,
                        onTap: () => _openFinancePeriod(
                          context,
                          buttonLabel: 'Weekly',
                          periodKey: 'weekly',
                        ),
                      ),
                    ),
                    SizedBox(
                      width: tileWidth,
                      child: ReportsPeriodTile(
                        label: 'Monthly',
                        subtitle: 'This month',
                        icon: Icons.calendar_month_outlined,
                        accent: scheme.secondary,
                        onTap: () => _openFinancePeriod(
                          context,
                          buttonLabel: 'Monthly',
                          periodKey: 'monthly',
                        ),
                      ),
                    ),
                    SizedBox(
                      width: tileWidth,
                      child: ReportsPeriodTile(
                        label: 'Annual',
                        subtitle: 'This year',
                        icon: Icons.event_note_outlined,
                        accent: const Color(0xFF7C4DFF),
                        onTap: () => _openFinancePeriod(
                          context,
                          buttonLabel: 'Annual',
                          periodKey: 'annual',
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          ReportsSection(
            title: 'Commission calendar',
            subtitle:
                'Tap a date to view payouts. Daily totals reset each calendar day.',
            icon: Icons.payments_outlined,
            accent: scheme.tertiary,
            child: AdminMonthCalendar(
              focusedMonth: _commissionMonth,
              selectedDay: _selectedDay,
              hasEvent: (d) => (_commissionByDay[_fmtDay(d)] ?? 0) > 0,
              eventCount: (d) => (_commissionByDay[_fmtDay(d)] ?? 0).round(),
              onDaySelected: (d) {
                setState(() => _selectedDay = d);
                _load(silent: true);
              },
              onMonthChanged: (m) {
                setState(() => _commissionMonth = m);
                _load(silent: true);
              },
            ),
          ),
          const SizedBox(height: 16),
          ReportsSection(
            title: 'Reseller commissions',
            subtitle:
                'Selected day: ₱${_fmtNum(selectedDayCommission)} · Month: ₱${_fmtNum(_parseAmount(resellerTotals['total_paid']))}',
            icon: Icons.handshake_outlined,
            accent: const Color(0xFF00897B),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${_parseInt(resellerTotals['payment_count'])} payment(s) this month',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                if (_resellerPaymentsError != null ||
                    _resellerSectionError != null) ...[
                  const SizedBox(height: 12),
                  _InlineReportErrorPanel(
                    title: 'Reseller commissions error',
                    message: _resellerSectionError ??
                        _resellerPaymentsError ??
                        'Unknown error',
                    hint: _resellerPaymentsError != null
                        ? 'The API call failed. Check your connection or server logs.'
                        : 'The response loaded but this section could not be rendered. Copy the error below.',
                  ),
                ],
                if (_resellerSectionError == null) ...[
                  const SizedBox(height: 16),
                  _ResellerPeriodRow(
                    label: isToday ? 'Today (selected)' : 'Selected day',
                    data: _asStringKeyedMap(resellerOverview?['daily']),
                  ),
                  _ResellerPeriodRow(
                    label: 'This week',
                    data: _asStringKeyedMap(resellerOverview?['weekly']),
                  ),
                  _ResellerPeriodRow(
                    label: 'This month',
                    data: _asStringKeyedMap(resellerOverview?['monthly']),
                  ),
                  _ResellerPeriodRow(
                    label: 'This year',
                    data: _asStringKeyedMap(resellerOverview?['annual']),
                  ),
                  if (!widget.isFrontDesk) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 12),
                    Text(
                      'Record reseller payout',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Log a cash or bank payout to a partner.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 12),
                    _ResellerCommissionRecordForm(
                      onRecorded: () => _load(silent: true),
                    ),
                  ],
                  if (monthDaysWithPayouts.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text(
                      'Daily payouts this month',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 8),
                    ...monthDaysWithPayouts.map((raw) {
                      final m = Map<String, dynamic>.from(raw as Map);
                      final label = (m['period_label'] ?? '').toString();
                      final paid = _parseAmount(m['total_paid']);
                      final count = _parseInt(m['payment_count']);
                      return _MetricLine(
                        label: label.isEmpty ? 'Day' : label,
                        value:
                            '₱${_fmtNum(paid)} · $count payment${count == 1 ? '' : 's'}',
                      );
                    }),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          ReportsSection(
            title: 'Report period',
            subtitle: reportFrom.isNotEmpty && reportTo.isNotEmpty
                ? '$reportFrom → $reportTo'
                : 'Choose how charts and KPIs are grouped',
            icon: Icons.timeline_outlined,
            accent: scheme.secondary,
            child: SingleChildScrollView(
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
          ),
          const SizedBox(height: 20),
          _KpiGrid(
            children: [
              ReportsKpiTile(
                label: 'Net revenue',
                value:
                    '₱${_fmtNum(salesSummary['net_revenue'] ?? salesSummary['sales'] ?? salesSummary['gross_sales'] ?? 0)}',
                icon: Icons.payments_outlined,
                accent: scheme.primary,
                onTap: () => _openKpiDetail(
                  context,
                  label: 'Net revenue',
                  value:
                      '₱${_fmtNum(salesSummary['net_revenue'] ?? salesSummary['sales'] ?? salesSummary['gross_sales'] ?? 0)}',
                  detail:
                      'Report range: ${reportFrom.isEmpty ? '—' : reportFrom} to ${reportTo.isEmpty ? '—' : reportTo}',
                ),
              ),
              ReportsKpiTile(
                label: 'Refunds',
                value: '₱${_fmtNum(salesSummary['refunds'] ?? 0)}',
                icon: Icons.money_off_outlined,
                accent: scheme.error,
                onTap: () => _openKpiDetail(
                  context,
                  label: 'Refunds',
                  value: '₱${_fmtNum(salesSummary['refunds'] ?? 0)}',
                ),
              ),
              ReportsKpiTile(
                label: 'Bookings',
                value: '${salesSummary['bookings'] ?? 0}',
                icon: Icons.book_online_outlined,
                accent: scheme.tertiary,
                onTap: () => _openKpiDetail(
                  context,
                  label: 'Bookings',
                  value: '${salesSummary['bookings'] ?? 0}',
                ),
              ),
              ReportsKpiTile(
                label: 'Room transfers',
                value: '${transferSummary['count'] ?? 0}',
                icon: Icons.swap_horiz_outlined,
                accent: const Color(0xFF1976D2),
                onTap: () => _openKpiDetail(
                  context,
                  label: 'Room transfers',
                  value: '${transferSummary['count'] ?? 0}',
                ),
              ),
              ReportsKpiTile(
                label: 'Task completion',
                value: '${taskSummary['completion_rate'] ?? 0}%',
                icon: Icons.task_alt_outlined,
                accent: const Color(0xFF00897B),
                onTap: () => _openKpiDetail(
                  context,
                  label: 'Task completion',
                  value: '${taskSummary['completion_rate'] ?? 0}%',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ReportsNavRow(
            title: 'Occupancy',
            subtitle:
                'Booked ${_occupancy?['booked_rooms'] ?? 0} / ${_occupancy?['total_rooms'] ?? 0} rooms · ${_occupancy?['occupancy_rate'] ?? 0}% occupancy',
            icon: Icons.hotel_outlined,
            accent: scheme.primary,
            onTap: () {
              final occ = _occupancy ?? const {};
              final body = '''
Occupancy

Booked rooms: ${occ['booked_rooms'] ?? 0} / ${occ['total_rooms'] ?? 0}
Occupancy rate: ${occ['occupancy_rate'] ?? 0}%
''';
              _openPrintableReport(
                context,
                title: 'Occupancy',
                printBody: body,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Booked ${occ['booked_rooms'] ?? 0} / ${occ['total_rooms'] ?? 0} rooms',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${occ['occupancy_rate'] ?? 0}% occupancy',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          ReportsNavRow(
            title: 'Revenue by period',
            subtitle: 'Tap to open full report and print',
            icon: Icons.trending_up_rounded,
            accent: scheme.primary,
            onTap: () => _openTimeseriesReport(
              context,
              title: 'Revenue by period',
              points: salesPoints,
              emptyLabel: 'No booking revenue in range.',
              valueLabel: (point) =>
                  '₱${_fmtNum(_parseAmount(point['gross_sales'] ?? point['net_revenue'] ?? 0))}',
              subtitleLabel: (point) =>
                  '${_parseInt(point['booking_count'])} booking(s)',
            ),
          ),
          const SizedBox(height: 10),
          _ReportTimeseriesList(
            points: salesPoints,
            emptyLabel: 'No booking revenue in range.',
            valueLabel: (point) =>
                '₱${_fmtNum(_parseAmount(point['gross_sales'] ?? point['net_revenue'] ?? 0))}',
            subtitleLabel: (point) =>
                '${_parseInt(point['booking_count'])} booking(s)',
            onRowTap: (point) {
              final label = (point['period_label'] ?? 'Period').toString();
              _openPrintableReport(
                context,
                title: label,
                printBody: _formatTimeseriesPointPrint(
                  'Revenue by period',
                  point,
                  valueLabel: (p) =>
                      '₱${_fmtNum(_parseAmount(p['gross_sales'] ?? p['net_revenue'] ?? 0))}',
                  subtitleLabel: (p) =>
                      '${_parseInt(p['booking_count'])} booking(s)',
                ),
                child: _TimeseriesPointDetail(
                  label: label,
                  value:
                      '₱${_fmtNum(_parseAmount(point['gross_sales'] ?? point['net_revenue'] ?? 0))}',
                  subtitle: '${_parseInt(point['booking_count'])} booking(s)',
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          ReportsNavRow(
            title: 'Bookings count',
            subtitle: 'Tap to open full report and print',
            icon: Icons.confirmation_number_outlined,
            accent: scheme.tertiary,
            onTap: () => _openTimeseriesReport(
              context,
              title: 'Bookings count',
              points: salesPoints,
              emptyLabel: 'No bookings in range.',
              valueLabel: (point) => '${_parseInt(point['booking_count'])}',
              subtitleLabel: (point) =>
                  '₱${_fmtNum(_parseAmount(point['gross_sales'] ?? 0))} gross',
            ),
          ),
          const SizedBox(height: 10),
          _ReportTimeseriesList(
            points: salesPoints,
            emptyLabel: 'No bookings in range.',
            valueLabel: (point) => '${_parseInt(point['booking_count'])}',
            subtitleLabel: (point) =>
                '₱${_fmtNum(_parseAmount(point['gross_sales'] ?? 0))} gross',
            onRowTap: (point) {
              final label = (point['period_label'] ?? 'Period').toString();
              _openPrintableReport(
                context,
                title: label,
                printBody: _formatTimeseriesPointPrint(
                  'Bookings count',
                  point,
                  valueLabel: (p) => '${_parseInt(p['booking_count'])}',
                  subtitleLabel: (p) =>
                      '₱${_fmtNum(_parseAmount(p['gross_sales'] ?? 0))} gross',
                ),
                child: _TimeseriesPointDetail(
                  label: label,
                  value: '${_parseInt(point['booking_count'])}',
                  subtitle:
                      '₱${_fmtNum(_parseAmount(point['gross_sales'] ?? 0))} gross',
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          ReportsNavRow(
            title: 'Activity volume',
            subtitle: 'Tap to open full report and print',
            icon: Icons.history_rounded,
            accent: const Color(0xFF1976D2),
            onTap: () => _openTimeseriesReport(
              context,
              title: 'Activity volume',
              points: timelinePoints,
              emptyLabel: 'No activity logs in range.',
              valueLabel: (point) => '${_parseInt(point['total_events'])}',
              subtitleLabel: (_) => 'events',
            ),
          ),
          const SizedBox(height: 10),
          _ReportTimeseriesList(
            points: timelinePoints,
            emptyLabel: 'No activity logs in range.',
            valueLabel: (point) => '${_parseInt(point['total_events'])}',
            subtitleLabel: (_) => 'events',
            onRowTap: (point) {
              final label = (point['period_label'] ?? 'Period').toString();
              _openPrintableReport(
                context,
                title: label,
                printBody: _formatTimeseriesPointPrint(
                  'Activity volume',
                  point,
                  valueLabel: (p) => '${_parseInt(p['total_events'])}',
                  subtitleLabel: (_) => 'events',
                ),
                child: _TimeseriesPointDetail(
                  label: label,
                  value: '${_parseInt(point['total_events'])}',
                  subtitle: 'events',
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          _PaidTransactionsPanel(
            key: ValueKey('tx-$_granularity-$reportFrom-$reportTo'),
            granularity: _granularity,
            from: reportFrom,
            to: reportTo,
            onOpenFull: (ctx, printBody, child) => _openPrintableReport(
              ctx,
              title: 'Paid transactions',
              printBody: printBody,
              child: child,
            ),
          ),
        ],
      ),
    );
  }

  void _validateResellerSectionData({
    Map<String, dynamic>? overview,
    Map<String, dynamic>? resellerPay,
  }) {
    final overviewMap = overview ?? const <String, dynamic>{};
    final resellerOverview = _asStringKeyedMap(overviewMap['reseller_payments']);
    for (final key in ['daily', 'weekly', 'monthly', 'annual']) {
      final period = _asStringKeyedMap(resellerOverview?[key]);
      if (period == null) continue;
      _parseAmount(period['total_paid']);
      _parseInt(period['payment_count']);
      _asCategoryMap(period['by_category']);
    }

    final totals = _asStringKeyedMap(resellerPay?['totals']) ?? const {};
    _parseAmount(totals['total_paid']);
    _parseInt(totals['payment_count']);

    final points = (resellerPay?['points'] as List<dynamic>?) ?? const [];
    for (final raw in points) {
      if (raw is! Map) continue;
      _parseAmount(raw['total_paid']);
      _parseInt(raw['payment_count']);
      _asCategoryMap(raw['by_category']);
    }
  }

  static double _parseAmount(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim()) ?? 0;
    return 0;
  }

  static int _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }

  static Map<String, dynamic> _asCategoryMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return {};
  }

  static String _fmtNum(Object? v) {
    final n = _parseAmount(v);
    return n.toStringAsFixed(n >= 100 ? 0 : 2);
  }
}

class _InlineReportErrorPanel extends StatelessWidget {
  const _InlineReportErrorPanel({
    required this.title,
    required this.message,
    this.hint,
  });

  final String title;
  final String message;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.error.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.bug_report_outlined, color: scheme.error, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: scheme.error,
                      ),
                ),
              ),
            ],
          ),
          if (hint != null) ...[
            const SizedBox(height: 8),
            Text(
              hint!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
          const SizedBox(height: 10),
          SelectableText(
            message,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  height: 1.35,
                ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: message.trim().isEmpty
                  ? null
                  : () {
                      Clipboard.setData(ClipboardData(text: message));
                      showAppMessage(context, 'Error copied to clipboard.');
                    },
              icon: const Icon(Icons.copy_outlined, size: 18),
              label: const Text('Copy error'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportTimeseriesList extends StatelessWidget {
  const _ReportTimeseriesList({
    required this.points,
    required this.emptyLabel,
    required this.valueLabel,
    required this.subtitleLabel,
    this.onRowTap,
  });

  final List<dynamic> points;
  final String emptyLabel;
  final String Function(Map<String, dynamic> point) valueLabel;
  final String Function(Map<String, dynamic> point) subtitleLabel;
  final void Function(Map<String, dynamic> point)? onRowTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (points.isEmpty) {
      return AppSectionCard(
        child: Text(
          emptyLabel,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
      );
    }

    final rows = points
        .whereType<Map>()
        .map((raw) => Map<String, dynamic>.from(raw))
        .toList();

    return AppSectionCard(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                (rows[i]['period_label'] ?? 'Period').toString(),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              subtitle: Text(subtitleLabel(rows[i])),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    valueLabel(rows[i]),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: scheme.primary,
                        ),
                  ),
                  if (onRowTap != null) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                  ],
                ],
              ),
              onTap: onRowTap == null ? null : () => onRowTap!(rows[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReportPrintableScreen extends StatelessWidget {
  const _ReportPrintableScreen({
    required this.title,
    required this.printBody,
    required this.onPrint,
    required this.child,
  });

  final String title;
  final String printBody;
  final VoidCallback onPrint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppScaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            onPressed: onPrint,
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Copy for print',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.primaryContainer.withValues(alpha: 0.5),
                  scheme.surfaceContainerLowest,
                ],
              ),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: child,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onPrint,
            icon: const Icon(Icons.print_outlined),
            label: const Text('Copy report for printing'),
          ),
        ],
      ),
    );
  }
}

class _TimeseriesPointDetail extends StatelessWidget {
  const _TimeseriesPointDetail({
    required this.label,
    required this.value,
    required this.subtitle,
  });

  final String label;
  final String value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 12),
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 8),
        Text(subtitle),
      ],
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
    this.onOpenFull,
  });

  final String granularity;
  final String from;
  final String to;
  final void Function(
    BuildContext context,
    String printBody,
    Widget child,
  )? onOpenFull;

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
    final listChild = _loading
        ? const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        : _error != null
            ? Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
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
                    mainAxisSize: MainAxisSize.min,
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
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                'Page $_page of $_lastPage',
                                style: Theme.of(context).textTheme.labelLarge,
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
                  );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReportsNavRow(
          title: 'Paid transactions',
          subtitle: _total > 0
              ? '$_total transaction(s) · tap to open and print'
              : 'No transactions in selected period',
          icon: Icons.receipt_long_outlined,
          accent: Theme.of(context).colorScheme.primary,
          onTap: widget.onOpenFull == null
              ? () {}
              : () {
                    final buf = StringBuffer()
                      ..writeln('Paid transactions')
                      ..writeln();
                    if (_rows.isEmpty) {
                      buf.writeln('No paid transactions in selected range.');
                    } else {
                      for (final txn in _rows) {
                        final line = (txn['line'] ?? 'Transaction').toString();
                        final amount = ((txn['amount'] as num?)?.toDouble() ?? 0)
                            .toStringAsFixed(2);
                        buf.writeln('$line — ₱$amount');
                      }
                      if (_lastPage > 1) {
                        buf.writeln();
                        buf.writeln('Page $_page of $_lastPage ($_total total)');
                      }
                    }
                    widget.onOpenFull!(
                      context,
                      buf.toString(),
                      listChild,
                    );
                  },
        ),
        const SizedBox(height: 10),
        AppSectionCard(child: listChild),
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
              mainAxisSize: MainAxisSize.min,
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
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 10),
        _MetricLine(label: 'Gross revenue', value: '₱${_AdminReportsLegacyScreenState._fmtNum(revenue)}'),
        _MetricLine(label: 'Room revenue', value: '₱${_AdminReportsLegacyScreenState._fmtNum(room)}'),
        _MetricLine(label: 'Amenity revenue', value: '₱${_AdminReportsLegacyScreenState._fmtNum(amenity)}'),
        _MetricLine(label: 'Transfer adjustments', value: '₱${_AdminReportsLegacyScreenState._fmtNum(transfers)}'),
        const SizedBox(height: 6),
        _MetricLine(label: 'Refunds', value: '₱${_AdminReportsLegacyScreenState._fmtNum(refunds)}'),
        _MetricLine(label: 'Reseller payouts', value: '₱${_AdminReportsLegacyScreenState._fmtNum(reseller)}'),
        _MetricLine(label: 'Total expenses', value: '₱${_AdminReportsLegacyScreenState._fmtNum(expenses)}'),
        const SizedBox(height: 6),
        _MetricLine(
          label: 'Net before resellers',
          value: '₱${_AdminReportsLegacyScreenState._fmtNum(grossNet)}',
          emphasized: true,
        ),
        _MetricLine(
          label: 'Net profit',
          value: '₱${_AdminReportsLegacyScreenState._fmtNum(net)}',
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
    final total = _AdminReportsLegacyScreenState._parseAmount(data?['total_paid']);
    final count = _AdminReportsLegacyScreenState._parseInt(data?['payment_count']);
    final resellers =
        _AdminReportsLegacyScreenState._parseInt(data?['unique_resellers']);
    final byCat = _AdminReportsLegacyScreenState._asCategoryMap(data?['by_category']);

    if (data == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          '$label: no payouts recorded',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
            value: '₱${_AdminReportsLegacyScreenState._fmtNum(total)}',
          ),
          _MetricLine(label: 'Payments', value: '$count'),
          _MetricLine(label: 'Resellers', value: '$resellers'),
          if (byCat.isNotEmpty) ...[
            const SizedBox(height: 4),
            _MetricLine(
              label: 'Taxi',
              value: '₱${_AdminReportsLegacyScreenState._fmtNum(byCat['taxi'] ?? 0)}',
            ),
            _MetricLine(
              label: 'Motorcycle',
              value: '₱${_AdminReportsLegacyScreenState._fmtNum(byCat['motorcycle'] ?? 0)}',
            ),
            _MetricLine(
              label: 'Individual',
              value: '₱${_AdminReportsLegacyScreenState._fmtNum(byCat['individual'] ?? 0)}',
            ),
          ],
        ],
      ),
    );
  }
}

class _ResellerCommissionRecordForm extends StatefulWidget {
  const _ResellerCommissionRecordForm({required this.onRecorded});

  final Future<void> Function() onRecorded;

  @override
  State<_ResellerCommissionRecordForm> createState() =>
      _ResellerCommissionRecordFormState();
}

class _ResellerCommissionRecordFormState
    extends State<_ResellerCommissionRecordForm> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  List<Map<String, dynamic>> _resellers = [];
  String? _selectedResellerId;
  bool _loadingResellers = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadResellers();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadResellers() async {
    try {
      final res = await portalDio().get<Map<String, dynamic>>('/admin/resellers');
      final list = (res.data?['data'] as List<dynamic>?) ?? const [];
      if (!mounted) return;
      setState(() {
        _resellers = list
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
        _loadingResellers = false;
        if (_resellers.isNotEmpty && _selectedResellerId == null) {
          _selectedResellerId = (_resellers.first['id'] ?? '').toString();
        }
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingResellers = false;
        _error = dioErrorMessage(e);
      });
    } catch (e, stack) {
      if (!mounted) return;
      setState(() {
        _loadingResellers = false;
        _error = AdminDevErrorPanel.formatError(e, stack);
      });
    }
  }

  String? _selectedResellerValue() {
    final ids = _resellers
        .map((r) => (r['id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (_selectedResellerId != null && ids.contains(_selectedResellerId)) {
      return _selectedResellerId;
    }
    if (ids.isEmpty) return null;
    return ids.first;
  }

  Future<void> _submit() async {
    final id = _selectedResellerId ?? '';
    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    if (id.isEmpty) {
      setState(() => _error = 'Select a reseller.');
      return;
    }
    if (amount <= 0) {
      setState(() => _error = 'Enter a commission amount greater than zero.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await portalDio().post<Map<String, dynamic>>(
        '/admin/resellers/$id/commissions',
        data: {
          'amount': amount,
          'note': _noteCtrl.text.trim(),
        },
      );
      if (!mounted) return;
      _amountCtrl.clear();
      _noteCtrl.clear();
      showAppMessage(
        context,
        'Commission ₱${amount.toStringAsFixed(2)} recorded.',
      );
      await widget.onRecorded();
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _error = dioErrorMessage(e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingResellers) {
      return Text(
        'Loading partners…',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      );
    }
    if (_resellers.isEmpty) {
      return Text(
        'No resellers yet. Add partners under the Resellers tab first.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _selectedResellerValue(),
          decoration: const InputDecoration(
            labelText: 'Reseller *',
            border: OutlineInputBorder(),
          ),
          items: _resellers.map((r) {
            final id = (r['id'] ?? '').toString();
            final name = (r['name'] ?? 'Partner').toString();
            final category = (r['category'] ?? '').toString();
            return DropdownMenuItem(
              value: id,
              child: Text(
                category.isEmpty ? name : '$name · $category',
              ),
            );
          }).toList(),
          onChanged: _submitting
              ? null
              : (v) => setState(() => _selectedResellerId = v),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Commission amount (PHP) *',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _noteCtrl,
          decoration: const InputDecoration(
            labelText: 'Note (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _submitting ? null : _submit,
          icon: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.payments_outlined),
          label: const Text('Record payout'),
        ),
      ],
    );
  }
}
