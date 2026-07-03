import 'package:flutter/material.dart';

import '../../utils/money_format.dart';
import 'widgets/free_breakfast_selection.dart';

/// Pure helpers for admin dashboard UI (no API changes).
class AdminDashboardModels {
  AdminDashboardModels._();

  static int pendingReservationCount(List<dynamic> reservations) {
    var n = 0;
    for (final raw in reservations) {
      if (raw is! Map<String, dynamic>) continue;
      if ((raw['status'] ?? '').toString() == 'pending_approval') n++;
    }
    return n;
  }

  static int checkoutSoonCount(List<Map<String, dynamic>> rooms) {
    return rooms.where(isCheckoutSoon).length;
  }

  static int pendingAmenityClaimCount(List<dynamic> claims) {
    var n = 0;
    for (final raw in claims) {
      if (raw is! Map<String, dynamic>) continue;
      if ((raw['status'] ?? 'pending').toString() != 'fulfilled') n++;
    }
    return n;
  }

  static bool isBreakfastClaim(Map<String, dynamic> claim) {
    final type =
        (claim['amenityType'] ?? claim['amenity_type'] ?? '').toString().toLowerCase();
    final name =
        (claim['amenityName'] ?? claim['amenity_name'] ?? '').toString().toLowerCase();
    return type.contains('breakfast') || name.contains('breakfast');
  }

  /// Breakfast prep totals from guest amenity claims (quantity-based).
  static Map<String, int> breakfastPrepSummary(List<dynamic> claims) {
    var toPrepare = 0;
    var done = 0;
    var pendingOrders = 0;
    var fulfilledOrders = 0;
    for (final raw in claims) {
      if (raw is! Map<String, dynamic>) continue;
      if (!isBreakfastClaim(raw)) continue;
      final qty = (raw['quantity'] as num?)?.toInt() ?? 1;
      final status = (raw['status'] ?? 'pending').toString();
      if (status == 'fulfilled') {
        done += qty;
        fulfilledOrders++;
      } else {
        toPrepare += qty;
        pendingOrders++;
      }
    }
    return {
      'to_prepare': toPrepare,
      'done': done,
      'pending_orders': pendingOrders,
      'fulfilled_orders': fulfilledOrders,
    };
  }

  static String categoryLabel(Map<String, dynamic> room) {
    final cn = (room['category_name'] ?? '').toString().trim();
    if (cn.isNotEmpty) return cn;
    final rt = (room['room_type'] ?? '').toString().trim();
    if (rt.isEmpty) return 'Uncategorized';
    return rt.length == 1 ? rt.toUpperCase() : rt;
  }

  static String statusOf(Map<String, dynamic> room) {
    final raw = room['status'];
    if (raw is Map) {
      final fromMap = (raw['value'] ?? raw['name'] ?? '')
          .toString()
          .toLowerCase()
          .trim();
      if (fromMap.isNotEmpty) return fromMap;
    }
    final s = (raw ?? '').toString().toLowerCase().trim();
    if (s.isEmpty || s == 'null') return '';
    return s;
  }

  /// True when front desk can create a walk-in booking for this room.
  static bool isWalkInBookable(Map<String, dynamic> room) {
    final status = statusOf(room);
    if (status == 'maintenance' || status == 'checked_in') return false;
    if (status.isEmpty) {
      final guest = (room['current_guest_name'] ?? '').toString().trim();
      return guest.isEmpty;
    }
    return true;
  }

  /// True when staff may schedule a booking (including future dates on occupied rooms).
  static bool canScheduleFutureBooking(Map<String, dynamic> room) {
    return statusOf(room) != 'maintenance';
  }

  /// Booked / reserved arrivals eligible for quick check-in from Summary.
  static bool canQuickCheckIn(Map<String, dynamic> room) {
    if (statusOf(room) == 'checked_in') return false;
    final status = statusOf(room);
    if (status == 'booked' || status == 'reserved') return true;
    if ((status == 'available' ||
            status == 'checked_out' ||
            status.isEmpty) &&
        _hasUpcomingBookingRecord(room)) {
      return true;
    }
    return false;
  }

  /// Guest head count for a checked-in room (adults + children, or demographics).
  static int guestHeadCount(Map<String, dynamic> room) {
    final booking = room['latest_booking'];
    if (booking is Map) {
      final adults = (booking['adults'] as num?)?.toInt() ?? 0;
      final children = (booking['children'] as num?)?.toInt() ?? 0;
      final party = adults + children;
      if (party > 0) return party;
      final male = (booking['guests_male'] as num?)?.toInt() ?? 0;
      final female = (booking['guests_female'] as num?)?.toInt() ?? 0;
      if (male + female > 0) return male + female;
    }
    return 1;
  }

  /// Total guests currently checked in across the hotel.
  static int guestsInHotelNow(List<Map<String, dynamic>> rooms) {
    var total = 0;
    for (final room in rooms) {
      if (statusOf(room) == 'checked_in') {
        total += guestHeadCount(room);
      }
    }
    return total;
  }

  /// Parses dashboard room payloads (JSON maps are not always [Map<String, dynamic>]).
  static List<Map<String, dynamic>> parseRoomMaps(List<dynamic>? raw) {
    if (raw == null || raw.isEmpty) return const [];
    final out = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        out.add(item);
      } else if (item is Map) {
        out.add(Map<String, dynamic>.from(item));
      }
    }
    return out;
  }

  /// Normalizes Mongo/API room identifiers for booking requests.
  static String roomIdOf(Map<String, dynamic> room) {
    for (final key in ['id', '_id', 'room_id']) {
      final normalized = normalizeRoomIdString(room[key]);
      if (normalized.isNotEmpty) return normalized;
    }
    return '';
  }

  /// Normalizes Mongo document ids (menu items, bookings, etc.).
  static String documentIdOf(Map<String, dynamic> doc) {
    for (final key in ['id', '_id']) {
      final normalized = normalizeRoomIdString(doc[key]);
      if (normalized.isNotEmpty) return normalized;
    }
    return '';
  }

  /// Normalizes a raw id value (string, ObjectId map, etc.).
  static String normalizeRoomIdString(dynamic raw) {
    if (raw is Map) {
      final oid = raw[r'$oid'] ?? raw['oid'];
      if (oid != null) return oid.toString().trim();
    }
    final id = (raw ?? '').toString().trim();
    if (id.isEmpty || id == 'null') return '';
    return id;
  }

  /// Display label for booking records in the Book tab (uses room status when checked in).
  static String bookingRecordStatusLabel(
    Map<String, dynamic> booking, {
    Map<String, dynamic>? room,
  }) {
    final roomStatus = room != null
        ? statusOf(room)
        : (booking['room_status'] ?? '').toString().toLowerCase().trim();
    if (roomStatus == 'checked_in') {
      return 'Checked in';
    }

    final status = (booking['status'] ?? '').toString().toLowerCase().trim();
    switch (status) {
      case 'booked':
        return 'Booked';
      case 'reserved':
        return 'Reserved';
      case 'confirmed':
        return 'Booked';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        if (status.isEmpty) return '—';
        return status[0].toUpperCase() + status.substring(1).replaceAll('_', ' ');
    }
  }

  static String reservationStatusLabel(String status) {
    switch (status.toLowerCase().trim()) {
      case 'pending_approval':
      case 'pending':
        return 'Pending approval';
      case 'approved':
      case 'reserved':
        return 'Reserved';
      case 'booked':
        return 'Booked';
      case 'cancelled':
        return 'Cancelled';
      case 'rejected':
        return 'Rejected';
      default:
        if (status.isEmpty) return '—';
        return status[0].toUpperCase() + status.substring(1).replaceAll('_', ' ');
    }
  }

  static Map<String, dynamic>? roomForBooking(
    Map<String, dynamic> booking,
    List<Map<String, dynamic>> rooms,
  ) {
    final roomId = normalizeRoomIdString(booking['room_id']);
    if (roomId.isEmpty) return null;
    for (final room in rooms) {
      if (normalizeRoomIdString(roomIdOf(room)) == roomId) {
        return room;
      }
    }
    return null;
  }

  /// Display label: checked_in → Occupied (API value unchanged).
  static String roomStatusLabel(String status) {
    switch (status.toLowerCase().trim()) {
      case 'checked_in':
        return 'Occupied';
      case 'checked_out':
        return 'Checked out';
      case 'maintenance':
        return 'Maintenance';
      case 'reserved':
        return 'Reserved';
      case 'booked':
        return 'Booked';
      case 'available':
        return 'Available';
      default:
        if (status.isEmpty) return '—';
        return status[0].toUpperCase() + status.substring(1).replaceAll('_', ' ');
    }
  }

  /// Check-in is today or later (excludes stale reserved/booked rows).
  static bool hasCheckInTodayOrLater(Map<String, dynamic> room) {
    final start = stayStartDate(room);
    if (start == null) return true;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startDay = DateTime(start.year, start.month, start.day);
    return !startDay.isBefore(today);
  }

  /// Rooms with a booking not yet checked in (booked or reserved, check-in today+).
  static bool isAwaitingCheckIn(
    Map<String, dynamic> room, {
    int maxDaysAhead = 1,
  }) {
    return qualifiesAsBookedReserved(room, maxDaysAhead: maxDaysAhead);
  }

  static int bookedRoomCount(
    List<Map<String, dynamic>> rooms, {
    int maxDaysAhead = 1,
  }) {
    return rooms
        .where((r) => qualifiesAsBookedReserved(r, maxDaysAhead: maxDaysAhead))
        .length;
  }

  /// Walk-in tile grouping: available | reserved | occupied.
  static String walkInTileStatus(Map<String, dynamic> room) {
    final status = statusOf(room);
    if (status == 'maintenance' || status == 'checked_in') return 'occupied';
    if (status == 'available' || status == 'checked_out') {
      final start = stayStartDate(room);
      if (start != null) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final startDay = DateTime(start.year, start.month, start.day);
        if (startDay.isAfter(today)) return 'reserved';
      }
      return 'available';
    }
    if (status.isEmpty) {
      final guest = (room['current_guest_name'] ?? '').toString().trim();
      return guest.isEmpty ? 'available' : 'occupied';
    }
    if (status == 'reserved' || status == 'booked') {
      final start = stayStartDate(room);
      if (start == null) {
        return status == 'reserved' ? 'reserved' : 'occupied';
      }
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final startDay = DateTime(start.year, start.month, start.day);
      if (startDay.isAfter(today)) return 'reserved';
      return 'occupied';
    }
    return 'occupied';
  }

  static Color walkInTileColor(String walkInStatus) {
    switch (walkInStatus) {
      case 'available':
        return Colors.green.shade600;
      case 'reserved':
        return Colors.orange.shade700;
      default:
        return Colors.red.shade600;
    }
  }

  static String walkInTileStatusLabel(String walkInStatus) {
    switch (walkInStatus) {
      case 'available':
        return 'Available';
      case 'reserved':
        return 'Reserved';
      default:
        return 'Occupied';
    }
  }

  static String roomListTitle(Map<String, dynamic> room) {
    final number = (room['room_number'] ?? '').toString().trim();
    final name = (room['display_name'] ?? '').toString().trim();
    if (number.isEmpty && name.isEmpty) return 'Room';
    if (name.isEmpty) return 'Room $number';
    if (number.isEmpty) return name;
    return 'Room $number · $name';
  }

  static List<Map<String, dynamic>> roomsForCategory(
    List<Map<String, dynamic>> rooms, {
    required String categoryId,
    required String categoryName,
  }) {
    final nameKey = categoryName.trim().toLowerCase();
    final filtered = rooms.where((r) {
      final cid = (r['category_id'] ?? '').toString().trim();
      if (cid.isNotEmpty && cid == categoryId) return true;
      final label = categoryLabel(r).trim().toLowerCase();
      if (label.isEmpty || nameKey.isEmpty) return false;
      return label == nameKey;
    }).toList();
    filtered.sort((a, b) {
      final an = (a['room_number'] ?? '').toString();
      final bn = (b['room_number'] ?? '').toString();
      return an.compareTo(bn);
    });
    return filtered;
  }

  static Map<String, int> walkInStatusCounts(List<Map<String, dynamic>> rooms) {
    var available = 0;
    var reserved = 0;
    var occupied = 0;
    for (final r in rooms) {
      switch (walkInTileStatus(r)) {
        case 'available':
          available++;
        case 'reserved':
          reserved++;
        default:
          occupied++;
      }
    }
    return {
      'available': available,
      'reserved': reserved,
      'occupied': occupied,
    };
  }

  /// Checked in, booked, or reserved — active guest stays.
  static int activeStayRoomCount(List<Map<String, dynamic>> rooms) {
    return rooms.where((r) {
      final s = statusOf(r);
      return s == 'checked_in' || s == 'booked' || s == 'reserved';
    }).length;
  }

  static int stayNights(Map<String, dynamic> booking) {
    final n = (booking['nights'] as num?)?.toInt();
    if (n != null && n > 0) return n;
    final inD = parseDate(booking['check_in_date']);
    final outD = parseDate(booking['check_out_date']);
    if (inD == null || outD == null) return 0;
    return outD.difference(inD).inDays.clamp(0, 365);
  }

  static String formatBookingDuration(Map<String, dynamic> booking) {
    final inD = parseDate(booking['check_in_date']);
    final outD = parseDate(booking['check_out_date']);
    if (inD == null || outD == null) return '—';
    final nights = stayNights(booking);
    final range = formatDateRange(inD, outD);
    if (nights <= 0) return range;
    return '$range · $nights night${nights == 1 ? '' : 's'}';
  }

  static Map<String, List<Map<String, dynamic>>> groupByCategory(
    List<Map<String, dynamic>> rooms,
  ) {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final r in rooms) {
      final label = categoryLabel(r);
      map.putIfAbsent(label, () => []).add(r);
    }
    return map;
  }

  static Map<String, int> statusCounts(List<Map<String, dynamic>> rooms) {
    var vacant = 0;
    var occupied = 0;
    var maintenance = 0;
    for (final r in rooms) {
      if (isWalkInBookable(r)) vacant++;
      if (statusOf(r) == 'checked_in') occupied++;
      if (statusOf(r) == 'maintenance') maintenance++;
    }
    return {
      'total': rooms.length,
      'vacant': vacant,
      'occupied': occupied,
      'cleaning': maintenance,
      'maintenance': maintenance,
      'booked_reserved': bookedRoomCount(rooms),
    };
  }

  /// Checkout moment using booking time when available (defaults 11:00 AM).
  static DateTime? checkoutDateTime(Map<String, dynamic> room) {
    final currentOut = (room['current_check_out'] ?? '').toString();
    final booking =
        hasActiveGuestStay(room) ? room['latest_booking'] as Map? : null;
    final raw = currentOut.isNotEmpty
        ? currentOut
        : (booking?['check_out_date'] ?? '').toString();
    if (raw.isEmpty) return null;
    final d = DateTime.tryParse(raw.split('T').first);
    if (d == null) return null;
    final timeRaw = (booking?['check_out_time'] ?? '').toString();
    if (timeRaw.contains(':')) {
      final parts = timeRaw.split(':');
      final h = int.tryParse(parts[0]) ?? 11;
      final m = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
      return DateTime(d.year, d.month, d.day, h, m);
    }
    return DateTime(d.year, d.month, d.day, 11, 0);
  }

  static TimeOfDay? bookingTimeOfDay(Map<String, dynamic> room, String field) {
    final booking = room['latest_booking'] as Map?;
    final raw = (booking?[field] ?? '').toString();
    if (!raw.contains(':')) return null;
    final parts = raw.split(':');
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts.length > 1 ? parts[1] : '0');
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  static int? minutesUntilCheckout(Map<String, dynamic> room) {
    final at = checkoutDateTime(room);
    if (at == null) return null;
    return at.difference(DateTime.now()).inMinutes;
  }

  /// Minutes after scheduled checkout before the server auto-checks out a guest.
  static const int checkoutGraceMinutes = 40;

  /// Checked-in rooms due within 30 minutes or past checkout (grace window).
  static bool isCheckoutSoon(Map<String, dynamic> room) {
    if (statusOf(room) != 'checked_in') return false;
    final mins = minutesUntilCheckout(room);
    if (mins == null) return false;
    return mins <= 30;
  }

  /// True while guest is past checkout but still inside the grace window.
  static bool isCheckoutInGracePeriod(Map<String, dynamic> room) {
    if (statusOf(room) != 'checked_in') return false;
    final mins = minutesUntilCheckout(room);
    if (mins == null) return false;
    return mins < 0 && mins >= -checkoutGraceMinutes;
  }

  static DateTime? parseDate(dynamic raw) {
    final s = raw?.toString().trim() ?? '';
    if (s.isEmpty || s == 'null') return null;
    final datePart = s.split(RegExp(r'[T\s]')).first;
    return DateTime.tryParse(datePart);
  }

  /// Human-readable date without time noise (no T00:00:00 / midnight zeros).
  static String formatDisplayDate(dynamic raw) {
    final d = parseDate(raw);
    if (d == null) return '—';
    return '${d.month}/${d.day}/${d.year}';
  }

  /// Check-in → check-out for lists and cards.
  static String formatDateRange(dynamic checkIn, dynamic checkOut) {
    final inRaw = checkIn?.toString().trim() ?? '';
    final outRaw = checkOut?.toString().trim() ?? '';
    if (inRaw.isEmpty && outRaw.isEmpty) return '—';
    if (inRaw.isNotEmpty && outRaw.isNotEmpty) {
      return '${formatDisplayDate(inRaw)} → ${formatDisplayDate(outRaw)}';
    }
    if (inRaw.isNotEmpty) return formatDisplayDate(inRaw);
    return formatDisplayDate(outRaw);
  }

  /// Strips midnight-only times like " · 12:00 AM" from API display strings.
  static String cleanStayDisplay(String? raw) {
    final s = raw?.trim() ?? '';
    if (s.isEmpty) return '';
    var cleaned = s
        .replaceAll(RegExp(r'T\d{2}:\d{2}:\d{2}(\.\d+)?Z?'), '')
        .replaceAll(RegExp(r'\s+0{2}:0{2}:\d{2}'), '')
        .replaceAll(RegExp(r' · 12:00 AM'), '')
        .replaceAll(RegExp(r' · 0:00 AM'), '')
        .trim();
    if (cleaned.endsWith('·')) {
      cleaned = cleaned.substring(0, cleaned.length - 1).trim();
    }
    return cleaned;
  }

  static DateTime? stayEndDate(Map<String, dynamic> room) {
    final raw = room['current_check_out'] ??
        (room['latest_booking'] as Map?)?['check_out_date'];
    return parseDate(raw);
  }

  static DateTime? stayStartDate(Map<String, dynamic> room) {
    final raw = room['current_check_in'] ??
        (room['latest_booking'] as Map?)?['check_in_date'];
    return parseDate(raw);
  }

  /// Days from today until check-in (0 = today, 1 = tomorrow). Null if unknown.
  static int? daysUntilCheckIn(Map<String, dynamic> room) {
    final start = stayStartDate(room);
    if (start == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startDay = DateTime(start.year, start.month, start.day);
    return startDay.difference(today).inDays;
  }

  static bool _hasUpcomingBookingRecord(Map<String, dynamic> room) {
    final booking = room['latest_booking'];
    return booking is Map && booking.isNotEmpty;
  }

  /// Booked / reserved arrivals from today through [maxDaysAhead] (1 = today + tomorrow).
  static bool qualifiesAsBookedReserved(
    Map<String, dynamic> room, {
    int maxDaysAhead = 1,
  }) {
    if (statusOf(room) == 'checked_in') return false;

    final days = daysUntilCheckIn(room);
    if (days != null && (days < 0 || days > maxDaysAhead)) return false;

    final status = statusOf(room);
    if (status == 'booked' || status == 'reserved') {
      if (days == null) return hasCheckInTodayOrLater(room);
      return true;
    }

    if ((status == 'available' ||
            status == 'checked_out' ||
            status.isEmpty) &&
        _hasUpcomingBookingRecord(room)) {
      if (days == null) return false;
      return days >= 0 && days <= maxDaysAhead;
    }

    return false;
  }

  /// Summary / category "reserved" bucket (upcoming stays, not yet checked in).
  static bool isSummaryReserved(
    Map<String, dynamic> room, {
    int maxDaysAhead = 1,
  }) {
    if (qualifiesAsBookedReserved(room, maxDaysAhead: maxDaysAhead)) {
      return true;
    }
    if (walkInTileStatus(room) == 'reserved') {
      final days = daysUntilCheckIn(room);
      if (days == null) return true;
      return days >= 0 && days <= maxDaysAhead;
    }
    return false;
  }

  /// Departures within [withinDays] (default 2).
  static bool isStayEndingSoon(Map<String, dynamic> room, {int withinDays = 2}) {
    final end = stayEndDate(room);
    if (end == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final endDay = DateTime(end.year, end.month, end.day);
    final days = endDay.difference(today).inDays;
    return days >= 0 && days <= withinDays;
  }

  /// Arrivals today through [withinDays] ahead for reserved/booked rooms.
  static bool isStayArrivingSoon(Map<String, dynamic> room, {int withinDays = 2}) {
    return qualifiesAsBookedReserved(room, maxDaysAhead: withinDays);
  }

  /// Same-day or past check-in still marked reserved → treat as booked in UI.
  static String displayStatusForRoom(Map<String, dynamic> room) {
    final status = statusOf(room);
    if (status != 'reserved') return status;
    final start = stayStartDate(room);
    if (start == null) return status;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startDay = DateTime(start.year, start.month, start.day);
    if (!startDay.isAfter(today)) return 'booked';
    return status;
  }

  /// True when the room still has an in-house or upcoming guest stay.
  static bool hasActiveGuestStay(Map<String, dynamic> room) {
    final status = statusOf(room);
    if (status == 'checked_in' || status == 'booked' || status == 'reserved') {
      return true;
    }
    if (status == 'maintenance') {
      return (room['current_guest_name'] ?? '').toString().trim().isNotEmpty;
    }
    return false;
  }

  static String guestName(Map<String, dynamic> room) {
    final n = (room['current_guest_name'] ?? '').toString();
    if (n.isNotEmpty) return n;
    if (!hasActiveGuestStay(room)) return '—';
    final b = room['latest_booking'] as Map<String, dynamic>?;
    return (b?['guest_name'] ?? '—').toString();
  }

  static String guestEmail(Map<String, dynamic> room) {
    final booking = room['latest_booking'] as Map<String, dynamic>?;
    return (booking?['guest_email'] ?? room['guest_email'] ?? '')
        .toString()
        .trim();
  }

  static String formatStayRange(Map<String, dynamic> room) {
    final inD = stayStartDate(room);
    final outD = stayEndDate(room);
    if (inD == null && outD == null) return '—';
    return formatDateRange(inD, outD);
  }

  static int reservedArrivingSoonCount(
    List<Map<String, dynamic>> rooms, {
    int withinDays = 2,
  }) {
    return rooms
        .where((r) => isStayArrivingSoon(r, withinDays: withinDays))
        .length;
  }

  static List<Map<String, dynamic>> categoryVacantRooms(
    List<Map<String, dynamic>> rooms,
  ) {
    return rooms.where((r) => walkInTileStatus(r) == 'available').toList();
  }

  static bool isSummaryOccupied(Map<String, dynamic> room) {
    final status = statusOf(room);
    if (status == 'checked_in') return true;
    final guest = guestName(room);
    if (guest == '—' || guest.isEmpty) return false;
    // Guest still on record during maintenance / turnover.
    return status == 'maintenance';
  }

  static List<Map<String, dynamic>> categoryOccupiedRooms(
    List<Map<String, dynamic>> rooms,
  ) {
    return rooms.where(isSummaryOccupied).toList();
  }

  static List<Map<String, dynamic>> categoryReservedSoonRooms(
    List<Map<String, dynamic>> rooms, {
    int withinDays = 1,
  }) {
    return rooms
        .where((r) => isSummaryReserved(r, maxDaysAhead: withinDays))
        .toList();
  }

  static List<Map<String, dynamic>> categoryBookedReservedRooms(
    List<Map<String, dynamic>> rooms, {
    int maxDaysAhead = 1,
  }) {
    return rooms
        .where((r) => qualifiesAsBookedReserved(r, maxDaysAhead: maxDaysAhead))
        .toList();
  }

  static Map<String, dynamic> categoryStats(
    String label,
    List<Map<String, dynamic>> rooms,
  ) {
    var vacant = 0;
    var checkedIn = 0;
    var reserved = 0;
    var booked = 0;
    var maintenance = 0;
    for (final r in rooms) {
      final s = statusOf(r);
      if (walkInTileStatus(r) == 'available') vacant++;
      if (s == 'checked_in') checkedIn++;
      if (isSummaryReserved(r, maxDaysAhead: 1)) reserved++;
      if (s == 'booked' &&
          hasCheckInTodayOrLater(r) &&
          !isSummaryReserved(r, maxDaysAhead: 1)) {
        booked++;
      }
      if (s == 'maintenance') maintenance++;
    }
    final reservedSoon = reservedArrivingSoonCount(rooms, withinDays: 1);
    final awaitingCheckIn = booked + reserved;
    final total = rooms.length;
    final occ = total > 0 ? ((total - vacant) / total * 100).round() : 0;
    return {
      'label': label,
      'total': total,
      'vacant': vacant,
      'checked_in': checkedIn,
      'occupied': checkedIn + booked + reserved,
      'reserved': reserved,
      'reserved_soon': reservedSoon,
      'booked': booked,
      'awaiting_check_in': awaitingCheckIn,
      'maintenance': maintenance,
      'occupancy': occ,
    };
  }

  /// Amount due for one checkout-queue room (charges if present, else booking total).
  static double roomCollectibleAmount(Map<String, dynamic> room) {
    final charges = (room['charges'] as List?) ?? const [];
    var chargeSum = 0.0;
    for (final c in charges) {
      if (c is Map) {
        chargeSum += parseJsonDouble(c['amount']);
      }
    }
    if (chargeSum > 0) return chargeSum;
    final booking = room['latest_booking'] as Map<String, dynamic>?;
    return parseJsonDouble(booking?['total_amount']);
  }

  static double collectiblesForRooms(List<Map<String, dynamic>> rooms) {
    var sum = 0.0;
    for (final r in rooms) {
      if (!isCheckoutSoon(r)) continue;
      sum += roomCollectibleAmount(r);
    }
    return sum;
  }

  /// Receipt-style lines for rooms due for checkout.
  static List<Map<String, dynamic>> collectiblesSummaryLines(
    List<Map<String, dynamic>> rooms,
  ) {
    final lines = <Map<String, dynamic>>[];
    for (final room in rooms) {
      if (!isCheckoutSoon(room)) continue;
      final booking = room['latest_booking'] as Map<String, dynamic>?;
      final chargesRaw = (room['charges'] as List?) ?? const [];
      final chargeLines = <Map<String, dynamic>>[];
      for (final c in chargesRaw) {
        if (c is! Map) continue;
        final amount = parseJsonDouble(c['amount']);
        if (amount == 0) continue;
        chargeLines.add({
          'label': (c['label'] ?? c['type'] ?? 'Charge').toString(),
          'amount': amount,
          'type': (c['type'] ?? '').toString(),
        });
      }
      if (chargeLines.isEmpty) {
        final stay = parseJsonDouble(booking?['total_amount']);
        if (stay > 0) {
          chargeLines.add({
            'label': 'Stay charges',
            'amount': stay,
            'type': 'room',
          });
        }
      }
      final roomTotal = roomCollectibleAmount(room);
      if (roomTotal <= 0 && chargeLines.isEmpty) continue;
      lines.add({
        'room_number': (room['room_number'] ?? '—').toString(),
        'guest_name': guestName(room),
        'booking_reference':
            (booking?['booking_reference'] ?? '').toString(),
        'check_out': formatDisplayDate(
          room['current_check_out'] ?? booking?['check_out_date'],
        ),
        'charges': chargeLines,
        'total': roomTotal,
      });
    }
    return lines;
  }

  /// Physical floor for a room (stored value or parsed from room number).
  static int floorOf(Map<String, dynamic> room) {
    final raw = room['floor'];
    if (raw is int && raw > 0) return raw;
    if (raw is num && raw.toInt() > 0) return raw.toInt();
    final parsed = int.tryParse('$raw');
    if (parsed != null && parsed > 0) return parsed;
    final rn = (room['room_number'] ?? '').toString();
    // Match backend: first digit of room number (101 → floor 1, not 101).
    final match = RegExp(r'^(\d)').firstMatch(rn);
    if (match != null) {
      final fromNumber = int.tryParse(match.group(1)!);
      if (fromNumber != null && fromNumber > 0) return fromNumber;
    }
    return 1;
  }

  static List<int> distinctFloors(List<Map<String, dynamic>> rooms) {
    final floors = <int>{};
    for (final room in rooms) {
      floors.add(floorOf(room));
    }
    final list = floors.toList()..sort();
    return list;
  }

  /// Floors 1..N for a category, including floor 1 when the category has only one floor.
  static List<int> floorsForRooms(
    List<Map<String, dynamic>> rooms, {
    int? categoryFloorCount,
  }) {
    var maxFloor = (categoryFloorCount ?? 1).clamp(1, 99);
    for (final room in rooms) {
      final f = floorOf(room);
      if (f > maxFloor) maxFloor = f;
    }
    return List.generate(maxFloor, (i) => i + 1);
  }

  static int categoryFloorCountFrom(
    String label,
    List<Map<String, dynamic>> categoryRooms,
    List<Map<String, dynamic>>? categories,
  ) {
    if (categories != null) {
      final catId = categoryRooms.isNotEmpty
          ? (categoryRooms.first['category_id'] ?? '').toString().trim()
          : '';
      for (final c in categories) {
        final id = (c['id'] ?? c['_id'] ?? '').toString().trim();
        final name = (c['name'] ?? '').toString().trim();
        final matches = (catId.isNotEmpty && id == catId) || name == label;
        if (!matches) continue;
        final raw = c['floor_count'];
        if (raw is int && raw > 0) return raw.clamp(1, 99);
        if (raw is num && raw.toInt() > 0) return raw.toInt().clamp(1, 99);
        final parsed = int.tryParse('$raw');
        if (parsed != null && parsed > 0) return parsed.clamp(1, 99);
      }
    }
    final fromRooms = distinctFloors(categoryRooms);
    return fromRooms.isEmpty ? 1 : fromRooms.last.clamp(1, 99);
  }

  static bool needsFloorDrilldown(List<Map<String, dynamic>> rooms) {
    return distinctFloors(rooms).length > 1;
  }

  /// Category breakdown always drills through floors (including floor 1 only).
  static bool needsCategoryFloorDrilldown(List<Map<String, dynamic>> rooms) {
    return rooms.isNotEmpty;
  }

  /// Checked-in room with an active booking — eligible for amenity charges.
  static bool isAmenityChargeable(Map<String, dynamic> room) {
    if (statusOf(room) != 'checked_in') return false;
    final booking = room['latest_booking'];
    if (booking is! Map) return false;
    final map = booking is Map<String, dynamic>
        ? booking
        : Map<String, dynamic>.from(booking);
    return documentIdOf(map).isNotEmpty;
  }

  /// Public customer portal booking (online, not walk-in local).
  static bool isPublicOnlineBooking(Map<String, dynamic> room) {
    final booking = room['latest_booking'];
    if (booking is! Map) return false;
    final type = (booking['booking_type'] ?? '').toString().toLowerCase();
    if (type == 'online') return true;
    final source = (booking['booking_source'] ?? '').toString().toLowerCase();
    return source == 'app-customer';
  }

  static Map<String, dynamic>? pendingDateChange(Map<String, dynamic> record) {
    final direct = record['pending_date_change'];
    if (direct is Map) {
      return Map<String, dynamic>.from(direct);
    }
    final meta = record['metadata'];
    if (meta is Map && meta['pending_date_change'] is Map) {
      return Map<String, dynamic>.from(meta['pending_date_change'] as Map);
    }
    return null;
  }

  static bool hasPendingDateChange(Map<String, dynamic> record) {
    final pending = pendingDateChange(record);
    return (pending?['status'] ?? '').toString() == 'pending';
  }

  static List<Map<String, dynamic>> amenityChargeableRooms(
    List<Map<String, dynamic>> rooms,
  ) {
    return sortRoomsByNumber(rooms.where(isAmenityChargeable).toList());
  }

  static List<Map<String, dynamic>> roomsOnFloor(
    List<Map<String, dynamic>> rooms,
    int floor,
  ) {
    return sortRoomsByNumber(
      rooms.where((r) => floorOf(r) == floor).toList(),
    );
  }

  static List<Map<String, dynamic>> sortRoomsByNumber(
    List<Map<String, dynamic>> rooms,
  ) {
    final copy = List<Map<String, dynamic>>.from(rooms);
    int numericKey(Map<String, dynamic> room) {
      final rn = (room['room_number'] ?? '').toString();
      return int.tryParse(RegExp(r'\d+').firstMatch(rn)?.group(0) ?? '') ?? 0;
    }

    copy.sort((a, b) {
      final ak = numericKey(a);
      final bk = numericKey(b);
      if (ak != bk) return ak.compareTo(bk);
      return (a['room_number'] ?? '')
          .toString()
          .compareTo((b['room_number'] ?? '').toString());
    });
    return copy;
  }

  static String floorLabel(int floor) => 'Floor $floor';

  static List<Map<String, dynamic>> breakfastClaims(
    List<dynamic> claims, {
    required bool fulfilled,
  }) {
    return claims.whereType<Map<String, dynamic>>().where((claim) {
      if (!isBreakfastClaim(claim)) return false;
      final status = (claim['status'] ?? 'pending').toString();
      return fulfilled ? status == 'fulfilled' : status != 'fulfilled';
    }).toList(growable: false);
  }

  static String formatFreeBreakfast(List<dynamic>? options) {
    if (options == null || options.isEmpty) return '';
    final parts = <String>[];
    for (final raw in options) {
      final selection = FreeBreakfastSelection.fromDynamic(raw);
      if (selection == null) continue;
      if (selection.quantity > 1) {
        parts.add('${selection.quantity}× ${selection.name}');
      } else {
        parts.add(selection.name);
      }
    }
    return parts.join(', ');
  }
}
