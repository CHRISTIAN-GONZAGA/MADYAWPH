import 'package:flutter/material.dart';

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
    if (status == 'available' || status == 'reserved') return true;
    if (status.isEmpty) {
      final guest = (room['current_guest_name'] ?? '').toString().trim();
      return guest.isEmpty;
    }
    return false;
  }

  /// Normalizes Mongo/API room identifiers for booking requests.
  static String roomIdOf(Map<String, dynamic> room) {
    final raw = room['id'] ?? room['_id'];
    return normalizeRoomIdString(raw);
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

  /// Rooms with a booking not yet checked in (booked or reserved only).
  static bool isAwaitingCheckIn(Map<String, dynamic> room) {
    final s = statusOf(room);
    return s == 'booked' || s == 'reserved';
  }

  static int bookedRoomCount(List<Map<String, dynamic>> rooms) {
    return rooms.where(isAwaitingCheckIn).length;
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
    return '${inD.month}/${inD.day} → ${outD.month}/${outD.day} · $nights night${nights == 1 ? '' : 's'}';
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
      final s = statusOf(r);
      if (s == 'available') vacant++;
      if (s == 'checked_in' || s == 'booked' || s == 'reserved') {
        occupied++;
      }
      if (s == 'maintenance') maintenance++;
    }
    return {
      'total': rooms.length,
      'vacant': vacant,
      'occupied': occupied,
      'cleaning': maintenance,
      'maintenance': maintenance,
    };
  }

  /// Checkout moment using booking time when available (defaults 11:00 AM).
  static DateTime? checkoutDateTime(Map<String, dynamic> room) {
    final booking = room['latest_booking'] as Map?;
    final raw = (room['current_check_out'] ??
            booking?['check_out_date'] ??
            '')
        .toString();
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

  static bool isCheckoutSoon(Map<String, dynamic> room) {
    final mins = minutesUntilCheckout(room);
    if (mins == null) return false;
    return mins >= 0 && mins <= 30;
  }

  static DateTime? parseDate(dynamic raw) {
    final s = raw?.toString() ?? '';
    if (s.isEmpty) return null;
    return DateTime.tryParse(s.split('T').first);
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
    final status = statusOf(room);
    if (status == 'checked_in') return false;
    if (status != 'reserved' && status != 'booked') return false;
    final start = stayStartDate(room);
    if (start == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startDay = DateTime(start.year, start.month, start.day);
    final days = startDay.difference(today).inDays;
    return days >= 0 && days <= withinDays;
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

  static String guestName(Map<String, dynamic> room) {
    final n = (room['current_guest_name'] ?? '').toString();
    if (n.isNotEmpty) return n;
    final b = room['latest_booking'] as Map<String, dynamic>?;
    return (b?['guest_name'] ?? '—').toString();
  }

  static String formatStayRange(Map<String, dynamic> room) {
    final inD = stayStartDate(room);
    final outD = stayEndDate(room);
    if (inD == null && outD == null) return '—';
    String fmt(DateTime? d) =>
        d == null ? '—' : '${d.month}/${d.day}/${d.year}';
    return '${fmt(inD)} → ${fmt(outD)}';
  }

  static int reservedArrivingSoonCount(List<Map<String, dynamic>> rooms) {
    return rooms.where(isStayArrivingSoon).length;
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
      if (s == 'available') vacant++;
      if (s == 'checked_in') checkedIn++;
      if (s == 'reserved') reserved++;
      if (s == 'booked') booked++;
      if (s == 'maintenance') maintenance++;
    }
    final reservedSoon = reservedArrivingSoonCount(rooms);
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

  static double collectiblesForRooms(List<Map<String, dynamic>> rooms) {
    var sum = 0.0;
    for (final r in rooms) {
      if (!isCheckoutSoon(r)) continue;
      final booking = r['latest_booking'] as Map<String, dynamic>?;
      if (booking == null) continue;
      sum += (booking['total_amount'] as num?)?.toDouble() ?? 0;
      final charges = (r['charges'] as List?) ?? const [];
      for (final c in charges) {
        if (c is Map<String, dynamic>) {
          sum += (c['amount'] as num?)?.toDouble() ?? 0;
        }
      }
    }
    return sum;
  }
}
