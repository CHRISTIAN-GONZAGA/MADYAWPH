import 'package:flutter/material.dart';

import 'hourly_billing.dart';

/// Scrollable block-hours picker + price field for hourly room rates.
class HourlyPricePicker extends StatelessWidget {
  const HourlyPricePicker({
    super.key,
    required this.blockHours,
    required this.pricePerBlock,
    required this.onBlockHoursChanged,
    required this.onPriceChanged,
    this.priceController,
  });

  final int blockHours;
  final double pricePerBlock;
  final ValueChanged<int> onBlockHoursChanged;
  final ValueChanged<double> onPriceChanged;
  final TextEditingController? priceController;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final options = HourlyBilling.blockHourOptions;
    final selectedIndex = options.indexOf(blockHours).clamp(0, options.length - 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Hourly rate',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          'Set price per block of hours (e.g. ₱1,000 per 3 hours).',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: priceController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Price (PHP)',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
                onChanged: (v) =>
                    onPriceChanged(double.tryParse(v.trim()) ?? 0),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'per',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(width: 8),
            Container(
              width: 88,
              height: 120,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant),
                color: scheme.surfaceContainerLow,
              ),
              child: ListWheelScrollView.useDelegate(
                controller: FixedExtentScrollController(initialItem: selectedIndex),
                itemExtent: 36,
                physics: const FixedExtentScrollPhysics(),
                onSelectedItemChanged: (i) =>
                    onBlockHoursChanged(options[i]),
                childDelegate: ListWheelChildBuilderDelegate(
                  childCount: options.length,
                  builder: (context, index) {
                    final h = options[index];
                    final selected = h == blockHours;
                    return Center(
                      child: Text(
                        '$h hr',
                        style: TextStyle(
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w500,
                          color: selected ? scheme.primary : scheme.onSurface,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Preview: ₱${pricePerBlock.toStringAsFixed(0)} per $blockHours hour${blockHours == 1 ? '' : 's'}',
          style: TextStyle(
            color: scheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Billing mode toggle + nightly or hourly pricing fields.
class RoomPricingFields extends StatefulWidget {
  const RoomPricingFields({
    super.key,
    required this.billingMode,
    required this.pricePerNight,
    required this.pricePerBlock,
    required this.blockHours,
    required this.onChanged,
    this.pricePerExtraHour = 0,
    this.showExtraHourRate = true,
    /// Category setup is hourly-only (legacy per-night maps to 12h).
    this.allowNightly = true,
    this.nightlyController,
    this.blockPriceController,
    this.extraHourPriceController,
  });

  final String billingMode;
  final double pricePerNight;
  final double pricePerBlock;
  final int blockHours;
  final double pricePerExtraHour;
  /// Category forms only — rooms inherit the category rate.
  final bool showExtraHourRate;
  final bool allowNightly;
  final void Function({
    required String billingMode,
    required double pricePerNight,
    required double pricePerBlock,
    required int blockHours,
    required double pricePerExtraHour,
  }) onChanged;
  final TextEditingController? nightlyController;
  final TextEditingController? blockPriceController;
  final TextEditingController? extraHourPriceController;

  @override
  State<RoomPricingFields> createState() => _RoomPricingFieldsState();
}

class _RoomPricingFieldsState extends State<RoomPricingFields> {
  late String _mode;
  late double _nightly;
  late double _blockPrice;
  late int _blockHours;
  late double _extraHourPrice;

  @override
  void initState() {
    super.initState();
    _mode = widget.allowNightly ? widget.billingMode : 'hourly';
    _nightly = widget.pricePerNight;
    _blockPrice = widget.pricePerBlock;
    _blockHours = widget.blockHours;
    _extraHourPrice = widget.pricePerExtraHour;
  }

  void _emit() {
    widget.onChanged(
      billingMode: _mode,
      pricePerNight: _nightly,
      pricePerBlock: _blockPrice,
      blockHours: _blockHours,
      pricePerExtraHour: _extraHourPrice,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.allowNightly) ...[
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'nightly', label: Text('Per night')),
              ButtonSegment(value: 'hourly', label: Text('Per hours')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) {
              setState(() => _mode = s.first);
              _emit();
            },
          ),
          const SizedBox(height: 14),
        ],
        if (_mode == 'hourly' || !widget.allowNightly) ...[
          HourlyPricePicker(
            blockHours: _blockHours,
            pricePerBlock: _blockPrice,
            priceController: widget.blockPriceController,
            onBlockHoursChanged: (h) {
              setState(() => _blockHours = h);
              _emit();
            },
            onPriceChanged: (p) {
              setState(() => _blockPrice = p);
              _emit();
            },
          ),
          if (widget.showExtraHourRate) ...[
            const SizedBox(height: 14),
            TextField(
              controller: widget.extraHourPriceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Price per extra hour (PHP)',
                helperText:
                    'Used when extending stay by hour (applies to all rooms in this category).',
                prefixIcon: Icon(Icons.schedule_outlined),
              ),
              onChanged: (v) {
                setState(() => _extraHourPrice = double.tryParse(v.trim()) ?? 0);
                _emit();
              },
            ),
          ],
        ] else
          TextField(
            controller: widget.nightlyController,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Price per night (PHP)',
              prefixIcon: Icon(Icons.payments_outlined),
            ),
            onChanged: (v) {
              setState(() => _nightly = double.tryParse(v.trim()) ?? 0);
              _emit();
            },
          ),
      ],
    );
  }
}
