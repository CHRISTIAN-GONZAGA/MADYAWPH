import 'dart:async';

import 'package:flutter/material.dart';

/// In-dashboard full-screen routes (walk-in booking, room details) without
/// [Navigator.push], which is unreliable over [IndexedStack] on Android.
class AdminDashboardRoutes extends InheritedWidget {
  const AdminDashboardRoutes({
    super.key,
    required this.openWalkIn,
    required this.openDetail,
    required this.closeFullScreen,
    required this.isFullScreenOpen,
    required super.child,
  });

  final void Function(
    Map<String, dynamic> room,
    Future<void> Function() onSuccess,
    Completer<bool> completer,
  ) openWalkIn;

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
