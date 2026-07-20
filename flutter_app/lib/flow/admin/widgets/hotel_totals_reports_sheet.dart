import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../dio_client.dart';
import '../../../utils/money_format.dart';
import '../../admin_reports.dart';
import '../admin_dashboard_models.dart';
import 'collectibles_summary_dialog.dart';
import 'front_desk_sales_report_screen.dart';
import 'hotel_period_report_screen.dart';

/// Opens the Hotel Totals → Reports dropdown sheet (analytics + sales breakdown).
Future<void> openHotelTotalsReports(
  BuildContext context, {
  required List<Map<String, dynamic>> rooms,
  bool isFrontDesk = false,
}) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    builder: (ctx) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.88,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (ctx, scrollController) {
          return _HotelTotalsReportsSheet(
            rooms: rooms,
            isFrontDesk: isFrontDesk,
            scrollController: scrollController,
          );
        },
      );
    },
  );
}

enum _PaymentBucket { cash, ewallet, bank }

enum _SalesPeriod { daily, weekly, monthly, annual }

class _HotelTotalsReportsSheet extends StatefulWidget {
  const _HotelTotalsReportsSheet({
    required this.rooms,
    required this.scrollController,
    this.isFrontDesk = false,
  });

  final List<Map<String, dynamic>> rooms;
  final ScrollController scrollController;
  final bool isFrontDesk;

  @override
  State<_HotelTotalsReportsSheet> createState() =>
      _HotelTotalsReportsSheetState();
}

class _HotelTotalsReportsSheetState extends State<_HotelTotalsReportsSheet> {
  bool _loading = true;
  bool _salesLoading = false;
  String? _error;
  /// Always today's figures for expenses / cash on hand.
  Map<String, dynamic> _todaySummary = const {};
  List<Map<String, dynamic>> _todayBookingTxns = const [];
  /// Sales section — follows [_salesPeriod].
  Map<String, dynamic> _salesSummary = const {};
  List<Map<String, dynamic>> _bookingTxns = const [];
  _SalesPeriod _salesPeriod = _SalesPeriod.daily;
  String? _expanded; // sales | analytics | fo

  @override
  void initState() {
    super.initState();
    _load();
  }

  static DateTime _endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  static (DateTime start, DateTime end) _rangeFor(_SalesPeriod period) {
    final anchor = DateUtils.dateOnly(DateTime.now());
    switch (period) {
      case _SalesPeriod.weekly:
        final start = anchor.subtract(Duration(days: anchor.weekday - 1));
        return (start, _endOfDay(start.add(const Duration(days: 6))));
      case _SalesPeriod.monthly:
        final start = DateTime(anchor.year, anchor.month, 1);
        return (start, _endOfDay(DateTime(anchor.year, anchor.month + 1, 0)));
      case _SalesPeriod.annual:
        final start = DateTime(anchor.year, 1, 1);
        return (start, _endOfDay(DateTime(anchor.year, 12, 31)));
      case _SalesPeriod.daily:
        return (anchor, _endOfDay(anchor));
    }
  }

  static String _periodLabel(_SalesPeriod period) {
    switch (period) {
      case _SalesPeriod.daily:
        return 'Daily';
      case _SalesPeriod.weekly:
        return 'Weekly';
      case _SalesPeriod.monthly:
        return 'Monthly';
      case _SalesPeriod.annual:
        return 'Annual';
    }
  }

  static String _fmtDay(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String get _salesRangeCaption {
    final (start, end) = _rangeFor(_salesPeriod);
    final a = _fmtDay(start);
    final b = _fmtDay(end);
    return a == b ? a : '$a → $b';
  }

  Future<Map<String, dynamic>> _fetchShiftSummary(
    DateTime start,
    DateTime end,
  ) async {
    final res = await portalDio().get<Map<String, dynamic>>(
      '/reports/shift-summary',
      queryParameters: {
        'time_in': start.toIso8601String(),
        'time_out': end.toIso8601String(),
      },
    );
    return res.data ?? const <String, dynamic>{};
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final (start, end) = _rangeFor(_SalesPeriod.daily);
      final data = await _fetchShiftSummary(start, end);
      if (!mounted) return;
      final summary = (data['summary'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final bookings = ((data['booking_transactions'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      setState(() {
        _todaySummary = summary;
        _todayBookingTxns = bookings;
        _salesSummary = summary;
        _bookingTxns = bookings;
        _salesPeriod = _SalesPeriod.daily;
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

  Future<void> _setSalesPeriod(_SalesPeriod period) async {
    if (_salesPeriod == period && _bookingTxns.isNotEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _salesPeriod = period;
      _salesLoading = true;
      _error = null;
    });
    try {
      final (start, end) = _rangeFor(period);
      final data = await _fetchShiftSummary(start, end);
      if (!mounted) return;
      final summary = (data['summary'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final bookings = ((data['booking_transactions'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      setState(() {
        _salesSummary = summary;
        _bookingTxns = bookings;
        _salesLoading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = dioErrorMessage(e);
        _salesLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _salesLoading = false;
      });
    }
  }

  static _PaymentBucket? _bucketOf(String method) {
    final m = method.toLowerCase().trim();
    if (m.isEmpty) return null;
    if (m == 'cash') return _PaymentBucket.cash;
    if (m.contains('gcash') ||
        m.contains('g-cash') ||
        m.contains('paymaya') ||
        m.contains('maya') ||
        m.contains('ewallet') ||
        m.contains('e-wallet') ||
        m.contains('wallet')) {
      return _PaymentBucket.ewallet;
    }
    if (m.contains('bank') || m.contains('transfer')) {
      return _PaymentBucket.bank;
    }
    return null;
  }

  List<Map<String, dynamic>> _txnsFor(
    _PaymentBucket bucket, {
    List<Map<String, dynamic>>? source,
  }) {
    final rows = source ?? _bookingTxns;
    return rows.where((t) {
      final method = (t['payment_method'] ?? '').toString();
      return _bucketOf(method) == bucket;
    }).toList();
  }

  double _totalFor(
    _PaymentBucket bucket, {
    List<Map<String, dynamic>>? source,
  }) {
    var sum = 0.0;
    for (final t in _txnsFor(bucket, source: source)) {
      sum += (t['amount'] as num?)?.toDouble() ?? 0;
    }
    return sum;
  }

  double get _cashSales => _totalFor(_PaymentBucket.cash);
  double get _todayCashSales =>
      _totalFor(_PaymentBucket.cash, source: _todayBookingTxns);
  double get _expenses {
    final s = _todaySummary;
    return (s['expenses'] as num?)?.toDouble() ??
        (((s['refund_expense'] as num?)?.toDouble() ?? 0) +
            ((s['reseller_commissions_paid'] as num?)?.toDouble() ?? 0));
  }

  double get _cashOnHand =>
      (_todayCashSales - _expenses).clamp(0, double.infinity);
  double get _collectibles =>
      AdminDashboardModels.collectiblesForRooms(widget.rooms);

  void _toggle(String key) {
    HapticFeedback.selectionClick();
    setState(() => _expanded = _expanded == key ? null : key);
  }

  void _openTxnList({
    required String title,
    required List<Map<String, dynamic>> rows,
  }) {
    final periodName = _periodLabel(_salesPeriod).toLowerCase();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          builder: (ctx, sc) {
            return Material(
              color: Theme.of(ctx).colorScheme.surface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text(
                      title,
                      style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      '${rows.length} transaction(s) · $periodName · $_salesRangeCaption',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  ),
                  Expanded(
                    child: rows.isEmpty
                        ? const Center(child: Text('No transactions yet.'))
                        : ListView.separated(
                            controller: sc,
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            itemCount: rows.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                              final r = rows[i];
                              return Card(
                                child: ListTile(
                                  title: Text(
                                    (r['guest_name'] ?? 'Guest').toString(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: Text(
                                    [
                                      if ((r['reference'] ?? '')
                                          .toString()
                                          .isNotEmpty)
                                        r['reference'].toString(),
                                      if ((r['room_number'] ?? '')
                                          .toString()
                                          .isNotEmpty)
                                        'Room ${r['room_number']}',
                                      (r['payment_method'] ?? '').toString(),
                                    ].where((s) => s.isNotEmpty).join(' · '),
                                  ),
                                  trailing: Text(
                                    formatPeso(r['amount'] ?? 0),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _openFinancePeriod(String buttonLabel, String periodKey) {
    final period = switch (periodKey) {
      'weekly' => _SalesPeriod.weekly,
      'monthly' => _SalesPeriod.monthly,
      'annual' => _SalesPeriod.annual,
      _ => _SalesPeriod.daily,
    };
    final (start, end) = _rangeFor(period);
    openHotelPeriodReport(
      context: context,
      timeIn: start,
      timeOut: end,
      title: '$buttonLabel revenue',
      subtitle: 'Hotel-wide report',
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surface,
      child: ListView(
        controller: widget.scrollController,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Text(
            'Reports',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            'Sales, collectibles, expenses & analytics — tap a section to expand',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null) ...[
            Text(
              _error!,
              style: TextStyle(color: scheme.error),
            ),
            TextButton(onPressed: _load, child: const Text('Retry')),
            const SizedBox(height: 8),
          ],
          _DropdownSection(
            title: 'Sales',
            subtitle:
                'Cash · E-wallet · Bank transfer — daily / weekly / monthly / annual',
            icon: Icons.payments_outlined,
            accent: Colors.teal.shade700,
            expanded: _expanded == 'sales',
            onToggle: () => _toggle('sales'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final period in _SalesPeriod.values)
                      ChoiceChip(
                        label: Text(_periodLabel(period)),
                        selected: _salesPeriod == period,
                        onSelected: _salesLoading
                            ? null
                            : (_) => _setSalesPeriod(period),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _salesRangeCaption,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                if (_salesLoading) ...[
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(minHeight: 2),
                ],
                const SizedBox(height: 10),
                _SalesMethodTile(
                  label: 'Cash',
                  count: _txnsFor(_PaymentBucket.cash).length,
                  total: _cashSales,
                  color: Colors.green.shade700,
                  onTap: () => _openTxnList(
                    title: 'Cash sales · ${_periodLabel(_salesPeriod)}',
                    rows: _txnsFor(_PaymentBucket.cash),
                  ),
                ),
                const SizedBox(height: 8),
                _SalesMethodTile(
                  label: 'E-wallet',
                  count: _txnsFor(_PaymentBucket.ewallet).length,
                  total: _totalFor(_PaymentBucket.ewallet),
                  color: Colors.blue.shade700,
                  onTap: () => _openTxnList(
                    title:
                        'E-wallet sales · ${_periodLabel(_salesPeriod)}',
                    rows: _txnsFor(_PaymentBucket.ewallet),
                  ),
                ),
                const SizedBox(height: 8),
                _SalesMethodTile(
                  label: 'Bank transfer',
                  count: _txnsFor(_PaymentBucket.bank).length,
                  total: _totalFor(_PaymentBucket.bank),
                  color: Colors.indigo.shade700,
                  onTap: () => _openTxnList(
                    title:
                        'Bank transfer sales · ${_periodLabel(_salesPeriod)}',
                    rows: _txnsFor(_PaymentBucket.bank),
                  ),
                ),
                if ((_salesSummary['gross_revenue'] as num?) != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Period gross revenue: ${formatPeso(_salesSummary['gross_revenue'] ?? 0)}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          _ActionTile(
            title: 'Collectibles',
            subtitle: formatPeso(_collectibles),
            icon: Icons.receipt_long_outlined,
            color: Colors.orange.shade800,
            onTap: () => showCollectiblesSummaryDialog(
              context,
              rooms: widget.rooms,
            ),
          ),
          const SizedBox(height: 8),
          _ActionTile(
            title: 'Expenses',
            subtitle: formatPeso(_expenses),
            icon: Icons.money_off_outlined,
            color: Colors.red.shade700,
            onTap: () => _showMetricDetail(
              title: 'Expenses (today)',
              lines: [
                MapEntry(
                  'Refund expense',
                  formatPeso(_todaySummary['refund_expense'] ?? 0),
                ),
                MapEntry(
                  'Reseller commissions',
                  formatPeso(_todaySummary['reseller_commissions_paid'] ?? 0),
                ),
                MapEntry('Total expenses', formatPeso(_expenses)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _ActionTile(
            title: 'Cash on hand',
            subtitle: formatPeso(_cashOnHand),
            icon: Icons.account_balance_wallet_outlined,
            color: scheme.primary,
            onTap: () => _showMetricDetail(
              title: 'Cash on hand',
              lines: [
                MapEntry('Cash sales today', formatPeso(_todayCashSales)),
                MapEntry('Less expenses', formatPeso(_expenses)),
                MapEntry('Cash on hand', formatPeso(_cashOnHand)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _DropdownSection(
            title: 'Front desk sales report',
            subtitle: 'Per FO account — cash, GCash, bank transfer & more',
            icon: Icons.point_of_sale_outlined,
            accent: scheme.primary,
            expanded: _expanded == 'fo',
            onToggle: () => _toggle('fo'),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: scheme.primary.withValues(alpha: 0.12),
                child: Icon(Icons.people_outline, color: scheme.primary),
              ),
              title: const Text(
                'Open front desk sales',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'See how many paid in cash, GCash, bank transfer, and totals per FO',
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
          const SizedBox(height: 10),
          _DropdownSection(
            title: 'Reports & analytics',
            subtitle: 'Same hub as Setup → Analytics & reports',
            icon: Icons.analytics_outlined,
            accent: Colors.purple.shade700,
            expanded: _expanded == 'analytics',
            onToggle: () => _toggle('analytics'),
            child: Column(
              children: [
                _AnalyticsLink(
                  title: 'Front desk sales',
                  subtitle: 'Per-account daily → annual',
                  icon: Icons.point_of_sale_outlined,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const FrontDeskSalesReportScreen(),
                    ),
                  ),
                ),
                _AnalyticsLink(
                  title: 'Daily revenue',
                  subtitle: 'Hotel-wide today',
                  icon: Icons.today_outlined,
                  onTap: () => _openFinancePeriod('Daily', 'daily'),
                ),
                _AnalyticsLink(
                  title: 'Weekly revenue',
                  subtitle: 'This week',
                  icon: Icons.date_range_outlined,
                  onTap: () => _openFinancePeriod('Weekly', 'weekly'),
                ),
                _AnalyticsLink(
                  title: 'Monthly revenue',
                  subtitle: 'This month',
                  icon: Icons.calendar_month_outlined,
                  onTap: () => _openFinancePeriod('Monthly', 'monthly'),
                ),
                _AnalyticsLink(
                  title: 'Annual revenue',
                  subtitle: 'This year',
                  icon: Icons.insights_outlined,
                  onTap: () => _openFinancePeriod('Annual', 'annual'),
                ),
                _AnalyticsLink(
                  title: 'Full reports hub',
                  subtitle: 'Room insights, amenities, commissions…',
                  icon: Icons.grid_view_rounded,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AdminReportsScreen(
                          isFrontDesk: widget.isFrontDesk,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showMetricDetail({
    required String title,
    required List<MapEntry<String, String>> lines,
  }) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(child: Text(e.key)),
                    Text(
                      e.value,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _DropdownSection extends StatelessWidget {
  const _DropdownSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: expanded ? scheme.surfaceContainerLow : scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: expanded
              ? accent.withValues(alpha: 0.45)
              : scheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(icon, color: accent, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        Text(
                          subtitle,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _SalesMethodTile extends StatelessWidget {
  const _SalesMethodTile({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
    required this.onTap,
  });

  final String label;
  final int count;
  final double total;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                    Text(
                      '$count payment(s)',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              Text(
                formatPeso(total),
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: color,
                  fontSize: 16,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnalyticsLink extends StatelessWidget {
  const _AnalyticsLink({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(icon),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
