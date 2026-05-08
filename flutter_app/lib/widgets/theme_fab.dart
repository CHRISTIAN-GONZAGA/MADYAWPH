import 'package:flutter/material.dart';

import '../theme_controller.dart';

class ThemeFab extends StatefulWidget {
  const ThemeFab({super.key});

  @override
  State<ThemeFab> createState() => _ThemeFabState();
}

class _ThemeFabState extends State<ThemeFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    upperBound: 0.02,
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _openPicker() async {
    Color temp = themeSeedColorNotifier.value;
    double hue = HSVColor.fromColor(temp).hue;
    double sat = HSVColor.fromColor(temp).saturation;
    double val = HSVColor.fromColor(temp).value;

    final picked = await showDialog<Color>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          final color = HSVColor.fromAHSV(1, hue, sat, val).toColor();
          return AlertDialog(
            title: const Text('Theme color'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    border: Border.all(
                      color: Theme.of(context).dividerColor,
                      width: 0.8,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _SliderRow(
                  label: 'Hue',
                  value: hue,
                  max: 360,
                  onChanged: (v) => setLocal(() => hue = v),
                ),
                _SliderRow(
                  label: 'Saturation',
                  value: sat,
                  max: 1,
                  onChanged: (v) => setLocal(() => sat = v),
                ),
                _SliderRow(
                  label: 'Brightness',
                  value: val,
                  max: 1,
                  onChanged: (v) => setLocal(() => val = v),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.of(context).pop(color),
                  child: const Text('Apply')),
            ],
          );
        },
      ),
    );

    if (picked != null) {
      await setThemeSeedColor(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: themeSeedColorNotifier,
      builder: (context, c, _) {
        return FloatingActionButton(
          onPressed: _openPicker,
          backgroundColor: c,
          foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: GestureDetector(
            onTapDown: (_) => _c.forward(),
            onTapUp: (_) => _c.reverse(),
            onTapCancel: () => _c.reverse(),
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => Transform.scale(
                scale: 1 - _c.value,
                child: const Icon(Icons.palette_outlined),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 90, child: Text(label)),
        Expanded(
          child: Slider(
            value: value,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
