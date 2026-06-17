import 'package:flutter/material.dart';

import '../admin/widgets/hourly_billing.dart';

/// Hourly stay extension: same duration as original booking, or custom hours.
Future<Map<String, dynamic>?> showExtendStayDialog(
  BuildContext context, {
  required Map<String, dynamic>? extensionOptions,
  Map<String, dynamic>? roomInfo,
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

  final sameDuration = opts?['same_duration'] as Map<String, dynamic>?;
  final customHours = opts?['custom_hours'] as Map<String, dynamic>?;
  final stayHours = (opts?['booked_stay_hours'] as num?)?.toInt() ??
      (sameDuration?['hours'] as num?)?.toInt() ??
      (opts?['stay_hours'] as num?)?.toInt() ??
      (roomInfo?['bookedStayHours'] as num?)?.toInt() ??
      (roomInfo?['stayHours'] as num?)?.toInt();
  final pricePerExtraHour = (customHours?['price_per_hour'] as num?)?.toDouble() ??
      (opts?['price_per_extra_hour'] as num?)?.toDouble() ??
      (roomInfo?['pricePerExtraHour'] as num?)?.toDouble() ??
      0;

  final sameHours = (sameDuration?['hours'] as num?)?.toInt() ?? stayHours ?? 0;
  final sameFee = (sameDuration?['fee'] as num?)?.toDouble() ??
      (stayHours != null && stayHours > 0
          ? HourlyBilling.sameDurationExtensionFee(
              _roomFromOptions(opts, roomInfo),
              stayHours,
            )
          : 0);

  final canSameDuration = sameHours > 0 && sameFee > 0;
  final canCustomHours = pricePerExtraHour > 0;

  if (!canSameDuration && !canCustomHours) {
    return _showBlockExtendDialog(context, opts, roomInfo);
  }

  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => _HourlyExtendDialog(
      sameHours: sameHours,
      sameFee: sameFee,
      pricePerExtraHour: pricePerExtraHour,
      canSameDuration: canSameDuration,
      canCustomHours: canCustomHours,
      minCustomHours: (customHours?['min_hours'] as num?)?.toInt() ?? 1,
      maxCustomHours: (customHours?['max_hours'] as num?)?.toInt() ?? 720,
    ),
  );
}

Map<String, dynamic> _roomFromOptions(
  Map<String, dynamic>? opts,
  Map<String, dynamic>? roomInfo,
) {
  return {
    'billing_mode': 'hourly',
    'block_hours': opts?['block_hours'] ?? roomInfo?['blockHours'] ?? 1,
    'price_per_block':
        opts?['price_per_block'] ?? roomInfo?['pricePerBlock'] ?? 0,
    'price_per_extra_hour':
        opts?['price_per_extra_hour'] ?? roomInfo?['pricePerExtraHour'] ?? 0,
  };
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

Future<Map<String, dynamic>?> _showBlockExtendDialog(
  BuildContext context,
  Map<String, dynamic>? opts,
  Map<String, dynamic>? roomInfo,
) {
  final blockHours = (opts?['block_hours'] as num?)?.toInt() ??
      (roomInfo?['blockHours'] as num?)?.toInt() ??
      3;
  final pricePerBlock = (opts?['price_per_block'] as num?)?.toDouble() ??
      (roomInfo?['pricePerBlock'] as num?)?.toDouble() ??
      0;
  final hourOptions = (opts?['block_options'] as List<dynamic>? ??
          roomInfo?['extendHourOptions'] as List<dynamic>? ??
          [])
      .map((e) => (e as num).toInt())
      .where((h) => h > 0)
      .toList();

  if (hourOptions.isEmpty) {
    return Future.value(null);
  }

  var selectedHours = hourOptions.first;
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) => AlertDialog(
        title: const Text('Extend Stay'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Extend by multiples of $blockHours hour(s)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              key: ValueKey<int>(selectedHours),
              initialValue: selectedHours,
              items: hourOptions
                  .map(
                    (h) => DropdownMenuItem(
                      value: h,
                      child: Text(
                        '$h hours — ₱${((h / blockHours) * pricePerBlock).toStringAsFixed(0)}',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) =>
                  setLocal(() => selectedHours = v ?? selectedHours),
              decoration: const InputDecoration(
                labelText: 'Additional hours',
                border: OutlineInputBorder(),
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
            onPressed: () => Navigator.of(context).pop({
              'extension_mode': 'block',
              'hours': selectedHours,
            }),
            child: const Text('Submit'),
          ),
        ],
      ),
    ),
  );
}

class _HourlyExtendDialog extends StatefulWidget {
  const _HourlyExtendDialog({
    required this.sameHours,
    required this.sameFee,
    required this.pricePerExtraHour,
    required this.canSameDuration,
    required this.canCustomHours,
    required this.minCustomHours,
    required this.maxCustomHours,
  });

  final int sameHours;
  final double sameFee;
  final double pricePerExtraHour;
  final bool canSameDuration;
  final bool canCustomHours;
  final int minCustomHours;
  final int maxCustomHours;

  @override
  State<_HourlyExtendDialog> createState() => _HourlyExtendDialogState();
}

class _HourlyExtendDialogState extends State<_HourlyExtendDialog> {
  static const _modeSame = 'same_duration';
  static const _modeCustom = 'custom_hours';

  late String _mode;
  late int _customHours;
  late final TextEditingController _hoursCtrl;

  @override
  void initState() {
    super.initState();
    _mode = widget.canSameDuration ? _modeSame : _modeCustom;
    _customHours = widget.minCustomHours;
    _hoursCtrl = TextEditingController(text: '$_customHours');
  }

  @override
  void dispose() {
    _hoursCtrl.dispose();
    super.dispose();
  }

  double get _previewFee {
    if (_mode == _modeSame) return widget.sameFee;
    return HourlyBilling.customHoursExtensionFee(
      widget.pricePerExtraHour,
      _customHours,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Extend Stay'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.canSameDuration)
              RadioListTile<String>(
                value: _modeSame,
                groupValue: _mode,
                onChanged: (v) => setState(() => _mode = v!),
                title: Text('Same duration (${widget.sameHours} hours)'),
                subtitle: Text(
                  'Block rate — ₱${widget.sameFee.toStringAsFixed(0)}',
                ),
                contentPadding: EdgeInsets.zero,
              ),
            if (widget.canCustomHours) ...[
              RadioListTile<String>(
                value: _modeCustom,
                groupValue: _mode,
                onChanged: (v) => setState(() => _mode = v!),
                title: const Text('Custom hours'),
                subtitle: Text(
                  '₱${widget.pricePerExtraHour.toStringAsFixed(0)} per hour',
                ),
                contentPadding: EdgeInsets.zero,
              ),
              if (_mode == _modeCustom) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _hoursCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText:
                        'Hours (${widget.minCustomHours}–${widget.maxCustomHours})',
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    final parsed = int.tryParse(v.trim());
                    if (parsed != null) {
                      setState(() {
                        _customHours = parsed
                            .clamp(widget.minCustomHours, widget.maxCustomHours);
                      });
                    }
                  },
                ),
              ],
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
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_mode == _modeCustom) {
              final parsed = int.tryParse(_hoursCtrl.text.trim());
              if (parsed == null ||
                  parsed < widget.minCustomHours ||
                  parsed > widget.maxCustomHours) {
                return;
              }
              _customHours = parsed;
            }
            Navigator.of(context).pop({
              'extension_mode': _mode,
              if (_mode == _modeCustom) 'hours': _customHours,
            });
          },
          child: const Text('Submit'),
        ),
      ],
    );
  }
}
