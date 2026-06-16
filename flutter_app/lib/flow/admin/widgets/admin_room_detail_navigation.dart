import 'package:flutter/material.dart';

import '../../../navigation_keys.dart';
import '../admin_dashboard_models.dart';
import '../admin_room_detail_screen.dart';
import '../admin_room_summary_detail_screen.dart';
import 'admin_dashboard_routes.dart';

/// Opens room list + detail inside the dashboard shell when possible, otherwise
/// on the app root navigator (Manage rooms, Bookings tab, etc.).
abstract final class AdminRoomDetailNavigation {
  static int _rootOverlayDepth = 0;
  static bool _shellOverlayOpen = false;

  static bool get isRoomOverlayOpen =>
      _rootOverlayDepth > 0 || _shellOverlayOpen;

  static void Function(String roomId)? _boundOpenDetail;

  /// Registered by [AdminDashboardRoomOverlayHost] so detail opens even when
  /// [BuildContext] cannot see [AdminDashboardRoutes].
  static void bindShellOpenDetail(void Function(String roomId)? opener) {
    _boundOpenDetail = opener;
  }

  static void notifyShellOverlayOpen(bool open) {
    _shellOverlayOpen = open;
  }

  static Future<T?> _pushRoot<T>(Route<T> route) {
    final nav = appNavigatorKey.currentState;
    if (nav == null) {
      return Future<T?>.value(null);
    }
    _rootOverlayDepth++;
    return nav.push(route).whenComplete(() {
      if (_rootOverlayDepth > 0) _rootOverlayDepth--;
    });
  }

  static Future<void> _pushRootWithFallback<T>(
    Route<T> route, {
    BuildContext? context,
  }) async {
    final nav = appNavigatorKey.currentState;
    if (nav != null) {
      await _pushRoot(route);
      return;
    }
    if (context != null && context.mounted) {
      _rootOverlayDepth++;
      try {
        await Navigator.of(context, rootNavigator: true).push(route);
      } finally {
        if (_rootOverlayDepth > 0) _rootOverlayDepth--;
      }
    }
  }

  static Future<void> pushSummaryList({
    required BuildContext context,
    required String title,
    required List<Map<String, dynamic>> rooms,
    required bool showGuest,
    String? subtitle,
  }) async {
    if (rooms.isEmpty) return;

    final shell = AdminDashboardRoutes.maybeOf(context);
    if (shell != null) {
      shell.openRoomList(
        title: title,
        rooms: rooms,
        showGuest: showGuest,
        subtitle: subtitle,
      );
      return;
    }

    final route = MaterialPageRoute<void>(
      builder: (_) => AdminRoomSummaryDetailScreen(
        title: title,
        rooms: rooms,
        showGuest: showGuest,
        subtitle: subtitle,
      ),
    );
    await _pushRootWithFallback(route, context: context);
  }

  static Future<void> pushDetail({
    required String roomId,
    BuildContext? context,
  }) async {
    final id = AdminDashboardModels.normalizeRoomIdString(roomId);
    if (id.isEmpty) {
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Room ID missing. Pull to refresh the dashboard and try again.',
            ),
          ),
        );
      }
      return;
    }

    if (context != null) {
      final shell = AdminDashboardRoutes.maybeOf(context);
      if (shell != null) {
        shell.openRoomDetail(id);
        return;
      }
    }

    final bound = _boundOpenDetail;
    if (bound != null) {
      bound(id);
      return;
    }

    final route = MaterialPageRoute<void>(
      builder: (_) => AdminRoomDetailScreen(roomId: id),
    );
    await _pushRootWithFallback(route, context: context);
  }

  static Future<void> pushDetailForRoom({
    required BuildContext context,
    required Map<String, dynamic> room,
  }) {
    return pushDetail(
      roomId: AdminDashboardModels.roomIdOf(room),
      context: context,
    );
  }
}
