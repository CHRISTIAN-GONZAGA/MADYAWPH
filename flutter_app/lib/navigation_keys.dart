import 'package:flutter/material.dart';

/// Root [MaterialApp] navigator — use for routes outside the admin dashboard.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Nested navigator inside [AdminDashboardScreen] (settings sub-pages, chat, etc.).
final GlobalKey<NavigatorState> adminDashboardNavigatorKey =
    GlobalKey<NavigatorState>();
