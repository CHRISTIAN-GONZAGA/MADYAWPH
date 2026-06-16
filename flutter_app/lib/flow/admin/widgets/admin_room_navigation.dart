import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../navigation_keys.dart';
import '../../../widgets/app_overlay.dart';
import '../admin_dashboard_models.dart';
import '../admin_room_detail_screen.dart';
import 'admin_dashboard_routes.dart';
import 'admin_walk_in_customer_booking.dart';

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
      await openWalkInBooking(
        context,
        room: room,
        onSuccess: onSuccess,
      );
      return;
    }

    await openDetailById(context, AdminDashboardModels.roomIdOf(room));
  }

  static Future<bool> openWalkInBooking(
    BuildContext context, {
    required Map<String, dynamic> room,
    required Future<void> Function() onSuccess,
  }) async {
    final booked = await showAdminWalkInBookingDialog(
      context: context,
      room: room,
    );
    if (booked) {
      await onSuccess();
    }
    return booked;
  }

  static Future<void> openDetailById(BuildContext context, String roomId) async {
    final id = AdminDashboardModels.normalizeRoomIdString(roomId);
    if (id.isEmpty) {
      _missingRoomId(context);
      return;
    }

    if (!context.mounted) return;

    // Prefer in-shell full screen on the dashboard root route (Summary tab, etc.).
    final routes = AdminDashboardRoutes.maybeOf(context);
    final nested = adminDashboardNavigatorKey.currentState;
    if (routes != null && nested != null && !nested.canPop()) {
      routes.openDetail(id);
      return;
    }

    await pushAdminFullScreen<void>(
      context,
      builder: (_) => AdminRoomDetailScreen(roomId: id),
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
