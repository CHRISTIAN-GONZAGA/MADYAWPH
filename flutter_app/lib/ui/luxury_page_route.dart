import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// Soft fade + lift used for hotel, guest, and portal screens.
class LuxuryPageRoute<T> extends PageRouteBuilder<T> {
  LuxuryPageRoute({
    required WidgetBuilder builder,
    super.settings,
    Duration? duration,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) {
            return ColoredBox(
              color: Theme.of(context).colorScheme.surface,
              child: builder(context),
            );
          },
          transitionDuration: duration ?? UiTokens.dStd,
          reverseTransitionDuration: UiTokens.dFast,
          transitionsBuilder: (context, animation, secondary, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: UiTokens.easeEnter,
              reverseCurve: UiTokens.easeExit,
            );
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.028),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          },
        );

  static Future<T?> push<T extends Object?>(
    BuildContext context,
    Widget page,
  ) {
    return Navigator.of(context).push<T>(
      LuxuryPageRoute<T>(builder: (_) => page),
    );
  }

  static Future<T?> pushAndRemoveUntilFirst<T extends Object?>(
    BuildContext context,
    Widget page,
  ) {
    return Navigator.of(context).pushAndRemoveUntil<T>(
      LuxuryPageRoute<T>(builder: (_) => page),
      (route) => route.isFirst,
    );
  }
}
