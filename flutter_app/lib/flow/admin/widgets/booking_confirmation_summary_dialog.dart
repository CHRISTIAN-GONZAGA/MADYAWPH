import 'package:flutter/material.dart';

import '../../../utils/money_format.dart';
import 'hourly_billing.dart';
import 'multi_room_booking_summary.dart' hide formatPeso;

/// Date label like "17 Jan".
String formatBookingSummaryDate(DateTime d) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]}';
}

class BookingSummaryLine {
  const BookingSummaryLine({
    required this.label,
    required this.amount,
    this.subtitle,
  });

  final String label;
  final double amount;
  final String? subtitle;
}

/// Pre-confirm booking summary (walk-in / B2B), shown after deposit when checking in.
Future<bool> showBookingConfirmationSummary({
  required BuildContext context,
  required String title,
  required String guestName,
  required DateTime checkIn,
  required DateTime checkOut,
  required double totalAmount,
  required List<BookingSummaryLine> lines,
  String? roomLabel,
  String? paymentMethod,
  String? accountLabel,
  double? amountTendered,
  double? changeDue,
  bool checkInNow = true,
  String confirmLabel = 'Confirm & check in',
}) async {
  final nights = checkOut.difference(checkIn).inDays;
  final safeNights = nights > 0 ? nights : 1;
  final hours = checkOut.difference(checkIn).inHours;
  final durationBadge = nights > 0
      ? '${safeNights.toString().padLeft(2, '0')} Night${safeNights == 1 ? '' : 's'}'
      : '${(hours < 1 ? 1 : hours).toString().padLeft(2, '0')} Hr';

  final tendered = amountTendered ?? 0;
  final change = changeDue ??
      (tendered > 0 && totalAmount > 0
          ? (tendered - totalAmount).clamp(0, double.infinity)
          : 0.0);
  final remaining = tendered > 0
      ? (totalAmount - tendered).clamp(0, double.infinity)
      : totalAmount;

  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      var expanded = true;
      return StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          titlePadding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
          contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: Text(title),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (roomLabel != null && roomLabel.trim().isNotEmpty)
                    Text(
                      roomLabel,
                      style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  if (guestName.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      guestName,
                      style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ],
                  if (accountLabel != null && accountLabel.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      accountLabel,
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Total bill amount',
                          style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.receipt_long_outlined,
                              size: 22,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                formatPeso(totalAmount),
                                style: Theme.of(ctx)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: scheme.primary,
                                    ),
                              ),
                            ),
                            InkWell(
                              onTap: () =>
                                  setLocal(() => expanded = !expanded),
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 4,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Summary',
                                      style: Theme.of(ctx)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    Icon(
                                      expanded
                                          ? Icons.keyboard_arrow_up
                                          : Icons.keyboard_arrow_down,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (expanded) ...[
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Check-in',
                                      style: Theme.of(ctx)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                    Text(
                                      formatBookingSummaryDate(checkIn),
                                      style: Theme.of(ctx)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: scheme.primary.withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.schedule,
                                      size: 16,
                                      color: scheme.primary,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      durationBadge,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: scheme.primary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      'Check-out',
                                      style: Theme.of(ctx)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                    Text(
                                      formatBookingSummaryDate(checkOut),
                                      style: Theme.of(ctx)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: CustomPaint(
                              size: const Size(double.infinity, 1),
                              painter: _DashedLinePainter(
                                color: scheme.primary.withValues(alpha: 0.35),
                              ),
                            ),
                          ),
                          ...lines.map(
                            (line) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          line.label,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        if (line.subtitle != null &&
                                            line.subtitle!.isNotEmpty)
                                          Text(
                                            line.subtitle!,
                                            style: Theme.of(ctx)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color:
                                                      scheme.onSurfaceVariant,
                                                ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    formatPeso(line.amount),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (paymentMethod != null &&
                              paymentMethod.trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Payment method',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  Text(paymentMethod),
                                ],
                              ),
                            ),
                          if (tendered > 0.009) ...[
                            Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'Amount given',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Text(
                                  formatPeso(tendered),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (change > 0.009)
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Change given',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: scheme.primary,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    formatPeso(change),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: scheme.primary,
                                    ),
                                  ),
                                ],
                              )
                            else if (remaining > 0.009)
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Remaining after deposit',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    formatPeso(remaining),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              )
                            else
                              Text(
                                'Paid in full',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: scheme.primary,
                                ),
                              ),
                          ],
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    checkInNow
                        ? 'Review the stay details, then confirm check-in.'
                        : 'Review the stay details, then confirm this booking.',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Back'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(confirmLabel),
            ),
          ],
        ),
      );
    },
  );

  return confirmed == true;
}

/// Build summary lines for one or more rooms.
List<BookingSummaryLine> bookingSummaryLinesForRooms({
  required List<Map<String, dynamic>> rooms,
  required DateTime checkIn,
  required DateTime checkOut,
  double discountPercent = 0,
}) {
  final lines = <BookingSummaryLine>[];
  for (final room in rooms) {
    final roomNo = (room['room_number'] ?? '—').toString();
    final amount = HourlyBilling.customerDateStayCharge(room, checkIn, checkOut);
    if (HourlyBilling.isHourly(room)) {
      final blocks = HourlyBilling.blocksForStay(
        HourlyBilling.stayHours(checkIn, checkOut),
        HourlyBilling.blockHours(room),
      );
      lines.add(
        BookingSummaryLine(
          label: 'Room $roomNo · $blocks block${blocks == 1 ? '' : 's'}',
          subtitle:
              'Per block: ${formatPeso(HourlyBilling.pricePerBlock(room))}',
          amount: amount,
        ),
      );
    } else {
      final nights = checkOut.difference(checkIn).inDays;
      final safeNights = nights > 0 ? nights : 1;
      final nightly = parseJsonDouble(room['price_per_night']);
      lines.add(
        BookingSummaryLine(
          label: 'Room $roomNo · $safeNights night${safeNights == 1 ? '' : 's'}',
          subtitle: 'Per night: ${formatPeso(nightly)}',
          amount: amount,
        ),
      );
    }
  }

  final gross = multiRoomGrossTotal(
    computeMultiRoomChargeLines(rooms: rooms, checkIn: checkIn, checkOut: checkOut),
  );
  final discount = discountPercent.clamp(0, 100);
  if (discount > 0.009) {
    final net = HourlyBilling.round50(gross * (1 - discount / 100));
    final saved = HourlyBilling.round50(gross - net);
    lines.add(
      BookingSummaryLine(
        label: 'Discount (${discount.toStringAsFixed(0)}%)',
        subtitle: 'Applied to stay total',
        amount: -saved,
      ),
    );
  }
  return lines;
}

double bookingSummaryNetTotal({
  required List<Map<String, dynamic>> rooms,
  required DateTime checkIn,
  required DateTime checkOut,
  double discountPercent = 0,
}) {
  final gross = multiRoomGrossTotal(
    computeMultiRoomChargeLines(rooms: rooms, checkIn: checkIn, checkOut: checkOut),
  );
  final discount = discountPercent.clamp(0, 100);
  if (discount <= 0) return gross;
  return HourlyBilling.round50(gross * (1 - discount / 100));
}

class _DashedLinePainter extends CustomPainter {
  _DashedLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    const dash = 5.0;
    const gap = 4.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset((x + dash).clamp(0, size.width), 0), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) =>
      oldDelegate.color != color;
}
