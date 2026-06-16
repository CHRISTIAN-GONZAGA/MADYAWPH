import 'package:flutter/material.dart';

/// Hooks for in-dashboard room list/detail overlays (avoids broken Navigator.push).
class AdminDashboardRoutes extends InheritedWidget {
  const AdminDashboardRoutes({
    super.key,
    required this.openRoomList,
    required this.openRoomDetail,
    required this.closeRoomList,
    required this.closeTopOverlay,
    required this.isOverlayOpen,
    required super.child,
  });

  final void Function({
    required String title,
    required List<Map<String, dynamic>> rooms,
    required bool showGuest,
    String? subtitle,
  }) openRoomList;

  final void Function(String roomId) openRoomDetail;

  /// Closes the room grid list (and any open detail).
  final VoidCallback closeRoomList;

  /// Closes the topmost overlay layer (detail first, then list).
  final VoidCallback closeTopOverlay;

  final bool isOverlayOpen;

  static AdminDashboardRoutes? maybeOf(BuildContext context) {
    return context.getInheritedWidgetOfExactType<AdminDashboardRoutes>();
  }

  @override
  bool updateShouldNotify(AdminDashboardRoutes oldWidget) {
    return isOverlayOpen != oldWidget.isOverlayOpen;
  }
}
