import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../dio_client.dart';
import '../../../utils/money_format.dart';

/// Company policy percentage that must be collected before a walk-in check-in.
Future<double> fetchMinCheckInPaymentPercent() async {
  try {
    final res = await portalDio()
        .get<Map<String, dynamic>>('/admin/settings/min-check-in-payment');
    return parseJsonDouble(res.data?['min_check_in_payment_percent'] ?? 50);
  } catch (_) {
    return 50;
  }
}

double minCheckInDeposit(double balanceDue, double minPercent) {
  if (balanceDue <= 0 || minPercent <= 0) return 0;
  return (balanceDue * (minPercent / 100)).clamp(0, double.infinity).toDouble();
}

String minCheckInPercentLabel(double minPercent) =>
    minPercent % 1 == 0
        ? minPercent.toStringAsFixed(0)
        : minPercent.toStringAsFixed(1);

/// Deposit input shown inside the walk-in booking form, below the guest details.
/// Only required when the front desk checks the guest in right away.
class CheckInDepositField extends StatelessWidget {
  const CheckInDepositField({
    super.key,
    required this.controller,
    required this.balanceDue,
    required this.minPercent,
    required this.onChanged,
  });

  final TextEditingController controller;
  final double balanceDue;
  final double minPercent;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final minDue = minCheckInDeposit(balanceDue, minPercent);
    final pctLabel = minCheckInPercentLabel(minPercent);
    final tendered = double.tryParse(controller.text.trim()) ?? 0;
    final change = tendered > 0 && balanceDue > 0
        ? (tendered - balanceDue).clamp(0, double.infinity)
        : 0.0;
    final applied =
        tendered > 0 ? (tendered > balanceDue ? balanceDue : tendered) : 0.0;
    final belowMin = tendered + 0.009 < minDue;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.payments_outlined, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Check-in deposit',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            minDue > 0
                ? 'At least $pctLabel% (${formatPeso(minDue)}) must be paid '
                    'before check-in. Needed only when checking the guest in now.'
                : 'Needed only when checking the guest in now.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.35,
                ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: InputDecoration(
              labelText: 'Amount received (₱)',
              border: const OutlineInputBorder(),
              filled: true,
              fillColor: scheme.surface,
              prefixText: '₱ ',
              helperText: balanceDue > 0
                  ? 'Applied to bill: ${formatPeso(applied)}'
                  : null,
            ),
            onChanged: (_) => onChanged(),
          ),
          if (minDue > 0) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  controller.text = minDue.toStringAsFixed(2);
                  onChanged();
                },
                icon: const Icon(Icons.bolt_outlined, size: 18),
                label: Text('Use minimum ${formatPeso(minDue)}'),
              ),
            ),
          ],
          if (tendered > 0 && balanceDue > 0) ...[
            const SizedBox(height: 4),
            Text(
              belowMin
                  ? 'Need at least ${formatPeso(minDue)} to check in.'
                  : (change > 0
                      ? 'Change given: ${formatPeso(change)}'
                      : (tendered + 0.009 >= balanceDue
                          ? 'Paid in full — no change.'
                          : 'Remaining after this payment: '
                              '${formatPeso(balanceDue - tendered)}')),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: belowMin ? scheme.error : scheme.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
