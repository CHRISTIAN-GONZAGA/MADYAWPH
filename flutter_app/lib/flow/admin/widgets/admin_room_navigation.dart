import 'dart:async';
import 'package:gloretto_mobile/widgets/app_notice.dart';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../auth_storage.dart';
import '../../../navigation_keys.dart';
import '../admin_dashboard_models.dart';
import '../admin_room_guest_qr_screen.dart';
import 'admin_check_in_helper.dart';
import 'admin_room_detail_navigation.dart';
import 'admin_summary_room_tile.dart';
import 'admin_walk_in_customer_booking.dart';

/// How a room tile should open from the admin dashboard.
enum AdminRoomOpenMode {
  /// Prompt to book (walk-in) or manage the room.
  bookOrManage,

  /// Always open the room management dashboard (fees, checkout, transfer, status).
  manageOnly,
}

enum _AdminRoomAction { book, manage, checkIn, viewQr }

typedef AdminRoomManageHandler = Future<void> Function(
  BuildContext context,
  Map<String, dynamic> room,
);

/// Centralized navigation for admin room tiles, sheets, walk-in, and manage-rooms.
abstract final class AdminRoomNavigation {
  /// Tap on room tile — choose book or manage, unless [mode] is [AdminRoomOpenMode.manageOnly].
  static Future<void> handleRoomTap(
    BuildContext context, {
    required Map<String, dynamic> room,
    required Future<void> Function() onSuccess,
    BuildContext? sheetContext,
    AdminRoomOpenMode mode = AdminRoomOpenMode.bookOrManage,
    AdminRoomManageHandler? onManageRoom,
    bool preferCheckIn = false,
    bool canCreateBookings = true,
  }) {
    return openRoom(
      context,
      room: room,
      onSuccess: onSuccess,
      sheetContext: sheetContext,
      mode: canCreateBookings ? mode : AdminRoomOpenMode.manageOnly,
      onManageRoom: onManageRoom,
      preferCheckIn: preferCheckIn && canCreateBookings,
      canCreateBookings: canCreateBookings,
    );
  }

  /// Summary sheet room tap — root navigator push (same as hotel totals grid).
  static Future<void> openSummaryRoomDetail({
    required Map<String, dynamic> room,
    BuildContext? sheetContext,
    BuildContext? snackContext,
    Future<void> Function()? onClosed,
  }) async {
    final host = snackContext ?? adminDashboardNavigatorKey.currentContext;
    if (host == null || !host.mounted) return;

    Future<void> open() async {
      await AdminSummaryRoomActions.openRoomDetail(host, room);
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
    AdminRoomOpenMode mode = AdminRoomOpenMode.bookOrManage,
    AdminRoomManageHandler? onManageRoom,
    bool preferCheckIn = false,
    bool canCreateBookings = true,
  }) async {
    final effectiveMode =
        canCreateBookings ? mode : AdminRoomOpenMode.manageOnly;
    if (effectiveMode == AdminRoomOpenMode.manageOnly) {
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
        onManageRoom: onManageRoom,
        preferCheckIn: preferCheckIn,
        canCreateBookings: canCreateBookings,
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
    AdminRoomManageHandler? onManageRoom,
    bool preferCheckIn = false,
    bool canCreateBookings = true,
  }) async {
    final roomNo = (room['room_number'] ?? 'Room').toString();
    final showCheckIn = canCreateBookings &&
        preferCheckIn &&
        AdminDashboardModels.canQuickCheckIn(room);

    final action = await showModalBottomSheet<_AdminRoomAction>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Room $roomNo',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                AdminDashboardModels.guestName(room),
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              if (showCheckIn) ...[
                FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, _AdminRoomAction.checkIn),
                  icon: const Icon(Icons.login_rounded),
                  label: const Text('Check in guest'),
                ),
                const SizedBox(height: 10),
              ],
              if (canCreateBookings) ...[
                FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, _AdminRoomAction.book),
                  icon: const Icon(Icons.event_available_outlined),
                  label: const Text('Book this room'),
                ),
                const SizedBox(height: 10),
              ],
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(ctx, _AdminRoomAction.manage),
                icon: const Icon(Icons.meeting_room_outlined),
                label: const Text('Manage this room'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(ctx, _AdminRoomAction.viewQr),
                icon: const Icon(Icons.qr_code_2_outlined),
                label: const Text('View room QR code'),
              ),
            ],
          ),
        ),
      ),
    );

    if (!context.mounted || action == null) return;

    if (action == _AdminRoomAction.checkIn) {
      if (!canCreateBookings) {
        showAppMessage(
          context,
          'Only front desk can check guests in.',
          isError: true,
        );
        return;
      }
      await performAdminRoomCheckIn(
        context,
        room: room,
        onSuccess: onSuccess,
      );
      return;
    }

    if (action == _AdminRoomAction.viewQr) {
      final roomId = AdminDashboardModels.roomIdOf(room);
      if (roomId.isEmpty) {
        _missingRoomId(context);
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => AdminRoomGuestQrScreen(
            roomId: roomId,
            roomNumber: roomNo,
          ),
        ),
      );
      return;
    }

    if (action == _AdminRoomAction.manage) {
      if (onManageRoom != null) {
        await onManageRoom(context, room);
      } else {
        await AdminSummaryRoomActions.openRoomDetail(context, room);
      }
      await onSuccess();
      return;
    }

    if (!canCreateBookings) {
      showAppMessage(
        context,
        'Only front desk can book rooms.',
        isError: true,
      );
      return;
    }

    if (!AdminDashboardModels.canScheduleFutureBooking(room)) {
      showAppMessage(context, 'Room $roomNo is under maintenance and cannot be booked.',);
      return;
    }

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
  }

  static Future<bool> openWalkInBooking(
    BuildContext context, {
    required Map<String, dynamic> room,
    required Future<void> Function() onSuccess,
    bool canCreateBookings = true,
  }) async {
    if (!canCreateBookings) {
      showAppMessage(
        context,
        'Only front desk can book rooms.',
        isError: true,
      );
      return false;
    }
    final hotelId = (await AuthStorage.hotelId()) ?? '';
    final booked = await showAdminWalkInBookingDialog(
      context: context,
      room: room,
      hotelId: hotelId,
    );
    if (booked) {
      await onSuccess();
    }
    return booked;
  }

  /// Opens room details on the root navigator (Bookings, Checkout).
  static Future<void> openDetailById(
    String roomId, {
    BuildContext? snackContext,
  }) {
    return AdminRoomDetailNavigation.pushDetail(
      roomId: roomId,
      context: snackContext,
    );
  }

  static void _missingRoomId(BuildContext context) {
    showAppMessage(context, 'Room ID missing. Pull to refresh the dashboard and try again.',);
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
