import 'package:flutter/material.dart';

import '../../../navigation_keys.dart';
import '../admin_dashboard_models.dart';
import '../admin_room_detail_screen.dart';
import '../admin_room_summary_detail_screen.dart';
import 'admin_hotel_totals_room_panel.dart';

/// Room list + details: Hotel totals uses in-dashboard slide-up panel; other
/// entry points use modal bottom sheets.
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

  static Future<void> showRoomDetailSheet({
    required String roomId,
    BuildContext? context,
  }) async {
    final id = AdminDashboardModels.normalizeRoomIdString(roomId);
    final ctx = _resolveContext(context);
    if (id.isEmpty) {
      if (ctx != null) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(
            content: Text(
              'Room ID missing. Pull to refresh the dashboard and try again.',
            ),
          ),
        );
      }
      return;
    }
    if (ctx == null) return;

    final panel = HotelTotalsRoomPanelScope.maybeOf(ctx);
    if (panel != null) {
      panel.openRoomDetail(id);
      return;
    }

    await _trackSheet(
      showModalBottomSheet<void>(
        context: ctx,
        useRootNavigator: true,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: const Color(0xFFF5F3EF),
        barrierColor: Colors.black54,
        builder: (sheetContext) {
          final height = MediaQuery.sizeOf(sheetContext).height;
          return SizedBox(
            height: height * 0.94,
            child: AdminRoomDetailScreen(
              roomId: id,
              embedded: true,
              onClose: () => Navigator.of(sheetContext).pop(),
            ),
          );
        },
      ),
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
        useRootNavigator: true,
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
