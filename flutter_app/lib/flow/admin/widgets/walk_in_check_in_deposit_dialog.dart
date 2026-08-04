import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';

import '../../../dio_client.dart';
import '../../../utils/money_format.dart';

/// Deposit confirmation before walk-in "Check in now" / book-and-check-in.
/// Returns the amount the front desk entered, or null if cancelled.
/// When the guest tenders more than [balanceDue], live change is shown in-dialog
/// and recorded on the bill after check-in (`cash_change`).
Future<double?> showWalkInCheckInDepositDialog(
  BuildContext context, {
  required double balanceDue,
  String roomLabel = '',
}) async {
  double minPercent = 50;
  try {
    final res = await portalDio()
        .get<Map<String, dynamic>>('/admin/settings/min-check-in-payment');
    minPercent = parseJsonDouble(
      res.data?['min_check_in_payment_percent'] ?? 50,
    );
  } catch (_) {}

  final minDue =
      (balanceDue * (minPercent / 100)).clamp(0, double.infinity).toDouble();
  final paymentCtrl = TextEditingController(
    text: minDue > 0 ? minDue.toStringAsFixed(2) : '',
  );
  final pctLabel = minPercent % 1 == 0
      ? minPercent.toStringAsFixed(0)
      : minPercent.toStringAsFixed(1);

  if (!context.mounted) {
    paymentCtrl.dispose();
    return null;
  }

  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final tendered = double.tryParse(paymentCtrl.text.trim()) ?? 0;
        final change = tendered > 0 && balanceDue > 0
            ? (tendered - balanceDue).clamp(0, double.infinity)
            : 0.0;
        final applied = tendered > 0
            ? (tendered > balanceDue ? balanceDue : tendered)
            : 0.0;

        return AlertDialog(
          title: Text(
            roomLabel.isEmpty
                ? 'Check-in deposit'
                : 'Check-in deposit — $roomLabel',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Estimated stay total: ₱${balanceDue.toStringAsFixed(2)}\n'
                  'Company policy: at least $pctLabel%'
                  '${minDue > 0 ? ' (₱${minDue.toStringAsFixed(2)})' : ''} '
                  'must be paid before check-in.',
                  style: Theme.of(ctx).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'You may enter more than the stay total; change is shown here '
                  'and recorded on the room bill.',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: paymentCtrl,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Amount given by guest (₱)',
                    border: const OutlineInputBorder(),
                    prefixText: '₱ ',
                    helperText: balanceDue > 0
                        ? 'Applied to bill: ₱${applied.toStringAsFixed(2)}'
                        : null,
                  ),
                  onChanged: (_) => setLocal(() {}),
                ),
                if (tendered > 0 && balanceDue > 0) ...[
                  const SizedBox(height: 10),
                  Text(
                    tendered + 0.009 < minDue
                        ? 'Need at least ₱${minDue.toStringAsFixed(2)} to check in.'
                        : (change > 0
                            ? 'Change given: ${formatPeso(change)}'
                            : (tendered + 0.009 >= balanceDue
                                ? 'Paid in full — no change.'
                                : 'Remaining after this payment: ${formatPeso(balanceDue - tendered)}')),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: tendered + 0.009 < minDue
                          ? Theme.of(ctx).colorScheme.error
                          : Theme.of(ctx).colorScheme.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final paid = double.tryParse(paymentCtrl.text.trim()) ?? 0;
                if (minPercent > 0 &&
                    balanceDue > 0 &&
                    paid + 0.009 < minDue) {
                  showAppMessage(
                    ctx,
                    'Enter at least ₱${minDue.toStringAsFixed(2)} '
                    '($pctLabel% of the stay total).',
                    isError: true,
                  );
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: Text(
                change > 0
                    ? 'Confirm, give change & check in'
                    : 'Confirm & check in',
              ),
            ),
          ],
        );
      },
    ),
  );

  final amount = double.tryParse(paymentCtrl.text.trim()) ?? 0;
  paymentCtrl.dispose();
  if (ok != true) return null;
  return amount;
}
