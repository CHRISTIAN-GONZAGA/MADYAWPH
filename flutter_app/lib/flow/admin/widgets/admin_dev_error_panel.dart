import 'package:flutter/material.dart';

/// Friendly error state when an admin screen cannot load.
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Icon(Icons.error_outline, size: 40, color: scheme.error),
        const SizedBox(height: 12),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: scheme.error,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        if (hint != null && hint!.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            hint!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ],
    );
  }
}
