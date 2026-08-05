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
  String confirmLabel = 'Make payment',
  /// View-only mode for looking up an existing booking; hides the confirm action.
  bool readOnly = false,
  String? footnote,
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
    barrierDismissible: readOnly,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      var expanded = true;
      final note = footnote ??
          (readOnly
              ? null
              : (checkInNow
                  ? 'Review the stay details, then confirm check-in.'
                  : 'Review the stay details, then confirm this booking.'));
      return StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          titlePadding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
          contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          title: Text(
            title,
            style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SummaryPanel(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
                    borderColor: scheme.outlineVariant.withValues(alpha: 0.45),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (roomLabel != null && roomLabel.trim().isNotEmpty)
                          Text(
                            roomLabel,
                            style: Theme.of(ctx).textTheme.labelLarge?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        if (guestName.trim().isNotEmpty) ...[
                          if (roomLabel != null && roomLabel.trim().isNotEmpty)
                            const SizedBox(height: 4),
                          Text(
                            guestName,
                            style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ],
                        if (accountLabel != null &&
                            accountLabel.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            accountLabel,
                            style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SummaryPanel(
                    color: scheme.primaryContainer.withValues(alpha: 0.55),
                    borderColor: scheme.primary.withValues(alpha: 0.28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Total bill amount',
                          style: Theme.of(ctx).textTheme.labelMedium?.copyWith(
                                color: scheme.onPrimaryContainer
                                    .withValues(alpha: 0.75),
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: scheme.primary.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.receipt_long_outlined,
                                size: 22,
                                color: scheme.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                formatPeso(totalAmount),
                                style: Theme.of(ctx)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      color: scheme.primary,
                                      letterSpacing: -0.4,
                                    ),
                              ),
                            ),
                            Material(
                              color: scheme.surface.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(10),
                              child: InkWell(
                                onTap: () =>
                                    setLocal(() => expanded = !expanded),
                                borderRadius: BorderRadius.circular(10),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
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
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                      const SizedBox(width: 2),
                                      Icon(
                                        expanded
                                            ? Icons.keyboard_arrow_up_rounded
                                            : Icons.keyboard_arrow_down_rounded,
                                        size: 20,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (expanded) ...[
                    const SizedBox(height: 12),
                    _SummaryPanel(
                      color: scheme.surface,
                      borderColor: scheme.outlineVariant.withValues(alpha: 0.55),
                      child: Row(
                        children: [
                          Expanded(
                            child: _DateBlock(
                              label: 'Check-in',
                              value: formatBookingSummaryDate(checkIn),
                              alignEnd: false,
                            ),
                          ),
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.secondaryContainer
                                  .withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: scheme.secondary.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.schedule_rounded,
                                  size: 16,
                                  color: scheme.onSecondaryContainer,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  durationBadge,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: scheme.onSecondaryContainer,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: _DateBlock(
                              label: 'Check-out',
                              value: formatBookingSummaryDate(checkOut),
                              alignEnd: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SummaryPanel(
                      color: scheme.surfaceContainerLow,
                      borderColor: scheme.outlineVariant.withValues(alpha: 0.5),
                      child: Column(
                        children: [
                          for (var i = 0; i < lines.length; i++) ...[
                            if (i > 0)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                child: Divider(
                                  height: 1,
                                  color: scheme.outlineVariant
                                      .withValues(alpha: 0.45),
                                ),
                              ),
                            _LineRow(line: lines[i]),
                          ],
                        ],
                      ),
                    ),
                    if ((paymentMethod != null &&
                            paymentMethod.trim().isNotEmpty) ||
                        tendered > 0.009) ...[
                      const SizedBox(height: 12),
                      _SummaryPanel(
                        color: change > 0.009
                            ? scheme.primaryContainer.withValues(alpha: 0.45)
                            : (remaining > 0.009 && tendered > 0.009
                                ? scheme.tertiaryContainer
                                    .withValues(alpha: 0.4)
                                : scheme.surfaceContainerHighest
                                    .withValues(alpha: 0.55)),
                        borderColor: change > 0.009
                            ? scheme.primary.withValues(alpha: 0.3)
                            : (remaining > 0.009 && tendered > 0.009
                                ? scheme.tertiary.withValues(alpha: 0.3)
                                : scheme.outlineVariant.withValues(alpha: 0.5)),
                        child: Column(
                          children: [
                            if (paymentMethod != null &&
                                paymentMethod.trim().isNotEmpty)
                              _MetaRow(
                                label: 'Payment method',
                                value: paymentMethod,
                              ),
                            if (tendered > 0.009) ...[
                              if (paymentMethod != null &&
                                  paymentMethod.trim().isNotEmpty)
                                const SizedBox(height: 12),
                              _MetaRow(
                                label: 'Amount received',
                                value: formatPeso(tendered),
                                emphasize: true,
                              ),
                              const SizedBox(height: 12),
                              if (change > 0.009)
                                _MetaRow(
                                  label: 'Change given',
                                  value: formatPeso(change),
                                  emphasize: true,
                                  color: scheme.primary,
                                )
                              else if (remaining > 0.009)
                                _MetaRow(
                                  label: 'Remaining after deposit',
                                  value: formatPeso(remaining),
                                  emphasize: true,
                                  color: scheme.tertiary,
                                )
                              else
                                Row(
                                  children: [
                                    Icon(
                                      Icons.check_circle_rounded,
                                      size: 18,
                                      color: scheme.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Paid in full',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: scheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                  if (note != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      note,
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actionsAlignment: readOnly
              ? MainAxisAlignment.end
              : MainAxisAlignment.spaceBetween,
          actions: readOnly
              ? [
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Close'),
                  ),
                ]
              : [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Back'),
                  ),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(ctx, true),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    label: Text(confirmLabel),
                  ),
                ],
        ),
      );
    },
  );

  return confirmed == true;
}

class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({
    required this.child,
    required this.color,
    required this.borderColor,
  });

  final Widget child;
  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: child,
    );
  }
}

class _DateBlock extends StatelessWidget {
  const _DateBlock({
    required this.label,
    required this.value,
    required this.alignEnd,
  });

  final String label;
  final String value;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
      ],
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line});

  final BookingSummaryLine line;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDiscount = line.amount < 0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                line.label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: isDiscount ? scheme.primary : null,
                ),
              ),
              if (line.subtitle != null && line.subtitle!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  line.subtitle!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          formatPeso(line.amount),
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: isDiscount ? scheme.primary : null,
          ),
        ),
      ],
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.label,
    required this.value,
    this.emphasize = false,
    this.color,
  });

  final String label;
  final String value;
  final bool emphasize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: TextStyle(
            fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
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
