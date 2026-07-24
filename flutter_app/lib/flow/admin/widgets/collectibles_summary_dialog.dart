import 'package:flutter/material.dart';

import '../../../utils/money_format.dart';
import '../admin_dashboard_models.dart';

/// Receipt-style summary of all checkout-queue collectibles.
Future<void> showCollectiblesSummaryDialog(
  BuildContext context, {
  required List<Map<String, dynamic>> rooms,
}) {
  final lines = AdminDashboardModels.collectiblesSummaryLines(rooms);
  final total = AdminDashboardModels.collectiblesForRooms(rooms);
  final now = DateTime.now();
  final generatedAt =
      '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
      '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: const Text('Collectibles summary'),
        content: SizedBox(
          width: 420,
          child: lines.isEmpty
              ? const Text('No amounts due in the checkout queue right now.')
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Guests due for checkout',
                        style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      Text(
                        'Generated $generatedAt',
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      ...lines.map((entry) {
                        final charges =
                            (entry['charges'] as List?)?.whereType<Map>() ??
                                const [];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Room ${entry['room_number']}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  [
                                    (entry['guest_name'] ?? 'Guest').toString(),
                                    if ((entry['booking_reference'] ?? '')
                                        .toString()
                                        .isNotEmpty)
                                      entry['booking_reference'].toString(),
                                    if ((entry['check_out'] ?? '')
                                            .toString()
                                            .isNotEmpty &&
                                        entry['check_out'] != '—')
                                      'Out ${entry['check_out']}',
                                  ].join(' · '),
                                  style: Theme.of(ctx).textTheme.bodySmall,
                                ),
                                const Divider(height: 16),
                                ...charges.map((c) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            (c['label'] ?? 'Charge').toString(),
                                          ),
                                        ),
                                        Text(
                                          formatBillLineAmount(c),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        'Room total',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      formatPeso(
                                        parseJsonDouble(entry['total']),
                                      ),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: scheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      const Divider(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Total amount due',
                              style: Theme.of(ctx)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          Text(
                            formatPeso(total),
                            style: Theme.of(ctx)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: scheme.primary,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${lines.length} room(s) · due within 30 min or in '
                        '${AdminDashboardModels.checkoutGraceMinutes}-min grace',
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}
