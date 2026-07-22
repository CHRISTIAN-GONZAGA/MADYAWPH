import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../dio_client.dart';
import '../../../utils/money_format.dart';
import '../admin_dashboard_models.dart';
import 'amenities_report_screen.dart';
import 'collectibles_summary_dialog.dart';
import 'front_desk_sales_report_screen.dart';
import 'hotel_period_report_screen.dart';
import 'hotel_totals_reports_sheet.dart';
import 'reseller_commissions_report_screen.dart';
import 'room_insights_report_screen.dart';

/// Dedicated Reports hub under Hotel totals — bento tiles for each report.
class HotelReportsBentoSection extends StatefulWidget {
  const HotelReportsBentoSection({
    super.key,
    required this.rooms,
    this.showHeader = true,
  });

  final List<Map<String, dynamic>> rooms;
  final bool showHeader;

  @override
  State<HotelReportsBentoSection> createState() =>
      _HotelReportsBentoSectionState();
}

class _HotelReportsBentoSectionState extends State<HotelReportsBentoSection> {
  bool _loading = true;
  String? _error;

  double _sales = 0;
  double _expenses = 0;
  double _cashSales = 0;
  double _dailyRevenue = 0;
  double _weeklyRevenue = 0;
  double _monthlyRevenue = 0;
  double _annualRevenue = 0;
  int _demoGuests = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  static DateTime _endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  static (DateTime start, DateTime end) _rangeFor(_BentoPeriod period) {
    final anchor = DateUtils.dateOnly(DateTime.now());
    switch (period) {
      case _BentoPeriod.weekly:
        final start = anchor.subtract(Duration(days: anchor.weekday - 1));
        return (start, _endOfDay(start.add(const Duration(days: 6))));
      case _BentoPeriod.monthly:
        final start = DateTime(anchor.year, anchor.month, 1);
        return (start, _endOfDay(DateTime(anchor.year, anchor.month + 1, 0)));
      case _BentoPeriod.annual:
        final start = DateTime(anchor.year, 1, 1);
        return (start, _endOfDay(DateTime(anchor.year, 12, 31)));
      case _BentoPeriod.daily:
        return (anchor, _endOfDay(anchor));
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final today = DateUtils.dateOnly(DateTime.now());
      final end = _endOfDay(today);
      final results = await Future.wait([
        portalDio().get<Map<String, dynamic>>(
          '/reports/shift-summary',
          queryParameters: {
            'time_in': today.toIso8601String(),
            'time_out': end.toIso8601String(),
          },
        ),
        portalDio().get<Map<String, dynamic>>(
          '/reports/profit-overview',
          queryParameters: {
            'anchor_date':
                '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}',
          },
        ),
        portalDio().get<Map<String, dynamic>>(
          '/reports/guest-demographics',
          queryParameters: {'period': 'month'},
        ),
      ]);
      if (!mounted) return;

      final shift = results[0].data ?? const <String, dynamic>{};
      final profit = results[1].data ?? const <String, dynamic>{};
      final demo = results[2].data ?? const <String, dynamic>{};

      final summary =
          (shift['summary'] as Map?)?.cast<String, dynamic>() ?? const {};
      final bookings = ((shift['booking_transactions'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      var cashFromTxns = 0.0;
      var salesFromTxns = 0.0;
      for (final t in bookings) {
        final amount = parseJsonDouble(t['amount']);
        salesFromTxns += amount;
        final method = (t['payment_method'] ?? '').toString().toLowerCase();
        if (method == 'cash') cashFromTxns += amount;
      }

      final gross = parseJsonDouble(summary['gross_revenue']);
      final expenses = parseJsonDouble(summary['expenses']);
      final fallbackExpenses = parseJsonDouble(summary['refund_expense']) +
          parseJsonDouble(summary['reseller_commissions_paid']) +
          parseJsonDouble(summary['custom_expenses']);
      // Prefer the larger so older API payloads (expenses without custom) still
      // show the correct total when custom_expenses is present separately.
      final resolvedExpenses =
          expenses >= fallbackExpenses - 0.009 ? expenses : fallbackExpenses;

      double periodGross(String key) {
        final row = profit[key];
        if (row is! Map) return 0;
        return parseJsonDouble(row['gross_revenue'] ?? row['revenue']);
      }

      final totals = (demo['totals'] as Map?)?.cast<String, dynamic>();
      final guests = (totals?['total_guests'] as num?)?.toInt() ?? 0;

      setState(() {
        _sales = gross > 0.009 ? gross : salesFromTxns;
        _expenses = resolvedExpenses;
        _cashSales = cashFromTxns;
        _dailyRevenue = periodGross('daily');
        _weeklyRevenue = periodGross('weekly');
        _monthlyRevenue = periodGross('monthly');
        _annualRevenue = periodGross('annual');
        _demoGuests = guests;
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

  double get _collectibles =>
      AdminDashboardModels.collectiblesForRooms(widget.rooms);

  double get _cashOnHand =>
      (_cashSales - _expenses).clamp(0, double.infinity);

  Future<void> _openSheet(String section) async {
    await openHotelTotalsReports(
      context,
      rooms: widget.rooms,
      isFrontDesk: false,
      initialExpanded: section,
    );
    if (!mounted) return;
    await _load();
  }

  void _openPeriod(_BentoPeriod period, String label) {
    final (start, end) = _rangeFor(period);
    openHotelPeriodReport(
      context: context,
      timeIn: start,
      timeOut: end,
      title: '$label revenue',
      subtitle: 'Hotel-wide report',
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHeader) ...[
          Row(
            children: [
              Icon(Icons.grid_view_rounded, color: scheme.primary, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reports',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    Text(
                      'Tap a tile to open that report',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh, size: 20),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 10),
        ] else
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh, size: 20),
              visualDensity: VisualDensity.compact,
            ),
          ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_error != null) ...[
          Text(_error!, style: TextStyle(color: scheme.error, fontSize: 12)),
          TextButton(onPressed: _load, child: const Text('Retry')),
          const SizedBox(height: 8),
        ],
        _BentoGrid(
          children: [
            _BentoTile(
              title: 'Sales',
              subtitle: formatPeso(_sales),
              icon: Icons.payments_outlined,
              accent: Colors.teal.shade700,
              span: _BentoSpan.wide,
              onTap: () => _openSheet('sales'),
            ),
            _BentoTile(
              title: 'Collectibles',
              subtitle: formatPeso(_collectibles),
              icon: Icons.receipt_long_outlined,
              accent: Colors.orange.shade800,
              onTap: () => showCollectiblesSummaryDialog(
                context,
                rooms: widget.rooms,
              ),
            ),
            _BentoTile(
              title: 'Expenses',
              subtitle: formatPeso(_expenses),
              icon: Icons.money_off_outlined,
              accent: Colors.red.shade700,
              onTap: () => _openSheet('expenses'),
            ),
            _BentoTile(
              title: 'Cash on hand',
              subtitle: formatPeso(_cashOnHand),
              icon: Icons.account_balance_wallet_outlined,
              accent: scheme.primary,
              onTap: () => _openSheet('cash'),
            ),
            _BentoTile(
              title: 'Demographics',
              subtitle: _demoGuests > 0
                  ? '$_demoGuests guest(s) this month'
                  : 'Gender · nationality · age',
              icon: Icons.groups_outlined,
              accent: Colors.deepPurple.shade400,
              onTap: () => _openSheet('demographics'),
            ),
            _BentoTile(
              title: 'Front desk sales',
              subtitle: 'Per FO · cash / e-wallet / bank',
              icon: Icons.point_of_sale_outlined,
              accent: scheme.tertiary,
              span: _BentoSpan.wide,
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const FrontDeskSalesReportScreen(),
                  ),
                );
              },
            ),
            _BentoTile(
              title: 'Room insights',
              subtitle: 'Most / least booked · profit',
              icon: Icons.hotel_class_outlined,
              accent: Colors.indigo,
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const RoomInsightsReportScreen(),
                  ),
                );
              },
            ),
            _BentoTile(
              title: 'Amenities reports',
              subtitle: 'Product sales & profit',
              icon: Icons.room_service_outlined,
              accent: Colors.teal,
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AmenitiesReportScreen(),
                  ),
                );
              },
            ),
            _BentoTile(
              title: 'Reseller commissions',
              subtitle: 'Payouts & calendar',
              icon: Icons.handshake_outlined,
              accent: Colors.deepOrange,
              span: _BentoSpan.wide,
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ResellerCommissionsReportScreen(),
                  ),
                );
              },
            ),
            _BentoTile(
              title: 'Daily revenue',
              subtitle: formatPeso(_dailyRevenue),
              icon: Icons.today_outlined,
              accent: Colors.blue,
              onTap: () => _openPeriod(_BentoPeriod.daily, 'Daily'),
            ),
            _BentoTile(
              title: 'Weekly revenue',
              subtitle: formatPeso(_weeklyRevenue),
              icon: Icons.date_range_outlined,
              accent: Colors.cyan.shade700,
              onTap: () => _openPeriod(_BentoPeriod.weekly, 'Weekly'),
            ),
            _BentoTile(
              title: 'Monthly revenue',
              subtitle: formatPeso(_monthlyRevenue),
              icon: Icons.calendar_month_outlined,
              accent: Colors.purple,
              onTap: () => _openPeriod(_BentoPeriod.monthly, 'Monthly'),
            ),
            _BentoTile(
              title: 'Annual revenue',
              subtitle: formatPeso(_annualRevenue),
              icon: Icons.insights_outlined,
              accent: Colors.brown,
              onTap: () => _openPeriod(_BentoPeriod.annual, 'Annual'),
            ),
          ],
        ),
      ],
    );
  }
}

enum _BentoPeriod { daily, weekly, monthly, annual }

enum _BentoSpan { single, wide }

/// Simple bento layout: full-width rows for wide tiles, 2-column for singles.
class _BentoGrid extends StatelessWidget {
  const _BentoGrid({required this.children});

  final List<_BentoTile> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    var i = 0;
    while (i < children.length) {
      final tile = children[i];
      if (tile.span == _BentoSpan.wide) {
        rows.add(Padding(
          padding: EdgeInsets.only(bottom: i == children.length - 1 ? 0 : 8),
          child: tile,
        ));
        i++;
        continue;
      }
      if (i + 1 < children.length &&
          children[i + 1].span == _BentoSpan.single) {
        rows.add(Padding(
          padding: EdgeInsets.only(bottom: i + 1 == children.length - 1 ? 0 : 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: children[i]),
              const SizedBox(width: 8),
              Expanded(child: children[i + 1]),
            ],
          ),
        ));
        i += 2;
        continue;
      }
      rows.add(Padding(
        padding: EdgeInsets.only(bottom: i == children.length - 1 ? 0 : 8),
        child: tile,
      ));
      i++;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

class _BentoTile extends StatelessWidget {
  const _BentoTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
    this.span = _BentoSpan.single,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;
  final _BentoSpan span;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tall = span == _BentoSpan.wide;

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: accent.withValues(alpha: 0.22),
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: 0.10),
                scheme.surfaceContainerLow,
              ],
            ),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, tall ? 14 : 12, 12, tall ? 14 : 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: accent, size: 18),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.arrow_outward_rounded,
                      size: 16,
                      color: accent.withValues(alpha: 0.7),
                    ),
                  ],
                ),
                SizedBox(height: tall ? 12 : 10),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
