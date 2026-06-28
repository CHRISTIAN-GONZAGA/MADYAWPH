import 'package:flutter/material.dart';

import '../../../utils/money_format.dart';

/// Tabular display for shift / period revenue reports.
class ShiftReportTable extends StatelessWidget {
  const ShiftReportTable({
    super.key,
    required this.summary,
    required this.bookingRows,
    required this.amenityRows,
    this.periodLabel,
  });

  final Map<String, dynamic> summary;
  final List<Map<String, dynamic>> bookingRows;
  final List<Map<String, dynamic>> amenityRows;
  final String? periodLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (periodLabel != null && periodLabel!.isNotEmpty) ...[
          Text(
            periodLabel!,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 12),
        ],
        _SummaryTable(summary: summary),
        const SizedBox(height: 20),
        Text(
          'Booking transactions (${bookingRows.length})',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 8),
        _DataTable(
          columns: const [
            'Reference',
            'Guest',
            'Room',
            'Method',
            'Amount',
          ],
          rows: bookingRows.isEmpty
              ? const [
                  ['—', 'No booking payments', '', '', ''],
                ]
              : bookingRows
                  .map(
                    (r) => [
                      '${r['reference'] ?? ''}',
                      '${r['guest_name'] ?? ''}',
                      '${r['room_number'] ?? ''}',
                      '${r['payment_method'] ?? ''}',
                      formatPeso((r['amount'] as num?) ?? 0),
                    ],
                  )
                  .toList(),
          accent: scheme.primary,
        ),
        const SizedBox(height: 20),
        Text(
          'Amenity transactions (${amenityRows.length})',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 8),
        _DataTable(
          columns: const ['Item', 'Room', 'Amount', 'Sold at'],
          rows: amenityRows.isEmpty
              ? const [
                  ['No amenity sales', '', '', ''],
                ]
              : amenityRows
                  .map(
                    (r) => [
                      '${r['description'] ?? r['label'] ?? ''}',
                      '${r['room_number'] ?? ''}',
                      formatPeso((r['amount'] as num?) ?? 0),
                      _shortDate(r['paid_at']),
                    ],
                  )
                  .toList(),
          accent: scheme.tertiary,
        ),
      ],
    );
  }

  static String _shortDate(dynamic value) {
    final raw = (value ?? '').toString();
    if (raw.isEmpty) return '—';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _SummaryTable extends StatelessWidget {
  const _SummaryTable({required this.summary});

  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final rows = <List<String>>[
      ['Gross revenue', formatPeso(summary['gross_revenue'] ?? 0)],
      ['Room revenue', formatPeso(summary['room_revenue'] ?? 0)],
      ['Amenity revenue', formatPeso(summary['amenity_revenue'] ?? 0)],
      ['Refunds', formatPeso(summary['refunds'] ?? 0)],
      ['Transfer adjustments', formatPeso(summary['transfer_adjustments'] ?? 0)],
      ['Reseller payouts', formatPeso(summary['reseller_commissions_paid'] ?? 0)],
      ['Net revenue', formatPeso(summary['net_revenue'] ?? 0)],
      ['Net profit', formatPeso(summary['profit'] ?? 0)],
      ['Paid bookings', '${summary['bookings'] ?? 0}'],
    ];

    return _DataTable(
      columns: const ['Metric', 'Value'],
      rows: rows,
      accent: Theme.of(context).colorScheme.secondary,
      emphasizeLast: true,
    );
  }
}

class _DataTable extends StatelessWidget {
  const _DataTable({
    required this.columns,
    required this.rows,
    required this.accent,
    this.emphasizeLast = false,
  });

  final List<String> columns;
  final List<List<String>> rows;
  final Color accent;
  final bool emphasizeLast;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStatePropertyAll(
              accent.withValues(alpha: 0.12),
            ),
            columns: columns
                .map(
                  (c) => DataColumn(
                    label: Text(
                      c,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                )
                .toList(),
            rows: [
              for (var i = 0; i < rows.length; i++)
                DataRow(
                  cells: rows[i]
                      .map(
                        (cell) => DataCell(
                          Text(
                            cell,
                            style: emphasizeLast && i == rows.length - 1
                                ? const TextStyle(fontWeight: FontWeight.w800)
                                : null,
                          ),
                        ),
                      )
                      .toList(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
