/// Pure helpers for admin dashboard UI (no API changes).
class AdminDashboardModels {
  AdminDashboardModels._();

  static String categoryLabel(Map<String, dynamic> room) {
    final cn = (room['category_name'] ?? '').toString().trim();
    if (cn.isNotEmpty) return cn;
    final rt = (room['room_type'] ?? '').toString().trim();
    if (rt.isEmpty) return 'Uncategorized';
    return rt.length == 1 ? rt.toUpperCase() : rt;
  }

  static String statusOf(Map<String, dynamic> room) =>
      (room['status'] ?? '').toString().toLowerCase();

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
    final total = rooms.length;
    final occ = total > 0 ? ((total - vacant) / total * 100).round() : 0;
    return {
      'label': label,
      'total': total,
      'vacant': vacant,
      'checked_in': checkedIn,
      'reserved': reserved,
      'booked': booked,
      'maintenance': maintenance,
      'occupancy': occ,
    };
  }

  /// Default hotel checkout time 11:00 AM on check-out date.
  static DateTime? checkoutDateTime(Map<String, dynamic> room) {
    final raw = (room['current_check_out'] ?? '').toString();
    if (raw.isEmpty) return null;
    final d = DateTime.tryParse(raw.split('T').first);
    if (d == null) return null;
    return DateTime(d.year, d.month, d.day, 11, 0);
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
