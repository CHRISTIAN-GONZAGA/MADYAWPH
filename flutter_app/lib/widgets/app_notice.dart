import 'package:flutter/material.dart';

import '../navigation_keys.dart';
import '../ui/app_visual.dart';

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

  await showDialog<void>(
    context: ctx,
    useRootNavigator: true,
    barrierDismissible: actionLabel == null,
    builder: (dialogContext) {
      final scheme = Theme.of(dialogContext).colorScheme;
      final visual = Theme.of(dialogContext).extension<AppVisual>() ??
          AppVisual.light(scheme);
      final tone = isError ? scheme.error : scheme.primary;
      final surface = isError ? scheme.errorContainer : scheme.primaryContainer;
      final onSurface =
          isError ? scheme.onErrorContainer : scheme.onPrimaryContainer;

      return Dialog(
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surfaceTint,
        shape: RoundedRectangleBorder(borderRadius: visual.radiusLg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: surface.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Icon(
                      isError
                          ? Icons.error_outline_rounded
                          : Icons.check_circle_outline_rounded,
                      color: tone,
                      size: 36,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (title != null && title.isNotEmpty) ...[
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style:
                        Theme.of(dialogContext).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurface,
                        height: 1.4,
                      ),
                ),
                const SizedBox(height: 22),
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
                        style: FilledButton.styleFrom(
                          backgroundColor: tone,
                          foregroundColor: onSurface,
                        ),
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: Text(confirmLabel),
                      ),
                    ),
                  ],
                ),
              ],
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
