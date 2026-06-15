import 'package:flutter/material.dart';

import '../widgets/app_scaffold.dart';
import 'admin_reports.dart';
import 'dashboards.dart';
import 'portal_sign_out.dart';

/// Hotel owner workspace: financial summaries and activity audit trail.
class OwnerDashboardScreen extends StatefulWidget {
  const OwnerDashboardScreen({super.key});

  @override
  State<OwnerDashboardScreen> createState() => _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends State<OwnerDashboardScreen> {
  int _tab = 0;

  Future<void> _signOut() async {
    await confirmAndSignOutPortalToRoleSelection(context);
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
          AdminReportsScreen(embedded: true),
          AdminActivityLogsScreen(embedded: true),
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
