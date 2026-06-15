import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Blocks the system back button on a hotel dashboard root until the user confirms.
class DashboardExitGuard extends StatelessWidget {
  const DashboardExitGuard({
    super.key,
    required this.child,
    this.navigatorKey,
    this.onRequestInnerPop,
  });

  final Widget child;

  /// When set, back pops this navigator before asking to exit the app.
  final GlobalKey<NavigatorState>? navigatorKey;

  /// When this returns true, back was handled by an in-dashboard full screen.
  final bool Function()? onRequestInnerPop;

  static Future<bool> confirmExit(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Exit dashboard?'),
        content: const Text(
          'Are you sure you want to exit? You will leave your hotel dashboard.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;

        if (onRequestInnerPop?.call() == true) {
          return;
        }

        final nested = navigatorKey?.currentState;
        if (nested != null && nested.canPop()) {
          nested.pop();
          return;
        }

        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
          return;
        }

        if (await confirmExit(context) && context.mounted) {
          SystemNavigator.pop();
        }
      },
      child: child,
    );
  }
}
