const adminRoomTypeOptions = ['Single', 'Double', 'Suite', 'Deluxe'];

const adminRoomStatusOptions = [
  'available',
  'booked',
  'checked_in',
  'checked_out',
  'maintenance',
  'reserved',
];

String normalizeAdminRoomChoice(
  dynamic raw,
  String fallback,
  List<String> allowed,
) {
  var v = raw;
  if (v is Map) {
    v = v['value'] ?? v['name'] ?? '';
  }
  final text = v.toString().trim();
  if (text.isEmpty) return fallback;
  if (text.contains('.')) {
    final tail = text.split('.').last.trim();
    for (final option in allowed) {
      if (option.toLowerCase() == tail.toLowerCase()) return option;
    }
  }
  for (final option in allowed) {
    if (option.toLowerCase() == text.toLowerCase()) return option;
  }
  return fallback;
}

String safeAdminRoomRateLabel(Map<String, dynamic> room) {
  try {
    final billing =
        (room['billing_mode'] ?? 'nightly').toString().toLowerCase();
    if (billing == 'hourly') {
      final price = (room['price_per_block'] as num?)?.toDouble() ??
          (room['price_per_night'] as num?)?.toDouble() ??
          0;
      final hours = (room['block_hours'] as num?)?.toInt() ?? 1;
      return '₱${price.toStringAsFixed(0)} / $hours hr';
    }
    final nightly = (room['price_per_night'] as num?)?.toDouble() ?? 0;
    return '₱${nightly.toStringAsFixed(0)} / night';
  } catch (e) {
    return 'Rate unavailable ($e)';
  }
}
