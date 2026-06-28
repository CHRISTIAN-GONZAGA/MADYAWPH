import 'package:flutter/material.dart';

class BookingOverviewCards extends StatelessWidget {
  const BookingOverviewCards({
    super.key,
    required this.localTotal,
    required this.onlineTotal,
    required this.recentBookings24h,
    required this.pendingReservations,
    required this.onLocalTap,
    required this.onOnlineTap,
    required this.onAlertTap,
  });

  final int localTotal;
  final int onlineTotal;
  final int recentBookings24h;
  final int pendingReservations;
  final VoidCallback onLocalTap;
  final VoidCallback onOnlineTap;
  final VoidCallback onAlertTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final alertCount = pendingReservations;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (alertCount > 0) ...[
          Material(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onAlertTap,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.orange.shade100,
                      child: Icon(
                        Icons.notifications_active_outlined,
                        color: Colors.orange.shade900,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            alertCount == 1
                                ? '1 reservation needs attention'
                                : '$alertCount reservations need attention',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            _alertSubtitle(pendingReservations),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: scheme.primary),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
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
                subtitle: 'Walk-ins awaiting check-in',
                count: localTotal,
                icon: Icons.storefront_outlined,
                color: scheme.primary,
                onTap: onLocalTap,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _BookingStatCard(
                label: 'Online bookings',
                subtitle: 'Pending customer approval',
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

  static String _alertSubtitle(int pending) {
    if (pending > 0) {
      return pending == 1
          ? '1 reservation awaiting approval'
          : '$pending reservations awaiting approval';
    }
    return 'Review in bookings tab';
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
