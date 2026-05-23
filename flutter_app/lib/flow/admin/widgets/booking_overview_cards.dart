import 'package:flutter/material.dart';

class BookingOverviewCards extends StatelessWidget {
  const BookingOverviewCards({
    super.key,
    required this.localTotal,
    required this.onlineTotal,
    required this.onLocalTap,
    required this.onOnlineTap,
  });

  final int localTotal;
  final int onlineTotal;
  final VoidCallback onLocalTap;
  final VoidCallback onOnlineTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Booking overview',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _BookingStatCard(
                label: 'Local bookings',
                subtitle: 'In-app / customer portal',
                count: localTotal,
                icon: Icons.smartphone_outlined,
                color: scheme.primary,
                onTap: onLocalTap,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _BookingStatCard(
                label: 'Online bookings',
                subtitle: 'Website channel (future)',
                count: onlineTotal,
                icon: Icons.language_outlined,
                color: scheme.tertiary,
                onTap: onOnlineTap,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _BookingStatCard extends StatelessWidget {
  const _BookingStatCard({
    required this.label,
    required this.subtitle,
    required this.count,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final int count;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 22),
                  const Spacer(),
                  Icon(Icons.chevron_right, color: color),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '$count',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
              ),
              Text(
                label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
