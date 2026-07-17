import 'package:flutter/material.dart';

import '../admin/widgets/hourly_billing.dart';

/// Hourly stay extension: one block (category stay rate) or per-hour extras.
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

  final block = opts?['block'] as Map<String, dynamic>?;
  final perHour = opts?['per_hour'] as Map<String, dynamic>? ??
      opts?['custom_hours'] as Map<String, dynamic>?;
  final pricePerExtraHour = (perHour?['price_per_hour'] as num?)?.toDouble() ??
      (opts?['price_per_extra_hour'] as num?)?.toDouble() ??
      (roomInfo?['pricePerExtraHour'] as num?)?.toDouble() ??
      0;
  final blockHours = (block?['block_hours'] as num?)?.toInt() ??
      HourlyBilling.blockHours(roomInfo ?? const {});
  final blockFee = (block?['fee'] as num?)?.toDouble() ??
      (block?['price_per_block'] as num?)?.toDouble() ??
      0;

  final hasBlock = blockHours > 0 && blockFee > 0;
  final hasHours = pricePerExtraHour > 0;
  if (!hasBlock && !hasHours) {
    return Future.value(null);
  }

  final pickerMax = maxPickerHours.clamp(1, 10);
  final minHours = (perHour?['min_hours'] as num?)?.toInt() ?? 1;

  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => _HourlyExtendDialog(
      blockHours: blockHours,
      blockFee: blockFee,
      hasBlock: hasBlock,
      pricePerExtraHour: pricePerExtraHour,
      hasHours: hasHours,
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

class _HourlyExtendDialog extends StatefulWidget {
  const _HourlyExtendDialog({
    required this.blockHours,
    required this.blockFee,
    required this.hasBlock,
    required this.pricePerExtraHour,
    required this.hasHours,
    required this.minHours,
    required this.maxHours,
  });

  final int blockHours;
  final double blockFee;
  final bool hasBlock;
  final double pricePerExtraHour;
  final bool hasHours;
  final int minHours;
  final int maxHours;

  @override
  State<_HourlyExtendDialog> createState() => _HourlyExtendDialogState();
}

class _HourlyExtendDialogState extends State<_HourlyExtendDialog> {
  late String _mode; // block | hours
  late int _hours;

  @override
  void initState() {
    super.initState();
    _mode = widget.hasBlock ? 'block' : 'hours';
    _hours = widget.minHours;
  }

  double get _previewFee {
    if (_mode == 'block') return widget.blockFee;
    return HourlyBilling.customHoursExtensionFee(
      widget.pricePerExtraHour,
      _hours,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Extend Stay'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.hasBlock)
            RadioListTile<String>(
              value: 'block',
              groupValue: _mode,
              title: Text(
                'One more stay (${widget.blockHours} hr) — ₱${widget.blockFee.toStringAsFixed(0)}',
              ),
              onChanged: (v) {
                if (v != null) setState(() => _mode = v);
              },
            ),
          if (widget.hasHours)
            RadioListTile<String>(
              value: 'hours',
              groupValue: _mode,
              title: Text(
                'Extra hours — ₱${widget.pricePerExtraHour.toStringAsFixed(0)}/hr',
              ),
              onChanged: (v) {
                if (v != null) setState(() => _mode = v);
              },
            ),
          if (_mode == 'hours' && widget.hasHours) ...[
            const SizedBox(height: 8),
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
          ],
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
          onPressed: () {
            if (_mode == 'block') {
              Navigator.of(context).pop({
                'extension_mode': 'block',
              });
              return;
            }
            Navigator.of(context).pop({
              'extension_mode': 'custom_hours',
              'hours': _hours,
            });
          },
          child: const Text('Submit'),
        ),
      ],
    );
  }
}
