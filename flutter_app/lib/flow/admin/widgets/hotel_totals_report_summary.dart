import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../dio_client.dart';
import '../../../utils/money_format.dart';

/// Inline Hotel totals report summary for **timed-in** front desk only.
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

  @override
  void initState() {
    super.initState();
    _load();
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
      final res = await portalDio().get<Map<String, dynamic>>(
        '/reports/frontdesk-sales/timed-in-summary',
        queryParameters: {'anchor_date': _fmt(today)},
      );
      if (!mounted) return;

      final accounts = ((res.data?['accounts'] as List?) ?? const [])
          .whereType<Map>()
          .map((raw) {
            final row = Map<String, dynamic>.from(raw);
            return _FoSalesRow(
              username: (row['username'] ?? 'Front desk').toString(),
              cash: parseJsonDouble(row['cash_sales'] ?? row['cash']),
              ewallet: parseJsonDouble(row['ewallet_sales'] ?? row['ewallet']),
              bookingSales:
                  parseJsonDouble(row['booking_sales'] ?? row['room_sales']),
              expenses: parseJsonDouble(row['expenses']),
              cashOnHand: parseJsonDouble(row['cash_on_hand']),
            );
          })
          .toList();

      setState(() {
        _accounts = accounts;
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
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.receipt_long_outlined, color: scheme.primary, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Report summary',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  Text(
                    'Timed-in front desk only',
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
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_error != null) ...[
          Text(
            _error!,
            style: TextStyle(color: scheme.error, fontSize: 12),
          ),
          TextButton(onPressed: _load, child: const Text('Retry')),
        ] else if (_accounts.isEmpty)
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                'No front desk is timed in right now.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          )
        else
          for (var i = 0; i < _accounts.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _ReportSummaryCard(
              title:
                  'REPORT SUMMARY — ${_accounts[i].username.toUpperCase()}',
              rows: [
                _ReportLine(
                  label: 'CASH SALES',
                  amount: _accounts[i].cash,
                ),
                _ReportLine(
                  label: 'E-WALLET SALES',
                  amount: _accounts[i].ewallet,
                ),
                _ReportLine(
                  label: 'BOOKING SALES',
                  amount: _accounts[i].bookingSales,
                ),
                _ReportLine(
                  label: 'EXPENSES',
                  amount: _accounts[i].expenses,
                ),
                _ReportLine(
                  label: 'CASH ON HAND',
                  amount: _accounts[i].cashOnHand,
                ),
              ],
            ),
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
    required this.bookingSales,
    required this.expenses,
    required this.cashOnHand,
  });

  final String username;
  final double cash;
  final double ewallet;
  final double bookingSales;
  final double expenses;
  final double cashOnHand;
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
