import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';

import '../../../dio_client.dart';
import '../../../utils/money_format.dart';
import '../../../widgets/admin_month_calendar.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/app_scaffold.dart';
import '../../../widgets/app_state_views.dart';

/// Frontdesk sales: account list → per-account daily/weekly/monthly/annual + calendar.
class FrontDeskSalesReportScreen extends StatefulWidget {
  const FrontDeskSalesReportScreen({super.key});

  @override
  State<FrontDeskSalesReportScreen> createState() =>
      _FrontDeskSalesReportScreenState();
}

class _FrontDeskSalesReportScreenState extends State<FrontDeskSalesReportScreen> {
  DateTime _anchor = DateUtils.dateOnly(DateTime.now());
  Map<String, dynamic>? _summary;
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
      final res = await portalDio().get<Map<String, dynamic>>(
        '/reports/frontdesk-sales/summary',
        queryParameters: {
          'granularity': 'day',
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
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          Text(
            'Front desk accounts',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap an account to open that person’s daily, weekly, monthly, and annual sales — not hotel-wide totals.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Reference date'),
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
                      label: 'Today’s sales',
                      value:
                          '₱${parseJsonDouble(totals['display_total'] ?? totals['sales']).toStringAsFixed(2)}',
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
            final sales = parseJsonDouble(
              row['display_total'] ?? row['total_sales'],
            );
            final orders = row['order_count'] ?? 0;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'F',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  'Today: ₱${sales.toStringAsFixed(2)} · $orders orders\n'
                  'Cash · e-wallet · bank · daily → annual',
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => FrontDeskAccountSalesScreen(
                        userId: (row['user_id'] ?? '').toString(),
                        username: name,
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

class FrontDeskAccountSalesScreen extends StatefulWidget {
  const FrontDeskAccountSalesScreen({
    super.key,
    required this.userId,
    required this.username,
    required this.initialAnchor,
  });

  final String userId;
  final String username;
  final DateTime initialAnchor;

  @override
  State<FrontDeskAccountSalesScreen> createState() =>
      _FrontDeskAccountSalesScreenState();
}

class _FrontDeskAccountSalesScreenState
    extends State<FrontDeskAccountSalesScreen> {
  late DateTime _anchor;
  late DateTime _month;
  Map<String, dynamic>? _overview;
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
    _anchor = DateUtils.dateOnly(widget.initialAnchor);
    _month = DateTime(_anchor.year, _anchor.month);
    _selectedDay = _anchor;
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        portalDio().get<Map<String, dynamic>>(
          '/reports/frontdesk-sales/account-overview',
          queryParameters: {
            'user_id': widget.userId,
            'anchor_date': _fmt(_anchor),
          },
        ),
        portalDio().get<Map<String, dynamic>>(
          '/reports/frontdesk-sales/calendar',
          queryParameters: {
            'user_id': widget.userId,
            'month': _fmt(_month),
          },
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _overview = results[0].data;
        _calendar = results[1].data;
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
      map[date] = parseJsonDouble(
        raw['display_total'] ??
            (parseJsonDouble(raw['total_sales']) +
                parseJsonDouble(raw['payments_collected'])),
      );
    }
    return map;
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'room':
        return 'Room charges';
      case 'amenity':
        return 'Amenities';
      case 'manual':
        return 'Manual charges';
      case 'extend-stay':
        return 'Extend stay';
      case 'partial_payment':
      case 'partial-payment':
        return 'Payments collected';
      case 'early_check_in':
      case 'early-check-in':
        return 'Early check-in';
      case 'late_checkout':
      case 'late_check_out':
      case 'late-checkout':
        return 'Late checkout';
      default:
        return type.replaceAll('_', ' ').replaceAll('-', ' ');
    }
  }

  List<Map<String, dynamic>> _transactionsForMethod(
    Map<String, dynamic> period,
    String methodKey,
  ) {
    final raw = period['transactions'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((tx) {
          final bucket = (tx['payment_method_bucket'] ?? '').toString();
          if (bucket.isNotEmpty) return bucket == methodKey;
          return _paymentMethodBucket(
                (tx['payment_method'] ?? '').toString(),
              ) ==
              methodKey;
        })
        .toList();
  }

  String _paymentMethodBucket(String method) {
    final m = method.toLowerCase().trim();
    if (m == 'cash') return 'cash';
    if (m.contains('gcash') ||
        m.contains('g-cash') ||
        m.contains('paymaya') ||
        m.contains('maya') ||
        m.contains('ewallet') ||
        m.contains('e-wallet') ||
        m.contains('wallet')) {
      return 'ewallet';
    }
    if (m.contains('bank') || m.contains('transfer')) {
      return 'bank_transfer';
    }
    return 'other';
  }

  void _openMethodTransactions({
    required String title,
    required String range,
    required List<Map<String, dynamic>> rows,
  }) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          minChildSize: 0.4,
          maxChildSize: 0.94,
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
                      '${rows.length} transaction(s) · $range',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  ),
                  Expanded(
                    child: rows.isEmpty
                        ? const Center(child: Text('No transactions yet.'))
                        : ListView(
                            controller: sc,
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            children: _groupedTransactionWidgets(rows),
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

  List<Widget> _paymentMethodRows(
    Map<String, dynamic> summary, {
    Map<String, dynamic>? period,
    String? periodTitle,
  }) {
    final raw = summary['by_payment_method'];
    if (raw is! Map) return const [];
    final labels = <String, String>{
      'cash': 'Cash',
      'ewallet': 'E-wallet (GCash / PayMaya)',
      'bank_transfer': 'Bank transfer',
      'other': 'Other',
    };
    final scheme = Theme.of(context).colorScheme;
    final out = <Widget>[];
    for (final entry in labels.entries) {
      final row = raw[entry.key];
      if (row is! Map) continue;
      final count = (row['count'] as num?)?.toInt() ?? 0;
      final total = parseJsonDouble(row['total']);
      if (count == 0 && total <= 0) continue;

      final byType = row['by_type'];
      final typeLines = <Widget>[];
      if (byType is Map) {
        final entries = byType.entries
            .whereType<MapEntry>()
            .map((e) => MapEntry(e.key.toString(), e.value))
            .toList()
          ..sort((a, b) {
            final at = a.value is Map
                ? parseJsonDouble((a.value as Map)['total'])
                : 0.0;
            final bt = b.value is Map
                ? parseJsonDouble((b.value as Map)['total'])
                : 0.0;
            return bt.compareTo(at);
          });
        for (final typeEntry in entries) {
          final typeRow = typeEntry.value;
          if (typeRow is! Map) continue;
          final typeCount = (typeRow['count'] as num?)?.toInt() ?? 0;
          final typeTotal = parseJsonDouble(typeRow['total']);
          if (typeCount == 0 && typeTotal <= 0) continue;
          typeLines.add(
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_typeLabel(typeEntry.key)} · $typeCount',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                  Text(
                    '₱${typeTotal.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ),
          );
        }
      }

      final txns = period == null
          ? const <Map<String, dynamic>>[]
          : _transactionsForMethod(period, entry.key);
      final from = (period?['from'] ?? '').toString();
      final to = (period?['to'] ?? '').toString();
      final range = from.isEmpty
          ? ''
          : (from == to ? from : '$from → $to');
      final titlePrefix = periodTitle == null || periodTitle.isEmpty
          ? entry.value
          : '${entry.value} · $periodTitle';

      out.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: period == null
                  ? null
                  : () => _openMethodTransactions(
                        title: titlePrefix,
                        range: range,
                        rows: txns,
                      ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${entry.value} · $count txn${count == 1 ? '' : 's'}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          '₱${total.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        if (period != null) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ],
                    ),
                    if (typeLines.isNotEmpty) ...typeLines,
                    if (period != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Tap to view all $count transaction(s)',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (out.isEmpty) {
      out.add(
        const Text(
          'No payment-method breakdown for this period yet.',
          style: TextStyle(fontStyle: FontStyle.italic),
        ),
      );
    }
    return out;
  }

  List<Widget> _groupedTransactionWidgets(List<Map<String, dynamic>> rows) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final tx in rows) {
      final key = (tx['type_label'] ?? tx['category'] ?? _typeLabel((tx['type'] ?? '').toString()))
          .toString();
      groups.putIfAbsent(key, () => []).add(tx);
    }
    final keys = groups.keys.toList()
      ..sort((a, b) {
        final at = groups[a]!.fold<double>(
          0,
          (s, t) => s + parseJsonDouble(t['amount']),
        );
        final bt = groups[b]!.fold<double>(
          0,
          (s, t) => s + parseJsonDouble(t['amount']),
        );
        return bt.compareTo(at);
      });

    return [
      for (final key in keys)
        Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ExpansionTile(
            initiallyExpanded: keys.length <= 2,
            title: Text(
              key,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              '${groups[key]!.length} txn(s) · ₱${groups[key]!.fold<double>(0, (s, t) => s + parseJsonDouble(t['amount'])).toStringAsFixed(2)}',
            ),
            children: [
              for (final tx in groups[key]!) _transactionTile(tx),
            ],
          ),
        ),
    ];
  }

  Widget _transactionTile(Map<String, dynamic> tx) {
    final complimentary = tx['complimentary'] == true;
    final amount = parseJsonDouble(tx['amount']);
    final method = (tx['payment_method'] ?? '').toString().trim();
    final room = (tx['room_number'] ?? '').toString().trim();
    final category = (tx['room_category'] ?? '').toString().trim();
    final guest = (tx['guest_name'] ?? '').toString().trim();
    final created = (tx['created_at'] ?? '').toString();
    return ListTile(
      dense: true,
      title: Text(
        (tx['label'] ?? tx['type_label'] ?? tx['type'] ?? 'Charge').toString(),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        [
          if (room.isNotEmpty) 'Room $room',
          if (category.isNotEmpty) category,
          if (guest.isNotEmpty) guest,
          if (method.isNotEmpty) method,
          if (created.isNotEmpty)
            created.length >= 10 ? created.substring(0, 10) : created,
          if (complimentary) 'Complimentary',
        ].where((s) => s.isNotEmpty).join(' · '),
      ),
      trailing: Text(
        complimentary ? 'Free' : '₱${amount.toStringAsFixed(2)}',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _breakdownExpansion({
    required String title,
    required String subtitle,
    required List<Widget> children,
    bool initiallyExpanded = false,
  }) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(top: 8),
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        tilePadding: const EdgeInsets.symmetric(horizontal: 10),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle),
        children: children,
      ),
    );
  }

  List<Widget> _categoryRows(List? raw, {required String Function(Map) labelOf}) {
    if (raw == null) return const [];
    final out = <Widget>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      final count = (m['count'] as num?)?.toInt() ?? 0;
      final total = parseJsonDouble(m['total']);
      if (count == 0 && total <= 0) continue;
      out.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${labelOf(m)} · $count',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '₱${total.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      );
    }
    return out;
  }

  Widget _periodTile(
    BuildContext context, {
    required String title,
    required Map<String, dynamic> period,
    required Color accent,
  }) {
    final from = (period['from'] ?? '').toString();
    final to = (period['to'] ?? '').toString();
    final range = from == to ? from : '$from → $to';
    final byType = period['by_charge_type'] is List
        ? period['by_charge_type'] as List
        : const [];
    final byRoom = period['by_room'] is List ? period['by_room'] as List : const [];
    final byCategory =
        period['by_category'] is List ? period['by_category'] as List : const [];

    return AppSectionCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(range, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 10),
            Text(
              '₱${parseJsonDouble(period['display_total'] ?? period['total_sales']).toStringAsFixed(2)}',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Sales ₱${parseJsonDouble(period['total_sales']).toStringAsFixed(2)}'
              ' · Payments ₱${parseJsonDouble(period['payments_collected']).toStringAsFixed(2)}'
              ' · ${period['order_count'] ?? 0} orders',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            _breakdownExpansion(
              title: 'By charge type',
              subtitle: 'Room stay, amenities, payments, fees',
              initiallyExpanded: true,
              children: _categoryRows(
                byType,
                labelOf: (m) =>
                    (m['label'] ?? m['key'] ?? '—').toString(),
              ),
            ),
            _breakdownExpansion(
              title: 'By room',
              subtitle: 'Which rooms contributed',
              children: _categoryRows(
                byRoom,
                labelOf: (m) {
                  final no = (m['room_number'] ?? '—').toString();
                  final cat = (m['room_category'] ?? '').toString();
                  return cat.isEmpty || cat == '—'
                      ? 'Room $no'
                      : 'Room $no ($cat)';
                },
              ),
            ),
            _breakdownExpansion(
              title: 'By room category',
              subtitle: 'Totals per room type / category',
              children: _categoryRows(
                byCategory,
                labelOf: (m) => (m['label'] ?? '—').toString(),
              ),
            ),
            if (period['by_payment_method'] is Map)
              _breakdownExpansion(
                title: 'By payment method',
                subtitle: 'Tap a method for full transaction list',
                initiallyExpanded: true,
                children: _paymentMethodRows(
                  period,
                  period: period,
                  periodTitle: title,
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final byDay = _salesByDay();
    final periods =
        (_overview?['periods'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
    final summary =
        (_dayDetail?['summary'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
    final transactions = (_dayDetail?['transactions'] as List?) ?? const [];

    Map<String, dynamic> periodOf(String key) {
      final raw = periods[key];
      if (raw is Map) return Map<String, dynamic>.from(raw);
      return const {};
    }

    return AppScaffold(
      appBar: AppBar(
        title: Text(widget.username),
        actions: [
          IconButton(onPressed: _loadAll, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const AppLoadingView()
          : _error != null
              ? AppErrorView(message: _error!, onRetry: _loadAll)
              : RefreshIndicator(
                  onRefresh: _loadAll,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                    children: [
                      Text(
                        'Sales for ${widget.username}',
                        style:
                            Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tap an account for that FO’s daily, weekly, monthly, and annual sales — including cash, e-wallet, and bank transfer.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Anchor date'),
                        subtitle: Text(_fmt(_anchor)),
                        trailing: const Icon(Icons.calendar_today),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            firstDate: DateTime(2020),
                            lastDate:
                                DateTime.now().add(const Duration(days: 1)),
                            initialDate: _anchor,
                          );
                          if (picked == null) return;
                          setState(() {
                            _anchor = DateUtils.dateOnly(picked);
                            _month = DateTime(_anchor.year, _anchor.month);
                            _selectedDay = _anchor;
                          });
                          await _loadAll();
                        },
                      ),
                      const SizedBox(height: 8),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final wide = constraints.maxWidth >= 520;
                          final tileWidth = wide
                              ? (constraints.maxWidth - 12) / 2
                              : constraints.maxWidth;
                          return Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              SizedBox(
                                width: tileWidth,
                                child: _periodTile(
                                  context,
                                  title: 'Daily',
                                  period: periodOf('daily'),
                                  accent: scheme.primary,
                                ),
                              ),
                              SizedBox(
                                width: tileWidth,
                                child: _periodTile(
                                  context,
                                  title: 'Weekly',
                                  period: periodOf('weekly'),
                                  accent: scheme.tertiary,
                                ),
                              ),
                              SizedBox(
                                width: tileWidth,
                                child: _periodTile(
                                  context,
                                  title: 'Monthly',
                                  period: periodOf('monthly'),
                                  accent: const Color(0xFF00897B),
                                ),
                              ),
                              SizedBox(
                                width: tileWidth,
                                child: _periodTile(
                                  context,
                                  title: 'Annual',
                                  period: periodOf('annual'),
                                  accent: const Color(0xFF6A1B9A),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Sales calendar',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tap a day to see charges recorded by this account.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      AdminMonthCalendar(
                        focusedMonth: _month,
                        selectedDay: _selectedDay ?? _anchor,
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
                          _loadAll();
                        },
                        onDaySelected: _loadDay,
                      ),
                      const SizedBox(height: 16),
                      if (_selectedDay != null) ...[
                        Text(
                          'Detail · ${_fmt(_selectedDay!)}',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
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
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _Metric(
                                          label: 'Sales',
                                          value:
                                              '₱${parseJsonDouble(summary['display_total'] ?? summary['total_sales']).toStringAsFixed(2)}',
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
                                  if (summary['by_charge_type'] is List)
                                    _breakdownExpansion(
                                      title: 'By charge type',
                                      subtitle: 'Room stay, amenities, payments',
                                      initiallyExpanded: true,
                                      children: _categoryRows(
                                        summary['by_charge_type'] as List,
                                        labelOf: (m) =>
                                            (m['label'] ?? m['key'] ?? '—')
                                                .toString(),
                                      ),
                                    ),
                                  if (summary['by_room'] is List)
                                    _breakdownExpansion(
                                      title: 'By room',
                                      subtitle: 'Which rooms contributed',
                                      children: _categoryRows(
                                        summary['by_room'] as List,
                                        labelOf: (m) {
                                          final no =
                                              (m['room_number'] ?? '—').toString();
                                          final cat =
                                              (m['room_category'] ?? '').toString();
                                          return cat.isEmpty || cat == '—'
                                              ? 'Room $no'
                                              : 'Room $no ($cat)';
                                        },
                                      ),
                                    ),
                                  if (summary['by_category'] is List)
                                    _breakdownExpansion(
                                      title: 'By room category',
                                      subtitle: 'Totals per category',
                                      children: _categoryRows(
                                        summary['by_category'] as List,
                                        labelOf: (m) =>
                                            (m['label'] ?? '—').toString(),
                                      ),
                                    ),
                                  if (summary['by_payment_method'] is Map)
                                    _breakdownExpansion(
                                      title: 'By payment method',
                                      subtitle:
                                          'Tap a method for full transaction list',
                                      initiallyExpanded: true,
                                      children: _paymentMethodRows(
                                        summary,
                                        period: {
                                          'from': (_dayDetail?['from'] ?? '')
                                              .toString(),
                                          'to':
                                              (_dayDetail?['to'] ?? '').toString(),
                                          'transactions': transactions,
                                          'by_payment_method':
                                              summary['by_payment_method'],
                                        },
                                        periodTitle: 'Selected day',
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
                            )
                          else
                            ..._groupedTransactionWidgets(
                              transactions
                                  .whereType<Map>()
                                  .map((e) => Map<String, dynamic>.from(e))
                                  .toList(),
                            ),
                        ],
                      ],
                    ],
                  ),
                ),
    );
  }
}
