import 'package:flutter/material.dart';

import '../navigation_keys.dart';
import 'app_notice.dart';

/// Shows a dialog on the app root navigator so it appears above nested dashboards.
Future<T?> showAppOverlayDialog<T>({
  BuildContext? context,
  required WidgetBuilder builder,
  bool barrierDismissible = false,
  Color barrierColor = Colors.black54,
}) {
  final overlayContext = appNavigatorKey.currentContext ?? context;
  if (overlayContext == null) {
    return Future<T?>.value(null);
  }

  return showDialog<T>(
    context: overlayContext,
    useRootNavigator: true,
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor,
    builder: builder,
  );
}

/// @deprecated Prefer [showAppMessage]. Shows a centered notice instead of a bottom snackbar.
void showAppSnackBar(SnackBar snackBar, {BuildContext? context}) {
  final message = messageFromSnackBar(snackBar);
  if (message == null || message.trim().isEmpty) return;
  showAppMessage(context, message.trim());
}

/// Pushes a full-screen route on the admin nested navigator (matches dashboard taps).
Future<T?> pushAdminFullScreen<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  if (!context.mounted) {
    return Future<T?>.value(null);
  }

  final route = MaterialPageRoute<T>(builder: builder);

  final adminNav = adminDashboardNavigatorKey.currentState;
  if (adminNav != null) {
    return adminNav.push<T>(route);
  }

  return Navigator.of(context).push<T>(route);
}

/// Pushes a full-screen route on the app root navigator (fallback).
Future<T?> showAppOverlayPage<T>({
  BuildContext? context,
  required WidgetBuilder builder,
}) {
  if (context != null && context.mounted) {
    return pushAdminFullScreen<T>(context, builder: builder);
  }

  final nav = appNavigatorKey.currentState;
  if (nav != null) {
    return nav.push<T>(MaterialPageRoute<T>(builder: builder));
  }

  return Future<T?>.value(null);
}
