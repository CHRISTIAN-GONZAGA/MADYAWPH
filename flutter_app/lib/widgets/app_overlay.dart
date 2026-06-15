import 'package:flutter/material.dart';

import '../navigation_keys.dart';

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

void showAppSnackBar(SnackBar snackBar) {
  final overlayContext = appNavigatorKey.currentContext;
  if (overlayContext == null) return;
  ScaffoldMessenger.of(overlayContext).showSnackBar(snackBar);
}

/// Pushes a full-screen route on the app root navigator (reliable on nested dashboards).
Future<T?> showAppOverlayPage<T>({
  BuildContext? context,
  required WidgetBuilder builder,
}) {
  final nav = appNavigatorKey.currentState;
  if (nav != null) {
    return nav.push<T>(
      MaterialPageRoute<T>(
        fullscreenDialog: true,
        builder: builder,
      ),
    );
  }

  if (context != null && context.mounted) {
    return Navigator.of(context, rootNavigator: true).push<T>(
      MaterialPageRoute<T>(
        fullscreenDialog: true,
        builder: builder,
      ),
    );
  }

  return Future<T?>.value(null);
}
