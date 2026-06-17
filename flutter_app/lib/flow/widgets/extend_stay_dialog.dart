import 'package:flutter/material.dart';

import '../admin/widgets/hourly_billing.dart';

/// Hourly stay extension by per-hour rate (1–10 hours). Nightly: add nights.
Future<Map<String, dynamic>?> showExtendStayDialog(
  BuildContext context, {
  Map<String, dynamic>? extensionOptions,
  Map<String, dynamic>? roomInfo,
  int maxPickerHours = 10,
}) {
  final opts = extensionOptions ?? roomInfo?['extensionOptions'] as Map<String, dynamic>?;
  final billingMode = (opts?['billing_mode'] ??
          roomInfo?['billingMode'] ??
          'nightly')
      .toString()
      .toLowerCase();

  if (billingMode != 'hourly') {
    return _showNightlyExtendDialog(context);
  }

  final perHour = opts?['per_hour'] as Map<String, dynamic>? ??
      opts?['custom_hours'] as Map<String, dynamic>?;
  final pricePerExtraHour = (perHour?['price_per_hour'] as num?)?.toDouble() ??
      (opts?['price_per_extra_hour'] as num?)?.toDouble() ??
      (roomInfo?['pricePerExtraHour'] as num?)?.toDouble() ??
      0;

  if (pricePerExtraHour <= 0) {
    return Future.value(null);
  }

  final pickerMax = maxPickerHours.clamp(1, 10);
  final minHours = (perHour?['min_hours'] as num?)?.toInt() ?? 1;

  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => _PerHourExtendDialog(
      pricePerExtraHour: pricePerExtraHour,
      minHours: minHours,
      maxHours: pickerMax,
    ),
  );
}

Future<Map<String, dynamic>?> _showNightlyExtendDialog(BuildContext context) {
  final ctrl = TextEditingController(text: '1');
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Extend Stay'),
      content: TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'Additional nights',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final nights = int.tryParse(ctrl.text.trim()) ?? 1;
            if (nights < 1) return;
            Navigator.of(context).pop({'nights': nights});
          },
          child: const Text('Submit'),
        ),
      ],
    ),
  ).whenComplete(ctrl.dispose);
}

class _PerHourExtendDialog extends StatefulWidget {
  const _PerHourExtendDialog({
    required this.pricePerExtraHour,
    required this.minHours,
    required this.maxHours,
  });

  final double pricePerExtraHour;
  final int minHours;
  final int maxHours;

  @override
  State<_PerHourExtendDialog> createState() => _PerHourExtendDialogState();
}

class _PerHourExtendDialogState extends State<_PerHourExtendDialog> {
  late int _hours;

  @override
  void initState() {
    super.initState();
    _hours = widget.minHours;
  }

  double get _previewFee =>
      HourlyBilling.customHoursExtensionFee(widget.pricePerExtraHour, _hours);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Extend Stay'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '₱${widget.pricePerExtraHour.toStringAsFixed(0)} per hour (category rate)',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            key: ValueKey<int>(_hours),
            initialValue: _hours,
            decoration: const InputDecoration(
              labelText: 'Additional hours',
              border: OutlineInputBorder(),
            ),
            items: List.generate(
              widget.maxHours - widget.minHours + 1,
              (i) {
                final h = widget.minHours + i;
                final fee = HourlyBilling.customHoursExtensionFee(
                  widget.pricePerExtraHour,
                  h,
                );
                return DropdownMenuItem(
                  value: h,
                  child: Text(
                    '$h hour${h == 1 ? '' : 's'} — ₱${fee.toStringAsFixed(0)}',
                  ),
                );
              },
            ),
            onChanged: (v) {
              if (v != null) setState(() => _hours = v);
            },
          ),
          const SizedBox(height: 12),
          Text(
            'Extension fee: ₱${_previewFee.toStringAsFixed(0)}',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop({'hours': _hours}),
          child: const Text('Submit'),
        ),
      ],
    );
  }
}
