import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../dio_client.dart';
import '../admin_dashboard_models.dart';
import '../../widgets/complete_guest_booking_dialog.dart';
import 'hourly_billing.dart';

/// Opens the same "Complete your booking" dialog used for public customers.
Future<bool> showAdminWalkInBookingDialog({
  required BuildContext context,
  required Map<String, dynamic> room,
}) async {
  final payload = await showCompleteGuestBookingDialog(
    context: context,
    room: room,
    config: CompleteGuestBookingConfig.adminWalkIn(room),
  );
  if (payload == null) return false;

  try {
    await submitAdminWalkInBooking(room: room, payload: payload);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Room ${room['room_number']} booked successfully.',
          ),
        ),
      );
    }
    return true;
  } on DioException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dioErrorMessage(e))),
      );
    }
    return false;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
    return false;
  }
}

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
  final outAt = HourlyBilling.customerStayCheckOut(room, checkInDate, checkOutDate);

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

/// @deprecated Walk-in now uses [showAdminWalkInBookingDialog].
class AdminWalkInBookingScreen extends StatelessWidget {
  const AdminWalkInBookingScreen({
    super.key,
    required this.room,
    required this.onSuccess,
    this.onClose,
  });

  final Map<String, dynamic> room;
  final Future<void> Function() onSuccess;
  final void Function(bool success)? onClose;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!context.mounted) return;
      final booked = await showAdminWalkInBookingDialog(
        context: context,
        room: room,
      );
      if (!context.mounted) return;
      if (booked) {
        await onSuccess();
      }
      if (onClose != null) {
        onClose!(booked);
      } else if (context.mounted) {
        Navigator.of(context).pop(booked);
      }
    });
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
