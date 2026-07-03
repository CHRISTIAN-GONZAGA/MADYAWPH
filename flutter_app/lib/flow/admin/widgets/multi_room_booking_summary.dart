import 'package:flutter/material.dart';

import 'hourly_billing.dart';

typedef MultiRoomChargeLine = ({String roomNumber, double amount});

List<MultiRoomChargeLine> computeMultiRoomChargeLines({
  required List<Map<String, dynamic>> rooms,
  required DateTime checkIn,
  required DateTime checkOut,
}) {
  final lines = <MultiRoomChargeLine>[];
  for (final room in rooms) {
    final roomNo = (room['room_number'] ?? '—').toString();
    lines.add((
      roomNumber: roomNo,
      amount: HourlyBilling.customerDateStayCharge(room, checkIn, checkOut),
    ));
  }
  lines.sort((a, b) => a.roomNumber.compareTo(b.roomNumber));
  return lines;
}

double multiRoomGrossTotal(List<MultiRoomChargeLine> lines) =>
    lines.fold<double>(0, (sum, line) => sum + line.amount);

String formatPeso(double amount) => '₱${amount.toStringAsFixed(2)}';

/// Per-room breakdown and total amount due for a group walk-in booking.
class MultiRoomBookingTotalSummary extends StatelessWidget {
  const MultiRoomBookingTotalSummary({
    super.key,
    required this.rooms,
    required this.checkIn,
    required this.checkOut,
    this.discountPercent = 0,
    this.compact = false,
  });

  final List<Map<String, dynamic>> rooms;
  final DateTime checkIn;
  final DateTime checkOut;
  final double discountPercent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final lines = computeMultiRoomChargeLines(
      rooms: rooms,
      checkIn: checkIn,
      checkOut: checkOut,
    );
    final gross = multiRoomGrossTotal(lines);
    final discount = discountPercent.clamp(0, 100);
    final net = discount > 0
        ? HourlyBilling.round50(gross * (1 - discount / 100))
        : gross;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      color: scheme.primaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Booking summary',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            if (!compact)
              ...lines.map(
                (line) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Room ${line.roomNumber}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      Text(
                        formatPeso(line.amount),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            if (!compact) const Divider(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    compact
                        ? '${rooms.length} rooms'
                        : 'Subtotal (${rooms.length} rooms)',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                Text(
                  formatPeso(gross),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            if (discount > 0) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Discount (${discount.toStringAsFixed(0)}%)',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Text(
                    '−${formatPeso(gross - net)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Total amount due',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                Text(
                  formatPeso(net),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
  }
}
