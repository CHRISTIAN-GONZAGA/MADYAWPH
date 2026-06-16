import 'package:flutter/material.dart';

/// Optional hooks for nested dashboard back handling.
class AdminDashboardRoutes extends InheritedWidget {
  const AdminDashboardRoutes({
    super.key,
    required this.closeFullScreen,
    required this.isFullScreenOpen,
    required super.child,
  });

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
