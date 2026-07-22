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
import 'reseller_commissions_report_screen.dart';
import 'room_insights_report_screen.dart';

/// Opens the Hotel Totals → Reports sheet.
Future<void> openHotelTotalsReports(
  BuildContext context, {
  required List<Map<String, dynamic>> rooms,
  bool isFrontDesk = false,
  String? initialExpanded,
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
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.96,
        builder: (ctx, scrollController) {
          return _HotelTotalsReportsSheet(
            rooms: rooms,
            isFrontDesk: isFrontDesk,
            scrollController: scrollController,
            initialExpanded: initialExpanded,
          );
        },
      );
    },
  );
}

enum _PaymentBucket { cash, ewallet, bank }

enum _ReportPeriod { daily, weekly, monthly, annual }

class _HotelTotalsReportsSheet extends StatefulWidget {
  const _HotelTotalsReportsSheet({
    required this.rooms,
    required this.scrollController,
    this.isFrontDesk = false,
    this.initialExpanded,
  });

  final List<Map<String, dynamic>> rooms;
  final ScrollController scrollController;
  final bool isFrontDesk;
  final String? initialExpanded;

  @override
  State<_HotelTotalsReportsSheet> createState() =>
      _HotelTotalsReportsSheetState();
}

class _HotelTotalsReportsSheetState extends State<_HotelTotalsReportsSheet> {
  bool _loading = true;
  bool _salesLoading = false;
  bool _financeLoading = false;
  bool _demoLoading = false;
  String? _error;
  late String? _expanded;

  Map<String, dynamic> _todaySummary = const {};
  List<Map<String, dynamic>> _todayBookingTxns = const [];

  Map<String, dynamic> _salesSummary = const {};
  List<Map<String, dynamic>> _bookingTxns = const [];
  _ReportPeriod _salesPeriod = _ReportPeriod.daily;

  Map<String, dynamic> _financeSummary = const {};
  List<Map<String, dynamic>> _financeTxns = const [];
  _ReportPeriod _financePeriod = _ReportPeriod.daily;

  Map<String, dynamic> _demographics = const {};
  _ReportPeriod _demoPeriod = _ReportPeriod.monthly;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initialExpanded;
    _load();
  }

  static DateTime _endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  static (DateTime start, DateTime end) _rangeFor(_ReportPeriod period) {
    final anchor = DateUtils.dateOnly(DateTime.now());
    switch (period) {
      case _ReportPeriod.weekly:
        final start = anchor.subtract(Duration(days: anchor.weekday - 1));
        return (start, _endOfDay(start.add(const Duration(days: 6))));
      case _ReportPeriod.monthly:
        final start = DateTime(anchor.year, anchor.month, 1);
        return (start, _endOfDay(DateTime(anchor.year, anchor.month + 1, 0)));
      case _ReportPeriod.annual:
        final start = DateTime(anchor.year, 1, 1);
        return (start, _endOfDay(DateTime(anchor.year, 12, 31)));
      case _ReportPeriod.daily:
        return (anchor, _endOfDay(anchor));
    }
  }

  static String _periodLabel(_ReportPeriod period) {
    switch (period) {
      case _ReportPeriod.daily:
        return 'Daily';
      case _ReportPeriod.weekly:
        return 'Weekly';
      case _ReportPeriod.monthly:
        return 'Monthly';
      case _ReportPeriod.annual:
        return 'Annual';
    }
  }

  static String _demoApiPeriod(_ReportPeriod period) {
    switch (period) {
      case _ReportPeriod.daily:
        return 'day';
      case _ReportPeriod.weekly:
        return 'week';
      case _ReportPeriod.monthly:
        return 'month';
      case _ReportPeriod.annual:
        return 'year';
    }
  }

  static String _fmtDay(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _rangeCaption(_ReportPeriod period) {
    final (start, end) = _rangeFor(period);
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
      final (start, end) = _rangeFor(_ReportPeriod.daily);
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
        _financeSummary = summary;
        _financeTxns = bookings;
        _salesPeriod = _ReportPeriod.daily;
        _financePeriod = _ReportPeriod.daily;
        _loading = false;
      });
      // Demographics load in background.
      _loadDemographics(_demoPeriod);
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

  Future<void> _setSalesPeriod(_ReportPeriod period) async {
    if (_salesPeriod == period && _bookingTxns.isNotEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _salesPeriod = period;
      _salesLoading = true;
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

  Future<void> _setFinancePeriod(_ReportPeriod period) async {
    if (_financePeriod == period && _financeTxns.isNotEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _financePeriod = period;
      _financeLoading = true;
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
        _financeSummary = summary;
        _financeTxns = bookings;
        _financeLoading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = dioErrorMessage(e);
        _financeLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _financeLoading = false;
      });
    }
  }

  Future<void> _loadDemographics(_ReportPeriod period) async {
    setState(() {
      _demoPeriod = period;
      _demoLoading = true;
    });
    try {
      final res = await portalDio().get<Map<String, dynamic>>(
        '/reports/guest-demographics',
        queryParameters: {'period': _demoApiPeriod(period)},
      );
      if (!mounted) return;
      setState(() {
        _demographics = res.data ?? const <String, dynamic>{};
        _demoLoading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = dioErrorMessage(e);
        _demoLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _demoLoading = false;
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
      sum += parseJsonDouble(t['amount']);
    }
    return sum;
  }

  double get _cashSales => _totalFor(_PaymentBucket.cash);
  double get _financeCashSales =>
      _totalFor(_PaymentBucket.cash, source: _financeTxns);

  double get _salesTxnTotal =>
      _cashSales +
      _totalFor(_PaymentBucket.ewallet) +
      _totalFor(_PaymentBucket.bank);

  double _expensesOf(Map<String, dynamic> summary) {
    final reported = (summary['expenses'] as num?)?.toDouble();
    final parts = ((summary['refund_expense'] as num?)?.toDouble() ?? 0) +
        ((summary['reseller_commissions_paid'] as num?)?.toDouble() ?? 0) +
        ((summary['custom_expenses'] as num?)?.toDouble() ?? 0);
    if (reported == null) return parts;
    // Prefer the larger so older API payloads (expenses without custom) still
    // show the correct total when custom_expenses is present separately.
    return reported >= parts - 0.009 ? reported : parts;
  }

  double get _expenses => _expensesOf(_financeSummary);
  double get _todayExpenses => _expensesOf(_todaySummary);

  double get _cashOnHand =>
      (_financeCashSales - _expenses).clamp(0, double.infinity);

  double get _collectibles =>
      AdminDashboardModels.collectiblesForRooms(widget.rooms);

  List<Map<String, dynamic>> get _collectibleLines =>
      AdminDashboardModels.collectiblesSummaryLines(widget.rooms);

  void _toggle(String key) {
    if (_focused) return;
    HapticFeedback.selectionClick();
    setState(() => _expanded = _expanded == key ? null : key);
    if (key == 'demographics' &&
        _expanded == 'demographics' &&
        _demographics.isEmpty &&
        !_demoLoading) {
      _loadDemographics(_demoPeriod);
    }
  }

  bool get _focused => widget.initialExpanded != null;

  bool _showSection(String key) =>
      !_focused || widget.initialExpanded == key;

  String get _sheetTitle {
    switch (widget.initialExpanded) {
      case 'sales':
        return 'Sales';
      case 'collectibles':
        return 'Collectibles';
      case 'expenses':
        return 'Expenses';
      case 'cash':
        return 'Cash on hand';
      case 'demographics':
        return 'Demographics';
      case 'fo':
        return 'Front desk sales';
      case 'room_insights':
        return 'Room insights';
      case 'amenities':
        return 'Amenities reports';
      case 'reseller':
        return 'Reseller commissions';
      case 'rev_daily':
        return 'Daily revenue';
      case 'rev_weekly':
        return 'Weekly revenue';
      case 'rev_monthly':
        return 'Monthly revenue';
      case 'rev_annual':
        return 'Annual revenue';
      default:
        return 'Reports';
    }
  }

  String get _sheetSubtitle {
    if (!_focused) {
      return 'Tap a section to expand · sales, collectibles, expenses & more';
    }
    return 'Showing this report only';
  }

  bool _sectionExpanded(String key) =>
      _focused || _expanded == key;

  void _openTxnList({
    required String title,
    required List<Map<String, dynamic>> rows,
    required _ReportPeriod period,
  }) {
    final periodName = _periodLabel(period).toLowerCase();
    final caption = _rangeCaption(period);
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
                      '${rows.length} item(s) · $periodName · $caption',
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
                                    (r['guest_name'] ??
                                            r['label'] ??
                                            'Guest')
                                        .toString(),
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
                                    formatPeso(parseJsonDouble(r['amount'])),
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

  void _openFinancePeriod(String buttonLabel, _ReportPeriod period) {
    final (start, end) = _rangeFor(period);
    openHotelPeriodReport(
      context: context,
      timeIn: start,
      timeOut: end,
      title: '$buttonLabel revenue',
      subtitle: 'Hotel-wide report',
    );
  }

  Future<void> _openAddCustomExpense() async {
    final labelCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add custom expense'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: labelCtrl,
              decoration: const InputDecoration(
                labelText: 'Label',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: '₱ ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: notesCtrl,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final amount = double.tryParse(amountCtrl.text.trim());
    final label = labelCtrl.text.trim();
    if (label.isEmpty || amount == null || amount <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid label and amount.')),
      );
      return;
    }
    try {
      await portalDio().post(
        '/reports/expenses',
        data: {
          'label': label,
          'amount': amount,
          'notes': notesCtrl.text.trim(),
          'expense_date': _fmtDay(DateTime.now()),
        },
      );
      if (!mounted) return;
      await _setFinancePeriod(_financePeriod);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Custom expense saved.')),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dioErrorMessage(e))),
      );
    }
  }

  Future<void> _openCustomExpenses() async {
    final (start, end) = _rangeFor(_financePeriod);
    try {
      final res = await portalDio().get<Map<String, dynamic>>(
        '/reports/expenses',
        queryParameters: {
          'from': _fmtDay(start),
          'to': _fmtDay(end),
        },
      );
      if (!mounted) return;
      final rows = ((res.data?['data'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) {
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.6,
            builder: (ctx, sc) {
              return ListView(
                controller: sc,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  Text(
                    'Custom expenses · ${_periodLabel(_financePeriod)}',
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text('Total ${formatPeso(res.data?['total'] ?? 0)}'),
                  const SizedBox(height: 12),
                  if (rows.isEmpty)
                    const Text('No custom expenses in this period.')
                  else
                    ...rows.map(
                      (r) => Card(
                        child: ListTile(
                          title: Text((r['label'] ?? 'Expense').toString()),
                          subtitle: Text(
                            [
                              (r['expense_date'] ?? '').toString(),
                              if ((r['notes'] ?? '').toString().isNotEmpty)
                                r['notes'].toString(),
                            ].where((s) => s.isNotEmpty).join(' · '),
                          ),
                          trailing: Text(
                            formatPeso(r['amount']),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dioErrorMessage(e))),
      );
    }
  }

  Widget _periodChips({
    required _ReportPeriod selected,
    required bool loading,
    required ValueChanged<_ReportPeriod> onSelect,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final period in _ReportPeriod.values)
          ChoiceChip(
            label: Text(_periodLabel(period)),
            selected: selected == period,
            onSelected: loading ? null : (_) => onSelect(period),
          ),
      ],
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
            _sheetTitle,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            _sheetSubtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null) ...[
            Text(_error!, style: TextStyle(color: scheme.error)),
            TextButton(onPressed: _load, child: const Text('Retry')),
            const SizedBox(height: 8),
          ],

          // —— Sales ——
          if (_showSection('sales')) ...[
          _DropdownSection(
            title: 'Sales',
            subtitle: formatPeso(
              parseJsonDouble(_salesSummary['gross_revenue']) > 0.009
                  ? parseJsonDouble(_salesSummary['gross_revenue'])
                  : _salesTxnTotal,
            ),
            icon: Icons.payments_outlined,
            accent: Colors.teal.shade700,
            expanded: _sectionExpanded('sales'),
            locked: _focused,
            onToggle: () => _toggle('sales'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _periodChips(
                  selected: _salesPeriod,
                  loading: _salesLoading,
                  onSelect: _setSalesPeriod,
                ),
                const SizedBox(height: 8),
                Text(
                  _rangeCaption(_salesPeriod),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                if (_salesLoading) ...[
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(minHeight: 2),
                ],
                const SizedBox(height: 10),
                _DetailTile(
                  label: 'Cash',
                  countLabel: '${_txnsFor(_PaymentBucket.cash).length} payment(s)',
                  total: _cashSales,
                  color: Colors.green.shade700,
                  onTap: () => _openTxnList(
                    title: 'Cash sales · ${_periodLabel(_salesPeriod)}',
                    rows: _txnsFor(_PaymentBucket.cash),
                    period: _salesPeriod,
                  ),
                ),
                const SizedBox(height: 8),
                _DetailTile(
                  label: 'E-wallet',
                  countLabel:
                      '${_txnsFor(_PaymentBucket.ewallet).length} payment(s)',
                  total: _totalFor(_PaymentBucket.ewallet),
                  color: Colors.blue.shade700,
                  onTap: () => _openTxnList(
                    title: 'E-wallet sales · ${_periodLabel(_salesPeriod)}',
                    rows: _txnsFor(_PaymentBucket.ewallet),
                    period: _salesPeriod,
                  ),
                ),
                const SizedBox(height: 8),
                _DetailTile(
                  label: 'Bank transfer',
                  countLabel: '${_txnsFor(_PaymentBucket.bank).length} payment(s)',
                  total: _totalFor(_PaymentBucket.bank),
                  color: Colors.indigo.shade700,
                  onTap: () => _openTxnList(
                    title:
                        'Bank transfer sales · ${_periodLabel(_salesPeriod)}',
                    rows: _txnsFor(_PaymentBucket.bank),
                    period: _salesPeriod,
                  ),
                ),
              ],
            ),
          ),
          if (!_focused)
          const SizedBox(height: 10),
          ],

          // —— Collectibles ——
          if (_showSection('collectibles')) ...[
          _DropdownSection(
            title: 'Collectibles',
            subtitle: formatPeso(_collectibles),
            icon: Icons.receipt_long_outlined,
            accent: Colors.orange.shade800,
            expanded: _sectionExpanded('collectibles'),
            locked: _focused,
            onToggle: () => _toggle('collectibles'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Amounts due in the checkout queue right now',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 10),
                if (_collectibleLines.isEmpty)
                  const Text('No collectibles in queue.')
                else
                  ..._collectibleLines.map((line) {
                    final roomNo = (line['room_number'] ?? '—').toString();
                    final guest = (line['guest_name'] ?? 'Guest').toString();
                    final amount =
                        (line['amount'] as num?)?.toDouble() ?? 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _DetailTile(
                        label: 'Room $roomNo',
                        countLabel: guest,
                        total: amount,
                        color: Colors.orange.shade800,
                        onTap: () => showCollectiblesSummaryDialog(
                          context,
                          rooms: widget.rooms,
                        ),
                      ),
                    );
                  }),
                const SizedBox(height: 4),
                _DetailTile(
                  label: 'Full collectibles summary',
                  countLabel: '${_collectibleLines.length} room(s)',
                  total: _collectibles,
                  color: Colors.orange.shade900,
                  onTap: () => showCollectiblesSummaryDialog(
                    context,
                    rooms: widget.rooms,
                  ),
                ),
              ],
            ),
          ),
          if (!_focused)
          const SizedBox(height: 10),
          ],

          // —— Expenses ——
          if (_showSection('expenses')) ...[
          _DropdownSection(
            title: 'Expenses',
            subtitle: formatPeso(_expenses),
            icon: Icons.money_off_outlined,
            accent: Colors.red.shade700,
            expanded: _sectionExpanded('expenses'),
            locked: _focused,
            onToggle: () {
              _toggle('expenses');
              if (_expanded == 'expenses') {
                _setFinancePeriod(_financePeriod);
              }
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _periodChips(
                  selected: _financePeriod,
                  loading: _financeLoading,
                  onSelect: _setFinancePeriod,
                ),
                const SizedBox(height: 8),
                Text(
                  _rangeCaption(_financePeriod),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                if (_financeLoading) ...[
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(minHeight: 2),
                ],
                const SizedBox(height: 10),
                _DetailTile(
                  label: 'Refund expense',
                  countLabel: 'Refunds in period',
                  total: (_financeSummary['refund_expense'] as num?)
                          ?.toDouble() ??
                      0,
                  color: Colors.red.shade600,
                  onTap: () => _showMetricDetail(
                    title:
                        'Refund expense · ${_periodLabel(_financePeriod)}',
                    lines: [
                      MapEntry(
                        'Refund expense',
                        formatPeso(_financeSummary['refund_expense'] ?? 0),
                      ),
                      MapEntry(
                        'Period',
                        _rangeCaption(_financePeriod),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _DetailTile(
                  label: 'Reseller commissions',
                  countLabel: 'Commissions paid',
                  total: (_financeSummary['reseller_commissions_paid'] as num?)
                          ?.toDouble() ??
                      0,
                  color: Colors.deepOrange.shade700,
                  onTap: () => _showMetricDetail(
                    title:
                        'Reseller commissions · ${_periodLabel(_financePeriod)}',
                    lines: [
                      MapEntry(
                        'Commissions paid',
                        formatPeso(
                          _financeSummary['reseller_commissions_paid'] ?? 0,
                        ),
                      ),
                      MapEntry('Period', _rangeCaption(_financePeriod)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _DetailTile(
                  label: 'Custom expenses',
                  countLabel: 'Manual expenses in period',
                  total: (_financeSummary['custom_expenses'] as num?)
                          ?.toDouble() ??
                      0,
                  color: Colors.brown.shade700,
                  onTap: () => _openCustomExpenses(),
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: _openAddCustomExpense,
                  icon: const Icon(Icons.add),
                  label: const Text('Add custom expense'),
                ),
                const SizedBox(height: 8),
                _DetailTile(
                  label: 'Total expenses',
                  countLabel: _periodLabel(_financePeriod),
                  total: _expenses,
                  color: Colors.red.shade900,
                  onTap: () => _showMetricDetail(
                    title: 'Expenses · ${_periodLabel(_financePeriod)}',
                    lines: [
                      MapEntry(
                        'Refund expense',
                        formatPeso(_financeSummary['refund_expense'] ?? 0),
                      ),
                      MapEntry(
                        'Reseller commissions',
                        formatPeso(
                          _financeSummary['reseller_commissions_paid'] ?? 0,
                        ),
                      ),
                      MapEntry(
                        'Custom expenses',
                        formatPeso(_financeSummary['custom_expenses'] ?? 0),
                      ),
                      MapEntry('Total expenses', formatPeso(_expenses)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!_focused)
          const SizedBox(height: 10),
          ],

          // —— Cash on hand ——
          if (_showSection('cash')) ...[
          _DropdownSection(
            title: 'Cash on hand',
            subtitle: formatPeso(_cashOnHand),
            icon: Icons.account_balance_wallet_outlined,
            accent: scheme.primary,
            expanded: _sectionExpanded('cash'),
            locked: _focused,
            onToggle: () {
              _toggle('cash');
              if (_expanded == 'cash') {
                _setFinancePeriod(_financePeriod);
              }
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _periodChips(
                  selected: _financePeriod,
                  loading: _financeLoading,
                  onSelect: _setFinancePeriod,
                ),
                const SizedBox(height: 8),
                Text(
                  _rangeCaption(_financePeriod),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                if (_financeLoading) ...[
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(minHeight: 2),
                ],
                const SizedBox(height: 10),
                _DetailTile(
                  label: 'Cash sales',
                  countLabel:
                      '${_txnsFor(_PaymentBucket.cash, source: _financeTxns).length} payment(s)',
                  total: _financeCashSales,
                  color: Colors.green.shade700,
                  onTap: () => _openTxnList(
                    title: 'Cash sales · ${_periodLabel(_financePeriod)}',
                    rows: _txnsFor(
                      _PaymentBucket.cash,
                      source: _financeTxns,
                    ),
                    period: _financePeriod,
                  ),
                ),
                const SizedBox(height: 8),
                _DetailTile(
                  label: 'Less expenses',
                  countLabel: 'Refunds + commissions',
                  total: _expenses,
                  color: Colors.red.shade700,
                  onTap: () => _showMetricDetail(
                    title: 'Expenses deducted',
                    lines: [
                      MapEntry('Refunds', formatPeso(
                        _financeSummary['refund_expense'] ?? 0,
                      )),
                      MapEntry(
                        'Commissions',
                        formatPeso(
                          _financeSummary['reseller_commissions_paid'] ?? 0,
                        ),
                      ),
                      MapEntry('Total', formatPeso(_expenses)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _DetailTile(
                  label: 'Cash on hand',
                  countLabel: 'Cash sales − expenses',
                  total: _cashOnHand,
                  color: scheme.primary,
                  onTap: () => _showMetricDetail(
                    title: 'Cash on hand · ${_periodLabel(_financePeriod)}',
                    lines: [
                      MapEntry('Cash sales', formatPeso(_financeCashSales)),
                      MapEntry('Less expenses', formatPeso(_expenses)),
                      MapEntry('Cash on hand', formatPeso(_cashOnHand)),
                      MapEntry(
                        'Today (reference)',
                        formatPeso(
                          (_totalFor(
                                    _PaymentBucket.cash,
                                    source: _todayBookingTxns,
                                  ) -
                                  _todayExpenses)
                              .clamp(0, double.infinity),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!_focused)
          const SizedBox(height: 10),
          ],

          // —— Demographics ——
          if (_showSection('demographics')) ...[
          _DropdownSection(
            title: 'Demographics',
            subtitle: _demoSubtitle(),
            icon: Icons.groups_outlined,
            accent: Colors.cyan.shade800,
            expanded: _sectionExpanded('demographics'),
            locked: _focused,
            onToggle: () => _toggle('demographics'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _periodChips(
                  selected: _demoPeriod,
                  loading: _demoLoading,
                  onSelect: _loadDemographics,
                ),
                const SizedBox(height: 8),
                Text(
                  (_demographics['from'] != null &&
                          _demographics['to'] != null)
                      ? '${_demographics['from']} → ${_demographics['to']}'
                      : _rangeCaption(_demoPeriod),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                if (_demoLoading) ...[
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(minHeight: 2),
                ],
                const SizedBox(height: 10),
                _DemoStatTile(
                  label: 'Male guests',
                  value: '${_demoInt(['gender', 'male'])}',
                  color: Colors.blue.shade700,
                  onTap: () => _showMetricDetail(
                    title: 'Male guests',
                    lines: [
                      MapEntry('Male', '${_demoInt(['gender', 'male'])}'),
                      MapEntry(
                        'Share of known gender',
                        _genderShare('male'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _DemoStatTile(
                  label: 'Female guests',
                  value: '${_demoInt(['gender', 'female'])}',
                  color: Colors.pink.shade700,
                  onTap: () => _showMetricDetail(
                    title: 'Female guests',
                    lines: [
                      MapEntry('Female', '${_demoInt(['gender', 'female'])}'),
                      MapEntry(
                        'Share of known gender',
                        _genderShare('female'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _DemoStatTile(
                  label: 'Adults',
                  value: '${_demoInt(['age_groups', 'adults'])}',
                  color: Colors.indigo.shade700,
                  onTap: () => _showMetricDetail(
                    title: 'Age group · Adults',
                    lines: [
                      MapEntry(
                        'Adults',
                        '${_demoInt(['age_groups', 'adults'])}',
                      ),
                      MapEntry(
                        'Children',
                        '${_demoInt(['age_groups', 'children'])}',
                      ),
                      const MapEntry(
                        'Note',
                        'Exact ages are not collected; adults/children from booking forms.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _DemoStatTile(
                  label: 'Children',
                  value: '${_demoInt(['age_groups', 'children'])}',
                  color: Colors.teal.shade700,
                  onTap: () => _showMetricDetail(
                    title: 'Age group · Children',
                    lines: [
                      MapEntry(
                        'Children',
                        '${_demoInt(['age_groups', 'children'])}',
                      ),
                      MapEntry(
                        'Adults',
                        '${_demoInt(['age_groups', 'adults'])}',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Nationality',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 6),
                ..._nationalityTiles(),
                const SizedBox(height: 8),
                Text(
                  'Booking source',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 6),
                ..._bookingModeTiles(),
              ],
            ),
          ),
          if (!_focused)
          const SizedBox(height: 10),
          ],

          // —— Front desk sales ——
          if (_showSection('fo')) ...[
          _DropdownSection(
            title: 'Front desk sales',
            subtitle: 'Per FO account · cash / e-wallet / bank',
            icon: Icons.point_of_sale_outlined,
            accent: scheme.primary,
            expanded: _sectionExpanded('fo'),
            locked: _focused,
            onToggle: () => _toggle('fo'),
            child: _DetailTile(
              label: 'Front desk accounts',
              countLabel: 'Daily · weekly · monthly · annual breakdown',
              total: null,
              color: scheme.primary,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const FrontDeskSalesReportScreen(),
                  ),
                );
              },
            ),
          ),
          if (!_focused)
          const SizedBox(height: 10),
          ],

          // —— Flat analytics (no nested “Reports & analytics”) ——
          if (_showSection('room_insights')) ...[
          _DropdownSection(
            title: 'Room insights',
            subtitle: 'Most / least booked · profit · maintenance',
            icon: Icons.hotel_class_outlined,
            accent: Colors.indigo,
            expanded: _sectionExpanded('room_insights'),
            locked: _focused,
            onToggle: () => _toggle('room_insights'),
            child: _DetailTile(
              label: 'Open room insights',
              countLabel: 'Occupancy & profitability by room',
              total: null,
              color: Colors.indigo,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const RoomInsightsReportScreen(),
                ),
              ),
            ),
          ),
          if (!_focused)
          const SizedBox(height: 10),
          ],
          if (_showSection('amenities')) ...[
          _DropdownSection(
            title: 'Amenities reports',
            subtitle: 'Product sales & profit',
            icon: Icons.room_service_outlined,
            accent: Colors.teal,
            expanded: _sectionExpanded('amenities'),
            locked: _focused,
            onToggle: () => _toggle('amenities'),
            child: _DetailTile(
              label: 'Open amenities report',
              countLabel: 'Sales and margin by amenity',
              total: null,
              color: Colors.teal,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AmenitiesReportScreen(),
                ),
              ),
            ),
          ),
          ],
          if (!widget.isFrontDesk && _showSection('reseller')) ...[
            if (!_focused) const SizedBox(height: 10),
            _DropdownSection(
              title: 'Reseller commissions',
              subtitle: 'Payouts & calendar',
              icon: Icons.handshake_outlined,
              accent: Colors.deepOrange,
              expanded: _sectionExpanded('reseller'),
              locked: _focused,
              onToggle: () => _toggle('reseller'),
              child: _DetailTile(
                label: 'Open reseller commissions',
                countLabel: 'Payout history and calendar',
                total: null,
                color: Colors.deepOrange,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ResellerCommissionsReportScreen(),
                  ),
                ),
              ),
            ),
          ],
          if (_showSection('rev_daily')) ...[
            if (!_focused) const SizedBox(height: 10),
          _DropdownSection(
            title: 'Daily revenue',
            subtitle: 'Hotel-wide today',
            icon: Icons.today_outlined,
            accent: Colors.blue,
            expanded: _sectionExpanded('rev_daily'),
            locked: _focused,
            onToggle: () => _toggle('rev_daily'),
            child: _DetailTile(
              label: 'View daily revenue',
              countLabel: _rangeCaption(_ReportPeriod.daily),
              total: null,
              color: Colors.blue,
              onTap: () =>
                  _openFinancePeriod('Daily', _ReportPeriod.daily),
            ),
          ),
          if (!_focused)
          const SizedBox(height: 10),
          ],
          if (_showSection('rev_weekly')) ...[
          _DropdownSection(
            title: 'Weekly revenue',
            subtitle: 'This week',
            icon: Icons.date_range_outlined,
            accent: Colors.cyan.shade700,
            expanded: _sectionExpanded('rev_weekly'),
            locked: _focused,
            onToggle: () => _toggle('rev_weekly'),
            child: _DetailTile(
              label: 'View weekly revenue',
              countLabel: _rangeCaption(_ReportPeriod.weekly),
              total: null,
              color: Colors.cyan.shade700,
              onTap: () =>
                  _openFinancePeriod('Weekly', _ReportPeriod.weekly),
            ),
          ),
          if (!_focused)
          const SizedBox(height: 10),
          ],
          if (_showSection('rev_monthly')) ...[
          _DropdownSection(
            title: 'Monthly revenue',
            subtitle: 'This month',
            icon: Icons.calendar_month_outlined,
            accent: Colors.purple,
            expanded: _sectionExpanded('rev_monthly'),
            locked: _focused,
            onToggle: () => _toggle('rev_monthly'),
            child: _DetailTile(
              label: 'View monthly revenue',
              countLabel: _rangeCaption(_ReportPeriod.monthly),
              total: null,
              color: Colors.purple,
              onTap: () =>
                  _openFinancePeriod('Monthly', _ReportPeriod.monthly),
            ),
          ),
          if (!_focused)
          const SizedBox(height: 10),
          ],
          if (_showSection('rev_annual')) ...[
          _DropdownSection(
            title: 'Annual revenue',
            subtitle: 'This year',
            icon: Icons.insights_outlined,
            accent: Colors.brown,
            expanded: _sectionExpanded('rev_annual'),
            locked: _focused,
            onToggle: () => _toggle('rev_annual'),
            child: _DetailTile(
              label: 'View annual revenue',
              countLabel: _rangeCaption(_ReportPeriod.annual),
              total: null,
              color: Colors.brown,
              onTap: () =>
                  _openFinancePeriod('Annual', _ReportPeriod.annual),
            ),
          ),
          ],
        ],
      ),
    );
  }

  String _demoSubtitle() {
    final total = _demoInt(['totals', 'total_guests']);
    if (total <= 0 && _demographics.isEmpty) return 'Gender · nationality · age groups';
    return '$total guest(s) in period';
  }

  int _demoInt(List<String> path) {
    dynamic cur = _demographics;
    for (final key in path) {
      if (cur is! Map) return 0;
      cur = cur[key];
    }
    return (cur as num?)?.toInt() ?? 0;
  }

  String _genderShare(String key) {
    final male = _demoInt(['gender', 'male']);
    final female = _demoInt(['gender', 'female']);
    final known = male + female;
    if (known <= 0) return '—';
    final n = key == 'male' ? male : female;
    return '${((n / known) * 100).toStringAsFixed(0)}%';
  }

  List<Widget> _nationalityTiles() {
    final raw = _demographics['nationalities'];
    if (raw is! List || raw.isEmpty) {
      return [
        Text(
          'No nationality data for this period.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ];
    }
    return raw.take(8).map((row) {
      final map = Map<String, dynamic>.from(row as Map);
      final label = (map['label'] ?? 'Unknown').toString();
      final guests = (map['guests'] as num?)?.toInt() ?? 0;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _DemoStatTile(
          label: label,
          value: '$guests',
          color: Colors.cyan.shade800,
          onTap: () => _showMetricDetail(
            title: 'Nationality · $label',
            lines: [
              MapEntry('Guests', '$guests'),
              MapEntry('Period', _rangeCaption(_demoPeriod)),
            ],
          ),
        ),
      );
    }).toList();
  }

  List<Widget> _bookingModeTiles() {
    final raw = _demographics['booking_modes'];
    if (raw is! List || raw.isEmpty) {
      return [
        Text(
          'No booking-source data for this period.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ];
    }
    return raw.take(6).map((row) {
      final map = Map<String, dynamic>.from(row as Map);
      final label = (map['label'] ?? 'Unspecified').toString();
      final bookings = (map['bookings'] as num?)?.toInt() ?? 0;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _DemoStatTile(
          label: label,
          value: '$bookings',
          color: Colors.blueGrey.shade700,
          onTap: () => _showMetricDetail(
            title: 'Booking source · $label',
            lines: [
              MapEntry('Bookings', '$bookings'),
              MapEntry('Period', _rangeCaption(_demoPeriod)),
            ],
          ),
        ),
      );
    }).toList();
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text(e.key)),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        e.value,
                        textAlign: TextAlign.end,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
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
    this.locked = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;
  final bool locked;

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
            onTap: locked ? null : onToggle,
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  if (!locked)
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

class _DetailTile extends StatelessWidget {
  const _DetailTile({
    required this.label,
    required this.countLabel,
    required this.color,
    required this.onTap,
    this.total,
  });

  final String label;
  final String countLabel;
  final double? total;
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
                      countLabel,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              if (total != null)
                Text(
                  formatPeso(total!),
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

class _DemoStatTile extends StatelessWidget {
  const _DemoStatTile({
    required this.label,
    required this.value,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String value;
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
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
              Text(
                value,
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
