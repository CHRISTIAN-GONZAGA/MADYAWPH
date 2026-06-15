import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../admin_dashboard_models.dart';
import '../admin_room_detail_screen.dart';
import 'manual_booking_dialog.dart';

/// How a room tile should open from the admin dashboard.
enum AdminRoomOpenMode {
  /// Vacant/available rooms open walk-in booking; others open room details.
  walkInOrDetail,

  /// Always open the room management dashboard (fees, checkout, transfer, status).
  manageOnly,
}

/// Centralized navigation for admin room tiles, sheets, walk-in, and manage-rooms.
abstract final class AdminRoomNavigation {
  /// Tap on room board tile — book if vacant, otherwise open room details.
  static Future<void> handleRoomTap(
    BuildContext context, {
    required Map<String, dynamic> room,
    required Future<void> Function() onSuccess,
    BuildContext? sheetContext,
    AdminRoomOpenMode mode = AdminRoomOpenMode.walkInOrDetail,
  }) {
    return openRoom(
      context,
      room: room,
      onSuccess: onSuccess,
      sheetContext: sheetContext,
      mode: mode,
    );
  }

  /// After an optional bottom sheet closes, open walk-in booking or room details.
  static Future<void> openRoom(
    BuildContext context, {
    required Map<String, dynamic> room,
    required Future<void> Function() onSuccess,
    BuildContext? sheetContext,
    AdminRoomOpenMode mode = AdminRoomOpenMode.walkInOrDetail,
  }) async {
    final hadSheet = sheetContext != null;
    if (hadSheet) {
      final sheetNavigator = Navigator.of(sheetContext);
      if (sheetNavigator.canPop()) {
        sheetNavigator.pop();
      }
    }

    Future<void> run() async {
      if (!context.mounted) return;
      await _openRoomNow(
        context,
        room: room,
        onSuccess: onSuccess,
        mode: mode,
      );
    }

    if (hadSheet) {
      await adminRoomAfterFrame(run);
      return;
    }

    await run();
  }

  static Future<void> _openRoomNow(
    BuildContext context, {
    required Map<String, dynamic> room,
    required Future<void> Function() onSuccess,
    required AdminRoomOpenMode mode,
  }) async {
    if (mode == AdminRoomOpenMode.manageOnly) {
      await openDetailById(context, AdminDashboardModels.roomIdOf(room));
      return;
    }

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
    final result = await _pushRoute<bool>(
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

    await _pushRoute<void>(
      context,
      AdminRoomDetailScreen(roomId: id),
    );
  }

  static Future<T?> _pushRoute<T>(BuildContext context, Widget page) {
    if (!context.mounted) return Future.value(null);
    return Navigator.of(context).push<T>(
      MaterialPageRoute<T>(builder: (_) => page),
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

/// Runs [action] after the current frame (and optional sheet pop animation).
Future<void> adminRoomAfterFrame(Future<void> Function() action) {
  final completer = Completer<void>();
  SchedulerBinding.instance.addPostFrameCallback((_) async {
    try {
      await action();
    } finally {
      if (!completer.isCompleted) completer.complete();
    }
  });
  return completer.future;
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
