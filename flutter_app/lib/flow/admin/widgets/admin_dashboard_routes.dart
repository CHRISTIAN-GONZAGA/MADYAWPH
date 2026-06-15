import 'package:flutter/material.dart';

/// In-dashboard full-screen room details (walk-in uses a root [showDialog] instead).
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

  @override
  bool updateShouldNotify(AdminDashboardRoutes oldWidget) {
    return isFullScreenOpen != oldWidget.isFullScreenOpen;
  }
}
