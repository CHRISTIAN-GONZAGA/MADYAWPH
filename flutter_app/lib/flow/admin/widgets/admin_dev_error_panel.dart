import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// On-screen developer diagnostics when admin setup screens fail to render.
class AdminDevErrorPanel extends StatelessWidget {
  const AdminDevErrorPanel({
    super.key,
    required this.title,
    required this.message,
    this.details,
    this.hint,
  });

  final String title;
  final String message;
  final String? details;
  final String? hint;

  static String formatError(Object error, [StackTrace? stack]) {
    final buffer = StringBuffer()..writeln(error.toString());
    if (stack != null) {
      buffer.writeln();
      buffer.writeln(stack.toString());
    }
    return buffer.toString().trim();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final body = [
      if (message.isNotEmpty) message,
      if (details != null && details!.trim().isNotEmpty) details!.trim(),
    ].join('\n\n');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Icon(Icons.bug_report_outlined, size: 40, color: scheme.error),
        const SizedBox(height: 12),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: scheme.error,
              ),
        ),
        if (hint != null) ...[
          const SizedBox(height: 8),
          Text(
            hint!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.errorContainer.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.error.withValues(alpha: 0.35)),
          ),
          child: SelectableText(
            body,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  height: 1.35,
                ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: body.isEmpty
              ? null
              : () {
                  Clipboard.setData(ClipboardData(text: body));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Error copied to clipboard.')),
                  );
                },
          icon: const Icon(Icons.copy_outlined),
          label: const Text('Copy error'),
        ),
        if (kDebugMode) ...[
          const SizedBox(height: 8),
          Text(
            'Debug build — share the copied text when reporting this issue.',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ],
    );
  }
}
