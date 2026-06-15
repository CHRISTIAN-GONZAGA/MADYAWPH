import 'package:flutter/material.dart';

import '../admin_dashboard_models.dart';
import '../admin_room_detail_screen.dart';
import 'manual_booking_dialog.dart';

/// Centralized navigation for admin room tiles, sheets, walk-in, and manage-rooms.
abstract final class AdminRoomNavigation {
  /// Tap on room board tile — book if vacant, otherwise open room details.
  static Future<void> handleRoomTap(
    BuildContext context, {
    required Map<String, dynamic> room,
    required Future<void> Function() onSuccess,
    BuildContext? sheetContext,
  }) {
    return openRoom(
      context,
      room: room,
      onSuccess: onSuccess,
      sheetContext: sheetContext,
    );
  }

  /// After an optional bottom sheet closes, open walk-in booking or room details.
  static Future<void> openRoom(
    BuildContext context, {
    required Map<String, dynamic> room,
    required Future<void> Function() onSuccess,
    BuildContext? sheetContext,
  }) async {
    await _dismissSheet(sheetContext);
    if (!context.mounted) return;

    if (AdminDashboardModels.isWalkInBookable(room)) {
      final roomId = AdminDashboardModels.roomIdOf(room);
      if (roomId.isEmpty) {
        _missingRoomId(context);
        return;
      }
      final booked = await openWalkInBooking(
        context,
        room: room,
        onSuccess: onSuccess,
      );
      if (booked && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Room ${room['room_number']} booked successfully.',
            ),
          ),
        );
      }
      return;
    }

    await openDetailById(context, AdminDashboardModels.roomIdOf(room));
  }

  static Future<bool> openWalkInBooking(
    BuildContext context, {
    required Map<String, dynamic> room,
    required Future<void> Function() onSuccess,
  }) async {
    final navigator = Navigator.of(context);
    final result = await navigator.push<bool>(
      MaterialPageRoute<bool>(
        builder: (routeContext) => AdminWalkInBookingScreen(
          room: room,
          onSuccess: onSuccess,
        ),
      ),
    );
    return result == true;
  }

  static Future<void> openDetailById(BuildContext context, String roomId) async {
    final id = AdminDashboardModels.normalizeRoomIdString(roomId);
    if (id.isEmpty) {
      _missingRoomId(context);
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (routeContext) => AdminRoomDetailScreen(roomId: id),
      ),
    );
  }

  static Future<void> _dismissSheet(BuildContext? sheetContext) async {
    if (sheetContext == null) return;
    final navigator = Navigator.of(sheetContext);
    if (navigator.canPop()) {
      await navigator.maybePop();
    }
  }

  static void _missingRoomId(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Room ID missing. Pull to refresh the dashboard and try again.',
        ),
      ),
    );
  }
}

/// @deprecated Use [AdminRoomNavigation.handleRoomTap].
Future<void> handleAdminWalkInRoomTap(
  BuildContext context, {
  required Map<String, dynamic> room,
  required Future<void> Function() onSuccess,
}) {
  return AdminRoomNavigation.handleRoomTap(
    context,
    room: room,
    onSuccess: onSuccess,
  );
}

/// @deprecated Use [AdminRoomNavigation.openWalkInBooking].
Future<bool> showAdminManualBookingDialog({
  required BuildContext context,
  required Map<String, dynamic> room,
  required Future<void> Function() onSuccess,
}) {
  return AdminRoomNavigation.openWalkInBooking(
    context,
    room: room,
    onSuccess: onSuccess,
  );
}
