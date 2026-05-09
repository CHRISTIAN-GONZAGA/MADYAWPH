import 'package:flutter/material.dart';

import '../auth_storage.dart';
import '../theme_controller.dart';

/// Draggable palette control; persists corner offset from bottom-right.
class ThemeFab extends StatefulWidget {
  const ThemeFab({super.key});

  @override
  State<ThemeFab> createState() => _ThemeFabState();
}

class _ThemeFabState extends State<ThemeFab> {
  double _dxFromRight = 16;
  double _dyFromBottom = 24;

  static const _fabSize = 56.0;

  @override
  void initState() {
    super.initState();
    AuthStorage.themeFabOffset().then((v) {
      if (!mounted || v == null) return;
      setState(() {
        _dxFromRight = v.$1;
        _dyFromBottom = v.$2;
      });
    });
  }

  Future<void> _persistOffset() =>
      AuthStorage.setThemeFabOffset(_dxFromRight, _dyFromBottom);

  Future<void> _openCustomization() async {
    double hue = HSVColor.fromColor(themeSeedColorNotifier.value).hue;
    double sat = HSVColor.fromColor(themeSeedColorNotifier.value).saturation;
    double val = HSVColor.fromColor(themeSeedColorNotifier.value).value;
    ThemeMode mode = themeModeNotifier.value;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          final color = HSVColor.fromAHSV(1, hue, sat, val).toColor();
          return AlertDialog(
            title: const Text('Appearance'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Theme mode',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text('Light'),
                        icon: Icon(Icons.light_mode_outlined),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text('Dark'),
                        icon: Icon(Icons.dark_mode_outlined),
                      ),
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text('Auto'),
                        icon: Icon(Icons.phone_android_outlined),
                      ),
                    ],
                    selected: {mode},
                    onSelectionChanged: (s) =>
                        setLocal(() => mode = s.first),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Accent color',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 12),
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
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  await setThemeMode(mode);
                  await setThemeSeedColor(color);
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final safe = mq.padding;
    final maxW = mq.size.width - safe.horizontal - _fabSize - 8;
    final maxH = mq.size.height - safe.vertical - _fabSize - 8;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          right: _dxFromRight.clamp(8, maxW > 8 ? maxW : 8),
          bottom: _dyFromBottom.clamp(8, maxH > 8 ? maxH : 8),
          child: GestureDetector(
            onPanUpdate: (d) {
              setState(() {
                _dxFromRight -= d.delta.dx;
                _dyFromBottom -= d.delta.dy;
              });
            },
            onPanEnd: (_) => _persistOffset(),
            child: ValueListenableBuilder<Color>(
              valueListenable: themeSeedColorNotifier,
              builder: (context, c, _) {
                final onFab =
                    ThemeData.estimateBrightnessForColor(c) == Brightness.dark
                        ? Colors.white
                        : Colors.black87;
                return Material(
                  elevation: 4,
                  shadowColor: Colors.black26,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  color: c,
                  child: InkWell(
                    onTap: _openCustomization,
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      width: _fabSize,
                      height: _fabSize,
                      child: Icon(Icons.tune, color: onFab),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
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
            value: value.clamp(0, max),
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
