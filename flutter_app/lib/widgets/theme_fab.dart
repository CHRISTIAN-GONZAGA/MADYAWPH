import 'package:flutter/material.dart';

import '../auth_storage.dart';
import '../locale_controller.dart';
import '../theme_controller.dart';
import '../ui/app_theme.dart';

/// Draggable appearance control — applies accent + mode across the whole app.
class ThemeFab extends StatefulWidget {
  const ThemeFab({super.key});

  @override
  State<ThemeFab> createState() => _ThemeFabState();
}

class _ThemeFabState extends State<ThemeFab> {
  double _dxFromRight = 16;
  double _dyFromBottom = 24;

  static const _fabSize = 56.0;

  static const _accentPresets = <Color>[
    Color(0xFF1565C0),
    Color(0xFF007AFF),
    Color(0xFF5856D6),
    Color(0xFF34C759),
    Color(0xFFFF9500),
    Color(0xFFFF2D55),
    Color(0xFF1C1C1E),
  ];

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

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (context, setLocal) {
          final previewColor = HSVColor.fromAHSV(1, hue, sat, val).toColor();
          final previewTheme = AppTheme.light(previewColor);
          final previewDark = AppTheme.dark(previewColor);

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Theme(
              data: mode == ThemeMode.dark ? previewDark : previewTheme,
              child: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        context.tr('appearance'),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.tr('appearance_sub'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        context.tr('theme_mode'),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<ThemeMode>(
                        segments: [
                          ButtonSegment(
                            value: ThemeMode.light,
                            label: Text(context.tr('light')),
                            icon: const Icon(Icons.light_mode_outlined, size: 18),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            label: Text(context.tr('dark')),
                            icon: const Icon(Icons.dark_mode_outlined, size: 18),
                          ),
                          ButtonSegment(
                            value: ThemeMode.system,
                            label: Text(context.tr('auto')),
                            icon: const Icon(Icons.phone_iphone_outlined, size: 18),
                          ),
                        ],
                        selected: {mode},
                        onSelectionChanged: (s) => setLocal(() => mode = s.first),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        context.tr('accent_presets'),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _accentPresets.map((c) {
                          final selected =
                              HSVColor.fromColor(c).hue.round() == hue.round();
                          return InkWell(
                            onTap: () {
                              final hsv = HSVColor.fromColor(c);
                              setLocal(() {
                                hue = hsv.hue;
                                sat = hsv.saturation;
                                val = hsv.value;
                              });
                            },
                            borderRadius: BorderRadius.circular(999),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: selected
                                      ? Theme.of(context).colorScheme.onSurface
                                      : Colors.transparent,
                                  width: 2.5,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text(context.tr('accent_color')),
                        children: [
                          _SliderRow(
                            label: context.tr('hue'),
                            value: hue,
                            max: 360,
                            onChanged: (v) => setLocal(() => hue = v),
                          ),
                          _SliderRow(
                            label: context.tr('saturation'),
                            value: sat,
                            max: 1,
                            onChanged: (v) => setLocal(() => sat = v),
                          ),
                          _SliderRow(
                            label: context.tr('brightness'),
                            value: val,
                            max: 1,
                            onChanged: (v) => setLocal(() => val = v),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: previewColor.withValues(alpha: 0.12),
                          border: Border.all(
                            color: previewColor.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: previewColor,
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: () {},
                                child: Text(context.tr('primary_button')),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () async {
                          final color =
                              HSVColor.fromAHSV(1, hue, sat, val).toColor();
                          await setThemeMode(mode);
                          await setThemeSeedColor(color);
                          if (sheetCtx.mounted) {
                            Navigator.of(sheetCtx).pop();
                          }
                        },
                        child: Text(context.tr('apply')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
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
                  elevation: 6,
                  shadowColor: Colors.black26,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  color: c,
                  child: InkWell(
                    onTap: _openCustomization,
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      width: _fabSize,
                      height: _fabSize,
                      child: Icon(Icons.palette_outlined, color: onFab),
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
