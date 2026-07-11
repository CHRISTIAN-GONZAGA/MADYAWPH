import 'package:dio/dio.dart';

import '../../../dio_client.dart';
import '../admin_dashboard_models.dart';
import '../../widgets/complete_guest_booking_dialog.dart';
import 'free_breakfast_selection.dart';
import 'hourly_billing.dart';

void _appendFreeBreakfastToMap(
  Map<String, dynamic> map,
  List<FreeBreakfastSelection> selections,
) {
  for (var i = 0; i < selections.length; i++) {
    final row = selections[i];
    final prefix = 'free_breakfast_options[$i]';
    if (row.menuItemId.isNotEmpty) {
      map['$prefix[menu_item_id]'] = row.menuItemId;
    }
    map['$prefix[name]'] = row.name;
    map['$prefix[quantity]'] = row.quantity.toString();
    if (row.amenityType.isNotEmpty) {
      map['$prefix[amenity_type]'] = row.amenityType;
    }
  }
}

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

  final breakfastJson = payload.freeBreakfastSelections
      .map((selection) => selection.toJson())
      .toList();

  final body = <String, dynamic>{
    'room_id': roomId,
    'guest_name': payload.guestName,
    if (payload.guestEmail.trim().isNotEmpty)
      'guest_email': payload.guestEmail.trim(),
    if (payload.guestPhone.trim().isNotEmpty)
      'guest_phone': payload.guestPhone.trim(),
    'check_in_at': inAt.toIso8601String(),
    'check_out_at': outAt.toIso8601String(),
    'payment_method': payload.paymentMethod,
    'check_in_now': 0,
    'adults': payload.adults,
    'children': payload.children,
    'guests_male': payload.guestsMale,
    'guests_female': payload.guestsFemale,
    'guest_nationality': payload.guestNationality,
    'booking_mode': payload.bookingMode,
    if (breakfastJson.isNotEmpty) 'free_breakfast_options': breakfastJson,
    if (payload.discountType != 'none') 'discount_type': payload.discountType,
    if (payload.memberShidId.isNotEmpty) 'member_shid_id': payload.memberShidId,
  };

  final hasGuestId = payload.guestIdFile != null;
  final hasDiscountId = payload.discountIdFile != null;

  if (hasGuestId || hasDiscountId) {
    final map = <String, dynamic>{};
    for (final entry in body.entries) {
      if (entry.value is List) continue;
      map[entry.key] = entry.value.toString();
    }
    _appendFreeBreakfastToMap(map, payload.freeBreakfastSelections);
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

/// Books multiple rooms under one guest profile (same stay dates).
Future<void> submitAdminBulkWalkInBooking({
  required List<Map<String, dynamic>> rooms,
  required CompleteGuestBookingPayload payload,
}) async {
  if (rooms.length < 2) {
    throw StateError('Select at least two rooms for a group booking.');
  }

  final roomIds = rooms
      .map(AdminDashboardModels.roomIdOf)
      .where((id) => id.isNotEmpty)
      .toList();
  if (roomIds.length != rooms.length) {
    throw StateError('One or more rooms are missing IDs. Refresh and try again.');
  }

  final anchorRoom = rooms.first;
  final checkInDate = DateTime.parse(payload.checkIn);
  final checkOutDate = DateTime.parse(payload.checkOut);
  final inAt = HourlyBilling.customerStayCheckIn(checkInDate);
  final outAt =
      HourlyBilling.customerStayCheckOut(anchorRoom, checkInDate, checkOutDate);

  final breakfastJson = payload.freeBreakfastSelections
      .map((selection) => selection.toJson())
      .toList();

  final body = <String, dynamic>{
    'room_ids': roomIds,
    'guest_name': payload.guestName,
    if (payload.guestEmail.trim().isNotEmpty)
      'guest_email': payload.guestEmail.trim(),
    if (payload.guestPhone.trim().isNotEmpty)
      'guest_phone': payload.guestPhone.trim(),
    'check_in_at': inAt.toIso8601String(),
    'check_out_at': outAt.toIso8601String(),
    'payment_method': payload.paymentMethod,
    'check_in_now': 0,
    'adults': payload.adults,
    'children': payload.children,
    'guests_male': payload.guestsMale,
    'guests_female': payload.guestsFemale,
    'guest_nationality': payload.guestNationality,
    'booking_mode': payload.bookingMode,
    if (breakfastJson.isNotEmpty) 'free_breakfast_options': breakfastJson,
    if (payload.discountType != 'none') 'discount_type': payload.discountType,
    if (payload.memberShidId.isNotEmpty) 'member_shid_id': payload.memberShidId,
  };

  final hasGuestId = payload.guestIdFile != null;
  final hasDiscountId = payload.discountIdFile != null;

  if (hasGuestId || hasDiscountId) {
    final map = <String, dynamic>{};
    for (var i = 0; i < roomIds.length; i++) {
      map['room_ids[$i]'] = roomIds[i];
    }
    for (final entry in body.entries) {
      if (entry.value is List) continue;
      map[entry.key] = entry.value.toString();
    }
    _appendFreeBreakfastToMap(map, payload.freeBreakfastSelections);
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
    await portalDio().post('/admin/bookings/bulk', data: FormData.fromMap(map));
    return;
  }

  await portalDio().post('/admin/bookings/bulk', data: body);
}
