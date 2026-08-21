import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../navigation_keys.dart';
import '../ui/app_visual.dart';
import '../ui/design_tokens.dart';

/// Resolves a mounted context for dialogs (nested admin navigator safe).
BuildContext? resolveNoticeContext(BuildContext? context) {
  if (context != null && context.mounted) return context;
  final admin = adminDashboardNavigatorKey.currentContext;
  if (admin != null && admin.mounted) return admin;
  final root = appNavigatorKey.currentContext;
  if (root != null && root.mounted) return root;
  return null;
}

/// Centered in-app notice (replaces bottom snackbars).
Future<void> showAppMessage(
  BuildContext? context,
  String message, {
  String? title,
  bool isError = false,
  String confirmLabel = 'OK',
  String? actionLabel,
  VoidCallback? onAction,
}) async {
  final ctx = resolveNoticeContext(context);
  if (ctx == null) return;

  if (isError) {
    HapticFeedback.mediumImpact();
  } else {
    HapticFeedback.lightImpact();
  }

  await showGeneralDialog<void>(
    context: ctx,
    useRootNavigator: true,
    barrierDismissible: actionLabel == null,
    barrierLabel: 'Dismiss',
    barrierColor: Theme.of(ctx).colorScheme.scrim.withValues(alpha: 0.45),
    transitionDuration: UiTokens.dStd,
    pageBuilder: (dialogContext, animation, secondary) {
      final scheme = Theme.of(dialogContext).colorScheme;
      final visual = Theme.of(dialogContext).extension<AppVisual>() ??
          AppVisual.light(scheme);
      final tone = isError ? scheme.error : scheme.primary;
      final surface =
          isError ? scheme.errorContainer : scheme.primaryContainer;

      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: UiTokens.easeEnter),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(
            CurvedAnimation(parent: animation, curve: UiTokens.easeEnter),
          ),
          child: Align(
            alignment: Alignment.center,
            child: Material(
              color: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Dialog(
                  insetPadding: const EdgeInsets.symmetric(horizontal: 28),
                  backgroundColor: scheme.surface,
                  surfaceTintColor: Colors.transparent,
                  shape: RoundedRectangleBorder(borderRadius: visual.radiusLg),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(26, 30, 26, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: surface.withValues(alpha: 0.55),
                            shape: BoxShape.circle,
                            boxShadow: visual.cardShadow,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Icon(
                              isError
                                  ? Icons.error_outline_rounded
                                  : Icons.check_circle_outline_rounded,
                              color: tone,
                              size: 34,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        if (title != null && title.isNotEmpty) ...[
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            style: Theme.of(dialogContext)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                        ],
                        Text(
                          message,
                          textAlign: TextAlign.center,
                          style: Theme.of(dialogContext)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: scheme.onSurface,
                                height: 1.45,
                              ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            if (actionLabel != null && onAction != null) ...[
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () {
                                    Navigator.of(dialogContext).pop();
                                    onAction();
                                  },
                                  child: Text(actionLabel),
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                            Expanded(
                              child: FilledButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(),
                                child: Text(confirmLabel),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Reads plain text from simple snackbars during migration.
String? messageFromSnackBar(SnackBar snackBar) {
  final content = snackBar.content;
  if (content is Text) {
    if (content.data != null && content.data!.isNotEmpty) {
      return content.data;
    }
    return content.textSpan?.toPlainText();
  }
  return null;
}
