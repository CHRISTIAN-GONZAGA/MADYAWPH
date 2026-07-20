import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../dio_client.dart';
import '../../../utils/money_format.dart';
import '../widgets/amenities_report_screen.dart';
import '../widgets/front_desk_sales_report_screen.dart';
import '../widgets/hotel_period_report_screen.dart';
import '../widgets/hotel_reports_bento_section.dart';
import '../widgets/reseller_commissions_report_screen.dart';
import '../widgets/room_insights_report_screen.dart';

/// Navbar → Reports & analytics hub.
class ReportsAnalyticsSection extends StatefulWidget {
  const ReportsAnalyticsSection({
    super.key,
    this.rooms = const [],
  });

  final List<Map<String, dynamic>> rooms;

  @override
  State<ReportsAnalyticsSection> createState() =>
      _ReportsAnalyticsSectionState();
}

class _ReportsAnalyticsSectionState extends State<ReportsAnalyticsSection> {
  bool _loadingInsights = true;
  String? _insightsError;
  Map<String, dynamic>? _insights;

  @override
  void initState() {
    super.initState();
    _loadInsights();
  }

  Future<void> _loadInsights() async {
    setState(() {
      _loadingInsights = true;
      _insightsError = null;
    });
    try {
      final res = await portalDio().get<Map<String, dynamic>>(
        '/reports/room-insights',
      );
      if (!mounted) return;
      setState(() {
        _insights = res.data;
        _loadingInsights = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _insightsError = dioErrorMessage(e);
        _loadingInsights = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _insightsError = '$e';
        _loadingInsights = false;
      });
    }
  }

  List<Map<String, dynamic>> _list(String key) {
    final raw = _insights?[key];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  String _roomLabel(Map<String, dynamic> row) {
    final room = (row['room_number'] ?? '—').toString();
    final count = row['bookings_count'] ?? row['bookings'];
    final revenue = row['revenue'];
    final parts = <String>['Room $room'];
    if (count != null) parts.add('$count booking(s)');
    if (revenue != null) parts.add(formatPeso(parseJsonDouble(revenue)));
    return parts.join(' · ');
  }

  String _categoryLabel(Map<String, dynamic> row) {
    final name = (row['label'] ?? row['category'] ?? '—').toString();
    final count = row['bookings'];
    final revenue = row['revenue'];
    final parts = <String>[name];
    if (count != null) parts.add('$count booking(s)');
    if (revenue != null) parts.add(formatPeso(parseJsonDouble(revenue)));
    return parts.join(' · ');
  }

  void _openPeriod(String label, DateTime start, DateTime end) {
    openHotelPeriodReport(
      context: context,
      timeIn: start,
      timeOut: end,
      title: '$label revenue',
      subtitle: 'Hotel-wide report',
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateUtils.dateOnly(DateTime.now());
    final endOf = (DateTime d) =>
        DateTime(d.year, d.month, d.day, 23, 59, 59, 999);
    final weekStart = now.subtract(Duration(days: now.weekday - 1));

    final mostBooked = _list('most_booked');
    final leastBooked = _list('least_booked');
    final mostCategories = _list('by_room_type');
    final mostRevenue = _list('most_profit');

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
          'Sales, FO performance, room insights, and period revenue',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 16),
        HotelReportsBentoSection(rooms: widget.rooms),
        const SizedBox(height: 20),
        Text(
          'Room & category analysis',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 8),
        if (_loadingInsights) const LinearProgressIndicator(minHeight: 2),
        if (_insightsError != null)
          Card(
            child: ListTile(
              title: Text(_insightsError!),
              trailing: TextButton(
                onPressed: _loadInsights,
                child: const Text('Retry'),
              ),
            ),
          )
        else ...[
          _InsightCard(
            title: 'Most booked rooms',
            icon: Icons.trending_up_rounded,
            color: Colors.teal.shade700,
            lines: mostBooked.take(3).map(_roomLabel).toList(),
            empty: 'No booking data yet',
            onOpen: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const RoomInsightsReportScreen(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _InsightCard(
            title: 'Least booked rooms',
            icon: Icons.trending_down_rounded,
            color: Colors.orange.shade800,
            lines: leastBooked.take(3).map(_roomLabel).toList(),
            empty: 'No booking data yet',
            onOpen: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const RoomInsightsReportScreen(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _InsightCard(
            title: 'Most booked categories',
            icon: Icons.category_outlined,
            color: Colors.indigo,
            lines: mostCategories.take(3).map(_categoryLabel).toList(),
            empty: 'No category data yet',
            onOpen: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const RoomInsightsReportScreen(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _InsightCard(
            title: 'Most revenue generated',
            icon: Icons.payments_outlined,
            color: Colors.green.shade700,
            lines: mostRevenue.take(3).map(_roomLabel).toList(),
            empty: 'No revenue data yet',
            onOpen: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const RoomInsightsReportScreen(),
              ),
            ),
          ),
        ],
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
              onPressed: () => _openPeriod('Daily', now, endOf(now)),
            ),
            ActionChip(
              label: const Text('Weekly revenue'),
              onPressed: () => _openPeriod(
                'Weekly',
                weekStart,
                endOf(weekStart.add(const Duration(days: 6))),
              ),
            ),
            ActionChip(
              label: const Text('Monthly revenue'),
              onPressed: () => _openPeriod(
                'Monthly',
                DateTime(now.year, now.month, 1),
                endOf(DateTime(now.year, now.month + 1, 0)),
              ),
            ),
            ActionChip(
              label: const Text('Annual revenue'),
              onPressed: () => _openPeriod(
                'Annual',
                DateTime(now.year, 1, 1),
                endOf(DateTime(now.year, 12, 31)),
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

class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.lines,
    required this.empty,
    required this.onOpen,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<String> lines;
  final String empty;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                TextButton(onPressed: onOpen, child: const Text('Open')),
              ],
            ),
            if (lines.isEmpty)
              Text(empty, style: Theme.of(context).textTheme.bodySmall)
            else
              ...lines.map(
                (line) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    line,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
