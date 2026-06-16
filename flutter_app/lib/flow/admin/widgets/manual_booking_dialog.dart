import 'package:dio/dio.dart';

import '../../../dio_client.dart';
import '../admin_dashboard_models.dart';
import '../../widgets/complete_guest_booking_dialog.dart';
import 'hourly_billing.dart';

/// Admin walk-in gateway — always creates a **local** booking (`source: admin`).
Future<void> submitAdminWalkInBooking({
  required Map<String, dynamic> room,
  required CompleteGuestBookingPayload payload,
}) async {
  final roomId = AdminDashboardModels.roomIdOf(room);
  if (roomId.isEmpty) {
    throw StateError('Room ID missing. Refresh the dashboard and try again.');
  }

  final checkInDate = DateTime.parse(payload.checkIn);
  final checkOutDate = DateTime.parse(payload.checkOut);
  final inAt = HourlyBilling.customerStayCheckIn(checkInDate);
  final outAt =
      HourlyBilling.customerStayCheckOut(room, checkInDate, checkOutDate);

  final body = <String, dynamic>{
    'room_id': roomId,
    'guest_name': payload.guestName,
    'guest_email': payload.guestEmail,
    'guest_phone': payload.guestPhone,
    'check_in_at': inAt.toIso8601String(),
    'check_out_at': outAt.toIso8601String(),
    'payment_method': payload.paymentMethod,
    'check_in_now': !HourlyBilling.isHourly(room),
    if (payload.discountType != 'none') 'discount_type': payload.discountType,
  };

  final hasGuestId = payload.guestIdFile != null;
  final hasDiscountId = payload.discountIdFile != null;

  if (hasGuestId || hasDiscountId) {
    final map = <String, dynamic>{};
    for (final entry in body.entries) {
      map[entry.key] = entry.value.toString();
    }
    if (hasGuestId) {
      map['guest_id_file'] = await MultipartFile.fromFile(
        payload.guestIdFile!.path,
        filename: payload.guestIdFile!.name.isNotEmpty
            ? payload.guestIdFile!.name
            : 'guest_id.jpg',
      );
    }
    if (hasDiscountId) {
      map['discount_id_file'] = await MultipartFile.fromFile(
        payload.discountIdFile!.path,
        filename: payload.discountIdFile!.name.isNotEmpty
            ? payload.discountIdFile!.name
            : 'discount_id.jpg',
      );
    }
    await portalDio().post('/admin/bookings', data: FormData.fromMap(map));
    return;
  }

  await portalDio().post('/admin/bookings', data: body);
}
