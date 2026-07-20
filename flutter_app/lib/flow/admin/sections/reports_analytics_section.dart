import 'package:flutter/material.dart';

import '../widgets/hotel_reports_bento_section.dart';

/// Navbar → Reports & analytics hub.
class ReportsAnalyticsSection extends StatelessWidget {
  const ReportsAnalyticsSection({
    super.key,
    this.rooms = const [],
  });

  final List<Map<String, dynamic>> rooms;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

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
          'Tap a tile to open that report',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 16),
        HotelReportsBentoSection(rooms: rooms, showHeader: false),
      ],
    );
  }
}
