import 'package:flutter/material.dart';

import 'admin_room_form_constants.dart';

/// Shared hourly block pricing helpers (mirrors backend RoomBillingSupport).
class HourlyBilling {
  HourlyBilling._();

  static const blockHourOptions = [1, 2, 3, 4, 6, 8, 12, 24];

  static bool isHourly(Map<String, dynamic> room) =>
      (room['billing_mode'] ?? 'nightly').toString().toLowerCase() == 'hourly';

  static int blockHours(Map<String, dynamic> room) =>
      parseAdminInt(room['block_hours'], 3);

  static double pricePerBlock(Map<String, dynamic> room) {
    final block = parseAdminDouble(room['price_per_block']);
    if (block > 0) return block;
    return parseAdminDouble(room['price_per_night']);
  }

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
      pricePerNight: parseAdminDouble(room['price_per_night']),
      checkIn: checkIn,
      checkOut: checkOut,
    );
  }

  /// Clock-based stay window: check-in = selected date + current wall-clock time;
  /// hourly checkout = check-in + [blockHours]; nightly uses overnight checkout date at 11:00.
  static ({DateTime checkIn, DateTime checkOut}) clockBasedStayWindow(
    Map<String, dynamic> room,
    DateTime checkInDate, {
    DateTime? checkOutDate,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final checkIn = DateTime(
      checkInDate.year,
      checkInDate.month,
      checkInDate.day,
      clock.hour,
      clock.minute,
      clock.second,
    );

    if (isHourly(room)) {
      final hours = blockHours(room);
      final safeHours = hours < 1 ? 1 : hours;
      return (checkIn: checkIn, checkOut: checkIn.add(Duration(hours: safeHours)));
    }

    final outDay = checkOutDate ?? checkInDate.add(const Duration(days: 1));
    final sameOrBefore = !outDay.isAfter(
      DateTime(checkInDate.year, checkInDate.month, checkInDate.day),
    );
    final resolvedOut = sameOrBefore
        ? checkInDate.add(const Duration(days: 1))
        : outDay;
    return (
      checkIn: checkIn,
      checkOut: DateTime(
        resolvedOut.year,
        resolvedOut.month,
        resolvedOut.day,
        11,
        0,
      ),
    );
  }

  /// Mirrors backend [CustomerStayPricing] for date-only customer bookings.
  /// Prefer [clockBasedStayWindow] for new walk-in / check-in flows.
  static DateTime customerStayCheckIn(DateTime checkInDate) {
    final now = DateTime.now();
    return DateTime(
      checkInDate.year,
      checkInDate.month,
      checkInDate.day,
      now.hour,
      now.minute,
      now.second,
    );
  }

  static DateTime customerStayCheckOut(
    Map<String, dynamic> room,
    DateTime checkInDate,
    DateTime checkOutDate,
  ) {
    return clockBasedStayWindow(
      room,
      checkInDate,
      checkOutDate: checkOutDate,
    ).checkOut;
  }

  static double customerDateStayCharge(
    Map<String, dynamic> room,
    DateTime checkInDate,
    DateTime checkOutDate,
  ) {
    final window = clockBasedStayWindow(
      room,
      checkInDate,
      checkOutDate: checkOutDate,
    );
    return stayCharge(room, window.checkIn, window.checkOut);
  }

  static double blockExtensionFee(Map<String, dynamic> room) {
    return _round50(pricePerBlock(room));
  }

  static String priceLabel(Map<String, dynamic> room) {
    if (isHourly(room)) {
      final price = pricePerBlock(room);
      final hours = blockHours(room);
      return '₱${price.toStringAsFixed(0)} / $hours hr';
    }
    final nightly = parseAdminDouble(room['price_per_night']);
    return '₱${nightly.toStringAsFixed(0)} / night';
  }

  static double extraHourRate(Map<String, dynamic> room) {
    final rate = parseAdminDouble(room['price_per_extra_hour']);
    return rate > 0 ? _round50(rate) : 0;
  }

  static double customHoursExtensionFee(double pricePerExtraHour, int hours) {
    if (hours < 1 || pricePerExtraHour <= 0) return 0;
    return _round50(pricePerExtraHour * hours);
  }

  static double _round50(double value) => (value / 50).round() * 50;

  static double round50(double value) => _round50(value);

  static DateTime combineDateAndTime(DateTime date, TimeOfDay time) => DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );

  /// Default admin walk-in check-in time (nearest 30-minute slot from now).
  static TimeOfDay defaultAdminCheckInTime() =>
      snapToSlot(TimeOfDay.now());

  static TimeOfDay snapToSlot(TimeOfDay time) {
    final total = time.hour * 60 + time.minute;
    final snapped = ((total + 15) ~/ 30) * 30;
    final clamped = snapped % (24 * 60);
    return TimeOfDay(hour: clamped ~/ 60, minute: clamped % 60);
  }

  /// Default admin walk-in check-out time for the selected stay window.
  static TimeOfDay defaultAdminCheckOutTime(
    Map<String, dynamic> room,
    DateTime checkInDate,
    DateTime checkOutDate,
    TimeOfDay checkInTime,
  ) {
    final outAt = adminStayCheckOut(room, checkInDate, checkOutDate, checkInTime);
    return TimeOfDay(hour: outAt.hour, minute: outAt.minute);
  }

  static DateTime adminStayCheckIn(DateTime checkInDate, TimeOfDay checkInTime) =>
      combineDateAndTime(checkInDate, checkInTime);

  static DateTime adminStayCheckOut(
    Map<String, dynamic> room,
    DateTime checkInDate,
    DateTime checkOutDate,
    TimeOfDay checkInTime,
  ) {
    if (!isHourly(room)) {
      return combineDateAndTime(
        checkOutDate,
        const TimeOfDay(hour: 11, minute: 0),
      );
    }
    final sameDay = checkInDate.year == checkOutDate.year &&
        checkInDate.month == checkOutDate.month &&
        checkInDate.day == checkOutDate.day;
    if (sameDay) {
      return adminStayCheckIn(checkInDate, checkInTime)
          .add(Duration(hours: blockHours(room)));
    }
    return combineDateAndTime(
      checkOutDate,
      const TimeOfDay(hour: 11, minute: 0),
    );
  }

  static double adminDateStayCharge(
    Map<String, dynamic> room,
    DateTime checkInDate,
    DateTime checkOutDate,
    TimeOfDay checkInTime,
    TimeOfDay checkOutTime,
  ) {
    return stayCharge(
      room,
      adminStayCheckIn(checkInDate, checkInTime),
      combineDateAndTime(checkOutDate, checkOutTime),
    );
  }
}
