const adminRoomTypeOptions = ['Single', 'Double', 'Suite', 'Deluxe'];

const adminRoomStatusOptions = [
  'available',
  'booked',
  'checked_in',
  'checked_out',
  'cleaning',
  'maintenance',
  'reserved',
];

/// Mongo / Laravel JSON often returns decimals as strings — never use `as num?`.
double parseAdminDouble(dynamic raw, [double fallback = 0]) {
  if (raw == null) return fallback;
  if (raw is num) return raw.toDouble();
  if (raw is String) {
    final cleaned = raw.trim().replaceAll(RegExp(r'[₱,\s]'), '');
    if (cleaned.isEmpty) return fallback;
    return double.tryParse(cleaned) ?? fallback;
  }
  return fallback;
}

int parseAdminInt(dynamic raw, [int fallback = 0]) {
  if (raw == null) return fallback;
  if (raw is int) return raw;
  if (raw is num) return raw.round();
  if (raw is String) {
    final cleaned = raw.trim();
    if (cleaned.isEmpty) return fallback;
    return int.tryParse(cleaned) ??
        double.tryParse(cleaned)?.round() ??
        fallback;
  }
  return fallback;
}

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
  final billing = (room['billing_mode'] ?? 'nightly').toString().toLowerCase();
  if (billing == 'hourly') {
    final block = parseAdminDouble(room['price_per_block']);
    final nightly = parseAdminDouble(room['price_per_night']);
    final price = block > 0 ? block : nightly;
    final hours = parseAdminInt(room['block_hours'], 1);
    return '₱${price.toStringAsFixed(0)} / $hours hr';
  }
  final nightly = parseAdminDouble(room['price_per_night']);
  return '₱${nightly.toStringAsFixed(0)} / night';
}
