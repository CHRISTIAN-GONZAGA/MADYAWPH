/// Shared hourly block pricing helpers (mirrors backend RoomBillingSupport).
class HourlyBilling {
  HourlyBilling._();

  static const blockHourOptions = [1, 2, 3, 4, 6, 8, 12, 24];

  static bool isHourly(Map<String, dynamic> room) =>
      (room['billing_mode'] ?? 'nightly').toString().toLowerCase() == 'hourly';

  static int blockHours(Map<String, dynamic> room) =>
      (room['block_hours'] as num?)?.toInt() ?? 1;

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

  /// Mirrors backend [CustomerStayPricing] for date-only customer bookings.
  static DateTime customerStayCheckIn(DateTime checkInDate) => DateTime(
        checkInDate.year,
        checkInDate.month,
        checkInDate.day,
        14,
        0,
      );

  static DateTime customerStayCheckOut(
    Map<String, dynamic> room,
    DateTime checkInDate,
    DateTime checkOutDate,
  ) {
    if (!isHourly(room)) {
      return DateTime(
        checkOutDate.year,
        checkOutDate.month,
        checkOutDate.day,
        11,
        0,
      );
    }
    final inAt = customerStayCheckIn(checkInDate);
    final sameDay = checkInDate.year == checkOutDate.year &&
        checkInDate.month == checkOutDate.month &&
        checkInDate.day == checkOutDate.day;
    if (sameDay) {
      return inAt.add(Duration(hours: blockHours(room)));
    }
    return DateTime(
      checkOutDate.year,
      checkOutDate.month,
      checkOutDate.day,
      11,
      0,
    );
  }

  static double customerDateStayCharge(
    Map<String, dynamic> room,
    DateTime checkInDate,
    DateTime checkOutDate,
  ) {
    return stayCharge(
      room,
      customerStayCheckIn(checkInDate),
      customerStayCheckOut(room, checkInDate, checkOutDate),
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

  static double extraHourRate(Map<String, dynamic> room) {
    final rate = (room['price_per_extra_hour'] as num?)?.toDouble() ?? 0;
    return rate > 0 ? _round50(rate) : 0;
  }

  static double customHoursExtensionFee(double pricePerExtraHour, int hours) {
    if (hours < 1 || pricePerExtraHour <= 0) return 0;
    return _round50(pricePerExtraHour * hours);
  }

  static double _round50(double value) => (value / 50).round() * 50;

  static double round50(double value) => _round50(value);
}
