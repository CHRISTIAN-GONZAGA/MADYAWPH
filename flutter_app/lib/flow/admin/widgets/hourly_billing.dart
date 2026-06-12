/// Shared hourly block pricing helpers (mirrors backend RoomBillingSupport).
class HourlyBilling {
  HourlyBilling._();

  static const blockHourOptions = [1, 2, 3, 4, 6, 8, 12, 24];

  static bool isHourly(Map<String, dynamic> room) =>
      (room['billing_mode'] ?? 'nightly').toString().toLowerCase() == 'hourly';

  static int blockHours(Map<String, dynamic> room) =>
      (room['block_hours'] as num?)?.toInt() ?? 3;

  static double pricePerBlock(Map<String, dynamic> room) =>
      (room['price_per_block'] as num?)?.toDouble() ??
      (room['price_per_night'] as num?)?.toDouble() ??
      0;

  static int stayHours(DateTime checkIn, DateTime checkOut) {
    final minutes = checkOut.difference(checkIn).inMinutes;
    return (minutes / 60).ceil().clamp(1, 720);
  }

  static int blocksForStay(int stayHours, int blockHours) {
    final bh = blockHours < 1 ? 1 : blockHours;
    return (stayHours / bh).ceil();
  }

  static double hourlyCharge({
    required double pricePerBlock,
    required int blockHours,
    required DateTime checkIn,
    required DateTime checkOut,
  }) {
    final hours = stayHours(checkIn, checkOut);
    final blocks = blocksForStay(hours, blockHours);
    return _round50(pricePerBlock * blocks);
  }

  static double nightlyCharge({
    required double pricePerNight,
    required DateTime checkIn,
    required DateTime checkOut,
  }) {
    final nights = checkOut.difference(checkIn).inDays;
    final safeNights = nights > 0 ? nights : 1;
    return _round50(pricePerNight * safeNights);
  }

  static double stayCharge(Map<String, dynamic> room, DateTime checkIn, DateTime checkOut) {
    if (isHourly(room)) {
      return hourlyCharge(
        pricePerBlock: pricePerBlock(room),
        blockHours: blockHours(room),
        checkIn: checkIn,
        checkOut: checkOut,
      );
    }
    return nightlyCharge(
      pricePerNight: (room['price_per_night'] as num?)?.toDouble() ?? 0,
      checkIn: checkIn,
      checkOut: checkOut,
    );
  }

  static String priceLabel(Map<String, dynamic> room) {
    if (isHourly(room)) {
      final price = pricePerBlock(room);
      final hours = blockHours(room);
      return '₱${price.toStringAsFixed(0)} / $hours hr';
    }
    final nightly = (room['price_per_night'] as num?)?.toDouble() ?? 0;
    return '₱${nightly.toStringAsFixed(0)} / night';
  }

  static List<int> extensionHourOptions(Map<String, dynamic> room, {int maxBlocks = 8}) {
    if (!isHourly(room)) return const [];
    final bh = blockHours(room);
    return List.generate(maxBlocks, (i) => (i + 1) * bh);
  }

  static double _round50(double value) => (value / 50).round() * 50;
}
