/// Hotel portal role helpers (admin vs front desk).
abstract final class HotelPortalRole {
  static bool isFrontDesk(String? role) => role == 'frontdesk';

  static bool isHotelAdmin(String? role) =>
      role == 'admin' || role == 'super_admin';

  static bool canManagePropertySetup(String? role) => isHotelAdmin(role);

  /// Walk-in booking, reservation approval, and guest check-in are front desk only.
  static bool canCreateBookings(String? role) => isFrontDesk(role);
}
