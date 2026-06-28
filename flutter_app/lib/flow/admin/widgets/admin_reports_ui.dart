import 'package:flutter/material.dart';

import '../../../ui/app_visual.dart';

/// Premium header for the reports dashboard.
class ReportsHeroHeader extends StatelessWidget {
  const ReportsHeroHeader({
    super.key,
    required this.selectedDateLabel,
    required this.onRefresh,
    this.isRefreshing = false,
  });

  final String selectedDateLabel;
  final VoidCallback onRefresh;
  final bool isRefreshing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visual = AppVisual.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: visual.radiusLg,
        boxShadow: visual.elevatedShadow,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary,
            Color.lerp(scheme.primary, scheme.tertiary, 0.45)!,
          ],
        ),
      ),
      child: ClipRRect(
        borderRadius: visual.radiusLg,
        child: Stack(
          children: [
            Positioned(
              right: -24,
              top: -24,
              child: Icon(
                Icons.insights_rounded,
                size: 120,
                color: scheme.onPrimary.withValues(alpha: 0.12),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Reports & analytics',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: scheme.onPrimary,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          selectedDateLabel,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: scheme.onPrimary.withValues(alpha: 0.9),
                              ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Tap any metric or period to view details and print.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onPrimary.withValues(alpha: 0.78),
                              ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: isRefreshing ? null : onRefresh,
                    icon: isRefreshing
                        ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: scheme.onPrimary,
                            ),
                          )
                        : Icon(Icons.refresh_rounded, color: scheme.onPrimary),
                    tooltip: 'Refresh reports',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Section container with icon header.
class ReportsSection extends StatelessWidget {
  const ReportsSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.icon = Icons.analytics_outlined,
    this.accent,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Color? accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visual = AppVisual.of(context);
    final tone = accent ?? scheme.primary;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: visual.radiusMd,
        boxShadow: visual.cardShadow,
        color: scheme.surfaceContainerLowest,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.12),
                    borderRadius: visual.radiusSm,
                  ),
                  child: Icon(icon, color: tone, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class ReportsPeriodTile extends StatelessWidget {
  const ReportsPeriodTile({
    super.key,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    required this.accent,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visual = AppVisual.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: visual.radiusMd,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: visual.radiusMd,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: 0.14),
                accent.withValues(alpha: 0.06),
              ],
            ),
            border: Border.all(color: accent.withValues(alpha: 0.28)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: accent, size: 20),
                    const Spacer(),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: accent,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ReportsKpiTile extends StatelessWidget {
  const ReportsKpiTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visual = AppVisual.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: visual.radiusMd,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: visual.radiusMd,
            color: scheme.surfaceContainerLowest,
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.45)),
            boxShadow: visual.cardShadow,
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        borderRadius: visual.radiusSm,
                      ),
                      child: Icon(icon, color: accent, size: 20),
                    ),
                    if (onTap != null) ...[
                      const Spacer(),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ReportsNavRow extends StatelessWidget {
  const ReportsNavRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.accent,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visual = AppVisual.of(context);
    final tone = accent ?? scheme.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: visual.radiusMd,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: visual.radiusMd,
              color: scheme.surfaceContainerLowest,
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.45)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: tone.withValues(alpha: 0.12),
                      borderRadius: visual.radiusSm,
                    ),
                    child: Icon(icon, size: 20, color: tone),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
