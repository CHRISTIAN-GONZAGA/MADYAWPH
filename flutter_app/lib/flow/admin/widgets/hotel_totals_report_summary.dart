import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../dio_client.dart';
import '../../../utils/money_format.dart';
import '../admin_dashboard_models.dart';

/// Inline Hotel totals report summary (no tap required).
/// Shows each FO’s cash / e-wallet / bank sales plus hotel collectibles,
/// expenses, and cash on hand — matching the paper report layout.
class HotelTotalsReportSummary extends StatefulWidget {
  const HotelTotalsReportSummary({
    super.key,
    required this.rooms,
  });

  final List<Map<String, dynamic>> rooms;

  @override
  State<HotelTotalsReportSummary> createState() =>
      _HotelTotalsReportSummaryState();
}

class _HotelTotalsReportSummaryState extends State<HotelTotalsReportSummary> {
  bool _loading = true;
  String? _error;
  List<_FoSalesRow> _accounts = const [];
  double _expenses = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant HotelTotalsReportSummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rooms != widget.rooms) {
      // Collectibles are derived from rooms; expenses/sales refresh on pull.
    }
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final today = DateUtils.dateOnly(DateTime.now());
      final end = DateTime(today.year, today.month, today.day, 23, 59, 59, 999);
      final results = await Future.wait([
        portalDio().get<Map<String, dynamic>>(
          '/reports/frontdesk-sales/summary',
          queryParameters: {
            'granularity': 'day',
            'anchor_date': _fmt(today),
          },
        ),
        portalDio().get<Map<String, dynamic>>(
          '/reports/shift-summary',
          queryParameters: {
            'time_in': today.toIso8601String(),
            'time_out': end.toIso8601String(),
          },
        ),
      ]);
      if (!mounted) return;

      final foData = results[0].data ?? const <String, dynamic>{};
      final shift = results[1].data ?? const <String, dynamic>{};
      final summary =
          (shift['summary'] as Map?)?.cast<String, dynamic>() ?? const {};
      final expenses = parseJsonDouble(summary['expenses']);
      final fallbackExpenses = parseJsonDouble(summary['refund_expense']) +
          parseJsonDouble(summary['reseller_commissions_paid']);

      final accounts = ((foData['accounts'] as List?) ?? const [])
          .whereType<Map>()
          .map((raw) {
            final row = Map<String, dynamic>.from(raw);
            final methods = (row['by_payment_method'] as Map?) ?? const {};
            double methodTotal(String key) {
              final direct = row[key];
              if (direct != null) return parseJsonDouble(direct);
              final nested = methods[key];
              if (nested is Map) return parseJsonDouble(nested['total']);
              return 0;
            }

            return _FoSalesRow(
              username: (row['username'] ?? 'Front desk').toString(),
              cash: methodTotal('cash'),
              ewallet: methodTotal('ewallet'),
              bankTransfer: methodTotal('bank_transfer'),
            );
          })
          .toList();

      setState(() {
        _accounts = accounts;
        _expenses = expenses > 0.009 ? expenses : fallbackExpenses;
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

  double get _totalCash =>
      _accounts.fold<double>(0, (sum, a) => sum + a.cash);

  double get _cashOnHand =>
      (_totalCash - _expenses).clamp(0, double.infinity);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.receipt_long_outlined, color: scheme.primary, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Report summary',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
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
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_error != null) ...[
          Text(
            _error!,
            style: TextStyle(color: scheme.error, fontSize: 12),
          ),
          TextButton(onPressed: _load, child: const Text('Retry')),
        ] else ...[
          if (_accounts.isEmpty)
            _ReportSummaryCard(
              title: 'REPORT SUMMARY',
              rows: [
                const _ReportLine(label: 'SALES — CASH', amount: 0),
                const _ReportLine(label: 'EWALLET', amount: 0),
                const _ReportLine(label: 'BANK TRANSFER', amount: 0),
                _ReportLine(label: 'COLLECTIBLES', amount: _collectibles),
                _ReportLine(label: 'EXPENSES', amount: _expenses),
                _ReportLine(label: 'CASH ON HAND', amount: _cashOnHand),
              ],
            )
          else ...[
            for (var i = 0; i < _accounts.length; i++) ...[
              Padding(
                padding: EdgeInsets.only(
                  bottom: i == _accounts.length - 1 ? 0 : 8,
                ),
                child: _ReportSummaryCard(
                  title:
                      'REPORT SUMMARY — ${_accounts[i].username.toUpperCase()}',
                  rows: [
                    _ReportLine(
                      label: 'SALES — CASH',
                      amount: _accounts[i].cash,
                    ),
                    _ReportLine(
                      label: 'EWALLET',
                      amount: _accounts[i].ewallet,
                    ),
                    _ReportLine(
                      label: 'BANK TRANSFER',
                      amount: _accounts[i].bankTransfer,
                    ),
                    if (i == _accounts.length - 1) ...[
                      _ReportLine(
                        label: 'COLLECTIBLES',
                        amount: _collectibles,
                      ),
                      _ReportLine(label: 'EXPENSES', amount: _expenses),
                      _ReportLine(
                        label: 'CASH ON HAND',
                        amount: _cashOnHand,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ],
      ],
    );
  }
}

class _FoSalesRow {
  const _FoSalesRow({
    required this.username,
    required this.cash,
    required this.ewallet,
    required this.bankTransfer,
  });

  final String username;
  final double cash;
  final double ewallet;
  final double bankTransfer;
}

class _ReportLine {
  const _ReportLine({required this.label, required this.amount});

  final String label;
  final double amount;
}

class _ReportSummaryCard extends StatelessWidget {
  const _ReportSummaryCard({
    required this.title,
    required this.rows,
  });

  final String title;
  final List<_ReportLine> rows;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3,
                    ),
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Text(
                        rows[i].label,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    Text(
                      formatPeso(rows[i].amount),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: scheme.primary,
                          ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
