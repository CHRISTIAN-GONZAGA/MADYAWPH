import 'package:flutter/material.dart';

import '../../../widgets/app_input.dart';

/// How the guest initiated the booking (admin / front desk walk-in flow).
class BookingModeOptions {
  BookingModeOptions._();

  static const defaultValue = 'walk-in';

  static const values = <String>[
    'messenger',
    'phonecall',
    'walk-in',
    'instagram',
    'x',
    'website',
    'email',
    'other',
  ];

  static String label(String value) => switch (value) {
        'messenger' => 'Messenger',
        'phonecall' => 'Phone call',
        'walk-in' => 'Walk-in',
        'instagram' => 'Instagram',
        'x' => 'X (Twitter)',
        'website' => 'Website',
        'email' => 'Email',
        'other' => 'Other',
        _ => value,
      };

  /// Value sent to the API (`booking_mode` or custom text when Other).
  static String apiValue(String mode, String otherText) {
    if (mode == 'other') {
      final custom = otherText.trim();
      return custom.isNotEmpty ? custom : 'other';
    }
    return mode;
  }
}

class BookingModeField extends StatelessWidget {
  const BookingModeField({
    super.key,
    required this.mode,
    required this.otherController,
    required this.onModeChanged,
  });

  final String mode;
  final TextEditingController otherController;
  final ValueChanged<String> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          value: BookingModeOptions.values.contains(mode)
              ? mode
              : BookingModeOptions.defaultValue,
          decoration: const InputDecoration(
            labelText: 'Booking mode',
            border: OutlineInputBorder(),
          ),
          items: BookingModeOptions.values
              .map(
                (value) => DropdownMenuItem(
                  value: value,
                  child: Text(BookingModeOptions.label(value)),
                ),
              )
              .toList(),
          onChanged: (value) => onModeChanged(value ?? BookingModeOptions.defaultValue),
        ),
        if (mode == 'other') ...[
          const SizedBox(height: 8),
          AppInput(
            controller: otherController,
            label: 'Specify booking mode',
            hint: 'e.g. Agoda, referral, Facebook',
          ),
        ],
      ],
    );
  }
}
