import 'package:flutter/material.dart';

/// In-dashboard full-screen room details from the Summary tab.
class AdminDashboardRoutes extends InheritedWidget {
  const AdminDashboardRoutes({
    super.key,
    required this.openDetail,
    required this.closeFullScreen,
    required this.isFullScreenOpen,
    required super.child,
  });

  final void Function(String roomId) openDetail;

  final VoidCallback closeFullScreen;

  final bool isFullScreenOpen;

  static AdminDashboardRoutes? maybeOf(BuildContext context) {
    return context.getInheritedWidgetOfExactType<AdminDashboardRoutes>();
  }

  /// Opens room details inside the dashboard shell (Summary occupied/vacant lists).
  static bool tryOpenDetail(BuildContext context, String roomId) {
    final routes = maybeOf(context);
    if (routes == null || roomId.isEmpty) return false;
    routes.openDetail(roomId);
    return true;
  }

  @override
  bool updateShouldNotify(AdminDashboardRoutes oldWidget) {
    return isFullScreenOpen != oldWidget.isFullScreenOpen;
  }
}
