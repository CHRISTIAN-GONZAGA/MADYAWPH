import 'package:flutter/material.dart';

/// Opaque full-screen route for admin flows (room detail, walk-in booking).
class AdminPushedRoute<T> extends MaterialPageRoute<T> {
  AdminPushedRoute({
    required BuildContext hostContext,
    required Widget child,
  }) : super(
          fullscreenDialog: true,
          builder: (routeContext) {
            final theme = Theme.of(hostContext);
            return Theme(
              data: theme,
              child: Material(
                color: theme.colorScheme.surface,
                child: child,
              ),
            );
          },
        );
}
