import 'package:flutter/material.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';

import '../../../navigation_keys.dart';
import '../../../widgets/app_overlay.dart';
import '../admin_dashboard_models.dart';
import '../admin_room_detail_screen.dart';
import '../admin_room_summary_detail_screen.dart';
import 'admin_hotel_totals_room_panel.dart';

/// Room list + details for admin dashboard.
abstract final class AdminRoomDetailNavigation {
  static int _openSheetCount = 0;
  static bool _panelOpen = false;

  static bool get isRoomOverlayOpen => _openSheetCount > 0 || _panelOpen;

  static void notifyPanelOpen(bool open) => _panelOpen = open;

  static BuildContext? get _rootOverlayContext =>
      appNavigatorKey.currentContext;

  static Future<T?> _trackSheet<T>(Future<T?> future) {
    _openSheetCount++;
    return future.whenComplete(() {
      if (_openSheetCount > 0) _openSheetCount--;
    });
  }

  static BuildContext? _resolveContext(BuildContext? context) {
    if (context != null && context.mounted) return context;
    final root = _rootOverlayContext;
    if (root != null && root.mounted) return root;
    return null;
  }

  /// Room detail route (fallback when hotel-totals panel is unavailable).
  static Future<void> showHotelTotalsRoomDetailSheet({
    required BuildContext context,
    required String roomId,
    Map<String, dynamic>? initialRoomSnapshot,
  }) async {
    final id = AdminDashboardModels.normalizeRoomIdString(roomId);
    if (id.isEmpty) return;

    final navContext = _resolveContext(context);
    if (navContext == null) return;

    await _trackSheet(
      pushAdminFullScreen<void>(
        navContext,
        builder: (ctx) => AdminRoomDetailScreen(
          key: ValueKey('hotel-totals-detail-$id'),
          roomId: id,
          embedded: true,
          initialRoomSnapshot: initialRoomSnapshot,
          onClose: () => Navigator.of(ctx).pop(),
        ),
      ),
    );
  }

  static Future<void> showRoomDetailSheet({
    required String roomId,
    BuildContext? context,
    Map<String, dynamic>? initialRoomSnapshot,
  }) async {
    final id = AdminDashboardModels.normalizeRoomIdString(roomId);
    final ctx = _resolveContext(context);
    if (id.isEmpty) {
      if (ctx != null) {
        showAppMessage(ctx, 'Room ID missing. Pull to refresh the dashboard and try again.',);
      }
      return;
    }
    if (ctx == null) return;

    await showHotelTotalsRoomDetailSheet(
      context: ctx,
      roomId: id,
      initialRoomSnapshot: initialRoomSnapshot,
    );
  }

  static Future<void> showRoomListSheet({
    required BuildContext context,
    required String title,
    required List<Map<String, dynamic>> rooms,
    required bool showGuest,
    String? subtitle,
  }) async {
    if (rooms.isEmpty) return;
    final ctx = _resolveContext(context);
    if (ctx == null) return;

    await _trackSheet(
      showModalBottomSheet<void>(
        context: ctx,
        useRootNavigator: false,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        barrierColor: Colors.black54,
        builder: (sheetContext) {
          final height = MediaQuery.sizeOf(sheetContext).height;
          return SizedBox(
            height: height * 0.88,
            child: AdminRoomSummaryDetailScreen(
              title: title,
              rooms: rooms,
              showGuest: showGuest,
              subtitle: subtitle,
              onClose: () => Navigator.of(sheetContext).pop(),
            ),
          );
        },
      ),
    );
  }

  static Future<void> pushSummaryList({
    required BuildContext context,
    required String title,
    required List<Map<String, dynamic>> rooms,
    required bool showGuest,
    String? subtitle,
  }) {
    openHotelTotalsRoomList(
      context,
      title: title,
      rooms: rooms,
      showGuest: showGuest,
      subtitle: subtitle,
    );
    return Future<void>.value();
  }

  static Future<void> pushDetail({
    required String roomId,
    BuildContext? context,
  }) {
    return showRoomDetailSheet(roomId: roomId, context: context);
  }

  static Future<void> pushDetailForRoom({
    required BuildContext context,
    required Map<String, dynamic> room,
  }) {
    openHotelTotalsRoomDetail(context, room: room);
    return Future<void>.value();
  }
}
