import 'package:flutter/material.dart';

import '../locale_controller.dart';

/// App bar action to switch UI language.
class LanguagePickerButton extends StatelessWidget {
  const LanguagePickerButton({super.key, this.iconOnly = false});

  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    if (iconOnly) {
      return IconButton(
        tooltip: context.tr('change_language'),
        icon: const Icon(Icons.translate_outlined),
        onPressed: () => LanguagePickerButton.showPicker(context),
      );
    }
    return TextButton.icon(
      onPressed: () => LanguagePickerButton.showPicker(context),
      icon: const Icon(Icons.translate_outlined, size: 20),
      label: Text(context.tr('language')),
    );
  }

  static Future<void> showPicker(BuildContext context) async {
    final current = appLocaleNotifier.value;
    final chosen = await showDialog<Locale>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('change_language')),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: AppLocales.supported.map((locale) {
              final selected = locale.languageCode == current.languageCode;
              return ListTile(
                leading: Icon(
                  selected ? Icons.check_circle : Icons.circle_outlined,
                  color: selected
                      ? Theme.of(ctx).colorScheme.primary
                      : null,
                ),
                title: Text(AppLocales.label(locale)),
                subtitle: Text(locale.languageCode),
                onTap: () => Navigator.pop(ctx, locale),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('cancel')),
          ),
        ],
      ),
    );
    if (chosen != null) {
      await AppLocales.setLocale(chosen);
    }
  }
}
