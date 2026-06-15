import 'dart:async';

import 'package:flutter/material.dart';

import '../../../navigation_keys.dart';
import '../admin_dashboard_models.dart';
import '../admin_room_detail_screen.dart';
import 'admin_pushed_route.dart';
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
    if (sheetContext != null) {
      final sheetNavigator = Navigator.of(sheetContext);
      if (sheetNavigator.canPop()) {
        sheetNavigator.pop();
      }
      // Push on the next frame so the sheet route is fully gone first.
      final completer = Completer<void>();
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          if (!context.mounted) return;
          await _openRoomNow(
            context,
            room: room,
            onSuccess: onSuccess,
          );
        } finally {
          if (!completer.isCompleted) completer.complete();
        }
      });
      return completer.future;
    }

    await _openRoomNow(
      context,
      room: room,
      onSuccess: onSuccess,
    );
  }

  static Future<void> _openRoomNow(
    BuildContext context, {
    required Map<String, dynamic> room,
    required Future<void> Function() onSuccess,
  }) async {
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
    final result = await _pushAdmin<bool>(
      context,
      AdminWalkInBookingScreen(
        room: room,
        onSuccess: onSuccess,
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
    await _pushAdmin<void>(
      context,
      AdminRoomDetailScreen(roomId: id),
    );
  }

  static Future<T?> _pushAdmin<T>(BuildContext context, Widget page) {
    final navigator = appNavigatorKey.currentState ?? Navigator.of(context);
    return navigator.push<T>(
      AdminPushedRoute<T>(
        hostContext: context,
        child: page,
      ),
    );
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
