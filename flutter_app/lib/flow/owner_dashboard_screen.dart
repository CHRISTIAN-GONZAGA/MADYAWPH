import 'package:flutter/material.dart';

import '../auth_storage.dart';
import '../widgets/app_scaffold.dart';
import 'admin_reports.dart';
import 'dashboards.dart';
import 'flow_state.dart';
import 'public_hotel_search_screen.dart';

/// Hotel owner workspace: financial summaries and activity audit trail.
class OwnerDashboardScreen extends StatefulWidget {
  const OwnerDashboardScreen({super.key});

  @override
  State<OwnerDashboardScreen> createState() => _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends State<OwnerDashboardScreen> {
  int _tab = 0;

  Future<void> _signOut() async {
    await AuthStorage.clearPortalAuth();
    hotelSessionNotifier.value = null;
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const PublicHotelSearchScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppScaffold(
      appBar: AppBar(
        title: const Text('Hotel owner'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: const [
          AdminReportsScreen(),
          AdminActivityLogsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights, color: scheme.primary),
            label: 'Financials',
          ),
          NavigationDestination(
            icon: const Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history, color: scheme.primary),
            label: 'Activity',
          ),
        ],
      ),
    );
  }
}
