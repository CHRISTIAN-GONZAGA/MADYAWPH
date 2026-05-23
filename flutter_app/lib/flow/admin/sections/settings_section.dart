import 'package:flutter/material.dart';

import '../../admin_bookings.dart';
import '../../admin_categories.dart';
import '../../admin_chat.dart';
import '../../admin_reports.dart';
import '../../admin_rooms.dart';
import '../../admin_staff.dart';
import '../../guest_list_history.dart';

class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.creditBalance,
    required this.onRecharge,
    required this.onSurgePricing,
    required this.onThemeReset,
    required this.onProcessReminders,
    required this.onOpenActivityLogs,
    required this.onOpenAccountSettings,
    required this.onRefreshAfterNav,
  });

  final String creditBalance;
  final VoidCallback onRecharge;
  final VoidCallback onSurgePricing;
  final Future<void> Function() onThemeReset;
  final Future<void> Function() onProcessReminders;
  final VoidCallback onOpenActivityLogs;
  final VoidCallback onOpenAccountSettings;
  final Future<void> Function() onRefreshAfterNav;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        Text('Settings', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        _SettingsGroup(
          title: 'Operations',
          tiles: [
            _SettingsTile(
              icon: Icons.event_note_outlined,
              title: 'Reservation requests',
              subtitle: 'Full approve/reject workflow',
              onTap: () async {
                await Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminBookingsScreen(),
                  ),
                );
                await onRefreshAfterNav();
              },
            ),
            _SettingsTile(
              icon: Icons.forum_outlined,
              title: 'Chatroom',
              subtitle: 'Guest and staff inboxes',
              onTap: () async {
                await Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminChatHubScreen(),
                  ),
                );
                await onRefreshAfterNav();
              },
            ),
            _SettingsTile(
              icon: Icons.history_edu_outlined,
              title: 'Guest history',
              subtitle: 'Completed stays archive',
              onTap: () async {
                await Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const GuestListHistoryScreen(),
                  ),
                );
              },
            ),
          ],
        ),
        _SettingsGroup(
          title: 'Room settings',
          tiles: [
            _SettingsTile(
              icon: Icons.hotel_outlined,
              title: 'Rooms & status',
              subtitle: 'Add, edit, passwords, fees, checkout',
              onTap: () async {
                await Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminRoomsScreen(),
                  ),
                );
                await onRefreshAfterNav();
              },
            ),
            _SettingsTile(
              icon: Icons.category_outlined,
              title: 'Room categories',
              subtitle: 'Categories, pricing, gallery images',
              onTap: () async {
                await Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminCategoriesScreen(),
                  ),
                );
                await onRefreshAfterNav();
              },
            ),
            _SettingsTile(
              icon: Icons.trending_up_outlined,
              title: 'Dynamic / surge pricing',
              subtitle: 'Weekend, peak, emergency surge toggles',
              onTap: onSurgePricing,
            ),
          ],
        ),
        _SettingsGroup(
          title: 'Staff & tasks',
          tiles: [
            _SettingsTile(
              icon: Icons.groups_outlined,
              title: 'Staff management',
              subtitle: 'Add, edit, roles, suspend',
              onTap: () async {
                await Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminStaffScreen(),
                  ),
                );
                await onRefreshAfterNav();
              },
            ),
          ],
        ),
        _SettingsGroup(
          title: 'System & reports',
          tiles: [
            _SettingsTile(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Credits: $creditBalance',
              subtitle: 'Recharge via GCash or PayMaya',
              onTap: onRecharge,
            ),
            _SettingsTile(
              icon: Icons.insights_outlined,
              title: 'Analytics & reports',
              subtitle: 'Daily, weekly, monthly, annual revenue',
              onTap: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminReportsScreen(),
                  ),
                );
              },
            ),
            _SettingsTile(
              icon: Icons.receipt_long_outlined,
              title: 'Checkout reminders',
              subtitle: 'Process due billing reminders',
              onTap: () => onProcessReminders(),
            ),
            _SettingsTile(
              icon: Icons.palette_outlined,
              title: 'Theme customization',
              subtitle: 'Reset personal admin theme',
              onTap: () => onThemeReset(),
            ),
            _SettingsTile(
              icon: Icons.list_alt_outlined,
              title: 'Activity logs & audit',
              subtitle: 'System activity tracking',
              onTap: onOpenActivityLogs,
            ),
            _SettingsTile(
              icon: Icons.lock_outline,
              title: 'Account & hotel login',
              subtitle: 'Admin password, hotel gate credentials',
              onTap: onOpenAccountSettings,
            ),
          ],
        ),
      ],
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.tiles});

  final String title;
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        ...tiles,
        const SizedBox(height: 16),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
