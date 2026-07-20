import 'package:flutter/material.dart';

import '../widgets/amenities_report_screen.dart';
import '../widgets/front_desk_sales_report_screen.dart';
import '../widgets/hotel_period_report_screen.dart';
import '../widgets/hotel_reports_bento_section.dart';
import '../widgets/reseller_commissions_report_screen.dart';

/// Navbar → Reports & analytics hub.
class ReportsAnalyticsSection extends StatelessWidget {
  const ReportsAnalyticsSection({
    super.key,
    this.rooms = const [],
  });

  final List<Map<String, dynamic>> rooms;

  void _openPeriod(
    BuildContext context,
    String label,
    DateTime start,
    DateTime end,
  ) {
    openHotelPeriodReport(
      context: context,
      timeIn: start,
      timeOut: end,
      title: '$label revenue',
      subtitle: 'Hotel-wide report',
    );
  }

  static DateTime _endOf(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateUtils.dateOnly(DateTime.now());
    final weekStart = now.subtract(Duration(days: now.weekday - 1));

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        Text(
          'Reports & analytics',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'Tap a tile to open that report only',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 16),
        HotelReportsBentoSection(rooms: rooms, showHeader: false),
        const SizedBox(height: 20),
        Text(
          'Front desk sales',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: Icon(Icons.point_of_sale_outlined, color: scheme.primary),
            title: const Text('Front desk sales report'),
            subtitle: const Text('Daily · weekly · monthly · annual per FO'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const FrontDeskSalesReportScreen(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(
              label: const Text('Daily revenue'),
              onPressed: () => _openPeriod(context, 'Daily', now, _endOf(now)),
            ),
            ActionChip(
              label: const Text('Weekly revenue'),
              onPressed: () => _openPeriod(
                context,
                'Weekly',
                weekStart,
                _endOf(weekStart.add(const Duration(days: 6))),
              ),
            ),
            ActionChip(
              label: const Text('Monthly revenue'),
              onPressed: () => _openPeriod(
                context,
                'Monthly',
                DateTime(now.year, now.month, 1),
                _endOf(DateTime(now.year, now.month + 1, 0)),
              ),
            ),
            ActionChip(
              label: const Text('Annual revenue'),
              onPressed: () => _openPeriod(
                context,
                'Annual',
                DateTime(now.year, 1, 1),
                _endOf(DateTime(now.year, 12, 31)),
              ),
            ),
            ActionChip(
              label: const Text('Amenities'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AmenitiesReportScreen(),
                ),
              ),
            ),
            ActionChip(
              label: const Text('Reseller commissions'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ResellerCommissionsReportScreen(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
