import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../navigation_keys.dart';
import '../admin_dashboard_models.dart';
import '../admin_room_detail_screen.dart';
import 'admin_walk_in_customer_booking.dart';
import 'admin_dashboard_routes.dart';

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

  /// Summary / sheet room tap — same push flow as [AdminRoomSummaryDetailScreen].
  static Future<void> openSummaryRoomDetail({
    required Map<String, dynamic> room,
    BuildContext? sheetContext,
    BuildContext? snackContext,
    Future<void> Function()? onClosed,
  }) async {
    final id = AdminDashboardModels.roomIdOf(room);
    if (id.isEmpty) {
      final ctx = snackContext ?? adminDashboardNavigatorKey.currentContext;
      if (ctx != null && ctx.mounted) _missingRoomId(ctx);
      return;
    }

    Future<void> open() async {
      await openDetailById(id, snackContext: snackContext);
      if (onClosed != null) await onClosed();
    }

    if (sheetContext != null) {
      final sheetNavigator = Navigator.of(sheetContext);
      if (sheetNavigator.canPop()) {
        sheetNavigator.pop();
      }
      await adminRoomAfterFrame(open);
      return;
    }

    await open();
  }

  /// After an optional bottom sheet closes, open walk-in booking or room details.
  static Future<void> openRoom(
    BuildContext context, {
    required Map<String, dynamic> room,
    required Future<void> Function() onSuccess,
    BuildContext? sheetContext,
    AdminRoomOpenMode mode = AdminRoomOpenMode.walkInOrDetail,
  }) async {
    if (mode == AdminRoomOpenMode.manageOnly) {
      await openSummaryRoomDetail(
        room: room,
        sheetContext: sheetContext,
        snackContext: context,
        onClosed: onSuccess,
      );
      return;
    }

    final hadSheet = sheetContext != null;
    if (hadSheet) {
      final sheetNavigator = Navigator.of(sheetContext);
      if (sheetNavigator.canPop()) {
        sheetNavigator.pop();
      }
    }

    Future<void> run() async {
      final navContext = adminDashboardNavigatorKey.currentContext ?? context;
      if (!navContext.mounted) return;
      await _openRoomNow(
        navContext,
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

    await openDetailById(
      AdminDashboardModels.roomIdOf(room),
      snackContext: context,
    );
    await onSuccess();
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

  /// Pushes or opens in-shell [AdminRoomDetailScreen] (Summary list tiles, Bookings).
  static Future<void> openDetailById(
    String roomId, {
    BuildContext? snackContext,
  }) async {
    final id = AdminDashboardModels.normalizeRoomIdString(roomId);
    if (id.isEmpty) {
      final ctx = snackContext ?? adminDashboardNavigatorKey.currentContext;
      if (ctx != null && ctx.mounted) _missingRoomId(ctx);
      return;
    }

    final ctx = snackContext ?? adminDashboardNavigatorKey.currentContext;
    final nested = adminDashboardNavigatorKey.currentState;
    final atDashboardRoot = nested == null || !nested.canPop();

    // Summary tab at dashboard root: open inside shell (reliable on device).
    if (ctx != null &&
        ctx.mounted &&
        atDashboardRoot &&
        AdminDashboardRoutes.tryOpenDetail(ctx, id)) {
      return;
    }

    final route = MaterialPageRoute<void>(
      builder: (_) => AdminRoomDetailScreen(roomId: id),
    );

    if (nested != null) {
      await nested.push(route);
      return;
    }

    if (ctx != null && ctx.mounted) {
      await Navigator.of(ctx).push(route);
      return;
    }

    final fallbackCtx = adminDashboardNavigatorKey.currentContext;
    if (fallbackCtx != null && fallbackCtx.mounted) {
      ScaffoldMessenger.of(fallbackCtx).showSnackBar(
        const SnackBar(content: Text('Unable to open room details.')),
      );
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
