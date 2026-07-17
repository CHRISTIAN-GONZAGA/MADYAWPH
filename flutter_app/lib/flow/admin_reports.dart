import 'package:flutter/material.dart';

import '../widgets/app_scaffold.dart';
import 'admin/widgets/amenities_report_screen.dart';
import 'admin/widgets/front_desk_sales_report_screen.dart';
import 'admin/widgets/hotel_period_report_screen.dart';
import 'admin/widgets/reseller_commissions_report_screen.dart';
import 'admin/widgets/room_insights_report_screen.dart';

/// Grid hub for reports & analytics — each card opens a detailed view.
class AdminReportsScreen extends StatelessWidget {
  const AdminReportsScreen({
    super.key,
    this.embedded = false,
    this.isFrontDesk = false,
  });

  final bool embedded;
  final bool isFrontDesk;

  String _fmtDay(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _openFinancePeriod(
    BuildContext context, {
    required String buttonLabel,
    required String periodKey,
  }) {
    final anchor = DateUtils.dateOnly(DateTime.now());
    late final DateTime start;
    late final DateTime end;
    switch (periodKey) {
      case 'weekly':
        start = anchor.subtract(Duration(days: anchor.weekday - 1));
        end = start.add(const Duration(days: 6));
        break;
      case 'monthly':
        start = DateTime(anchor.year, anchor.month, 1);
        end = DateTime(anchor.year, anchor.month + 1, 0);
        break;
      case 'annual':
        start = DateTime(anchor.year, 1, 1);
        end = DateTime(anchor.year, 12, 31);
        break;
      default:
        start = anchor;
        end = anchor;
    }
    openHotelPeriodReport(
      context: context,
      timeIn: start,
      timeOut: end,
      title: '$buttonLabel revenue',
      subtitle: 'Hotel-wide report',
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = DateUtils.dateOnly(DateTime.now());
    final tiles = <_HubTile>[
      _HubTile(
        title: 'Front desk sales',
        subtitle: 'Per-account daily → annual',
        icon: Icons.point_of_sale_outlined,
        color: scheme.primary,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const FrontDeskSalesReportScreen()),
        ),
      ),
      _HubTile(
        title: 'Room insights',
        subtitle: 'Most/least booked, profit, maintenance',
        icon: Icons.hotel_class_outlined,
        color: Colors.indigo,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const RoomInsightsReportScreen()),
        ),
      ),
      _HubTile(
        title: 'Amenities reports',
        subtitle: 'Product sales & profit',
        icon: Icons.room_service_outlined,
        color: Colors.teal,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AmenitiesReportScreen()),
        ),
      ),
      if (!isFrontDesk)
        _HubTile(
          title: 'Reseller commissions',
          subtitle: 'Payouts & calendar',
          icon: Icons.handshake_outlined,
          color: Colors.deepOrange,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const ResellerCommissionsReportScreen(),
            ),
          ),
        ),
      _HubTile(
        title: 'Daily revenue',
        subtitle: 'Hotel-wide today',
        icon: Icons.today_outlined,
        color: Colors.blue,
        onTap: () => _openFinancePeriod(
          context,
          buttonLabel: 'Daily',
          periodKey: 'daily',
        ),
      ),
      _HubTile(
        title: 'Weekly revenue',
        subtitle: 'This week',
        icon: Icons.date_range_outlined,
        color: Colors.cyan,
        onTap: () => _openFinancePeriod(
          context,
          buttonLabel: 'Weekly',
          periodKey: 'weekly',
        ),
      ),
      _HubTile(
        title: 'Monthly revenue',
        subtitle: 'This month',
        icon: Icons.calendar_month_outlined,
        color: Colors.purple,
        onTap: () => _openFinancePeriod(
          context,
          buttonLabel: 'Monthly',
          periodKey: 'monthly',
        ),
      ),
      _HubTile(
        title: 'Annual revenue',
        subtitle: 'This year',
        icon: Icons.insights_outlined,
        color: Colors.brown,
        onTap: () => _openFinancePeriod(
          context,
          buttonLabel: 'Annual',
          periodKey: 'annual',
        ),
      ),
    ];

    final body = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, embedded ? 8 : 16, 16, 48),
      children: [
        Text(
          'Reports & analytics',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'Tap a card for detailed figures · ${_fmtDay(today)}',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: tiles.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.05,
          ),
          itemBuilder: (context, i) => tiles[i],
        ),
      ],
    );

    if (embedded) return body;
    return AppScaffold(
      appBar: AppBar(title: const Text('Reports & analytics')),
      body: body,
    );
  }
}

class _HubTile extends StatelessWidget {
  const _HubTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.15),
                  child: Icon(icon, color: color),
                ),
                const Spacer(),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
