import 'package:flutter/material.dart';

import '../../../locale_controller.dart';
import '../../../widgets/language_picker_button.dart';
import '../../admin_categories.dart';
import '../../admin_chat.dart';
import '../../admin_reports.dart';
import '../../admin_rooms.dart';
import '../../admin_staff.dart';
import '../../admin_tasks.dart';
import '../admin_guest_portal_qr_screen.dart';
import '../admin_hotel_logo_screen.dart';
import '../admin_online_payment_screen.dart';

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
    this.creditsLocked = false,
  });

  final String creditBalance;
  final bool creditsLocked;
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
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.translate_outlined),
            title: Text(context.tr('change_language')),
            subtitle: Text(AppLocales.label(appLocaleNotifier.value)),
            trailing: const Icon(Icons.chevron_right),
            enabled: !creditsLocked,
            onTap: creditsLocked
                ? null
                : () => LanguagePickerButton.showPicker(context),
          ),
        ),
        if (creditsLocked) ...[
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                'Credits are depleted. Only recharge is available until your balance is above ₱0.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        _SettingsGroup(
          title: 'Operations',
          tiles: [
            _SettingsTile(
              icon: Icons.forum_outlined,
              title: 'Chatroom',
              subtitle: 'Guest and staff inboxes',
              enabled: !creditsLocked,
              onTap: () async {
                await Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminChatHubScreen(),
                  ),
                );
                await onRefreshAfterNav();
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
              subtitle: 'Edit room photo, rates, status, and setup',
              enabled: !creditsLocked,
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
              enabled: !creditsLocked,
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
              enabled: !creditsLocked,
              onTap: onSurgePricing,
            ),
            _SettingsTile(
              icon: Icons.image_outlined,
              title: 'Hotel logo',
              subtitle: 'Shown when guests search and browse your property',
              enabled: !creditsLocked,
              onTap: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminHotelLogoScreen(),
                  ),
                );
              },
            ),
            _SettingsTile(
              icon: Icons.qr_code_2_outlined,
              title: 'Guest portal QR',
              subtitle: 'QR for in-house guests to sign in from the app',
              enabled: !creditsLocked,
              onTap: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminGuestPortalQrScreen(),
                  ),
                );
              },
            ),
            _SettingsTile(
              icon: Icons.qr_code_scanner_outlined,
              title: 'Online payment (QR Ph)',
              subtitle: 'Upload QR for guest online payments & verify refs',
              enabled: !creditsLocked,
              onTap: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminOnlinePaymentScreen(),
                  ),
                );
              },
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
              enabled: !creditsLocked,
              onTap: () async {
                await Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminStaffScreen(),
                  ),
                );
                await onRefreshAfterNav();
              },
            ),
            _SettingsTile(
              icon: Icons.assignment_outlined,
              title: 'Assign tasks',
              subtitle: 'Delegate work to maintenance, reception, and staff',
              enabled: !creditsLocked,
              onTap: () async {
                await Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminTasksScreen(),
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
              enabled: !creditsLocked,
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
              enabled: !creditsLocked,
              onTap: () => onProcessReminders(),
            ),
            _SettingsTile(
              icon: Icons.palette_outlined,
              title: 'Theme customization',
              subtitle: 'Reset personal admin theme',
              enabled: !creditsLocked,
              onTap: () => onThemeReset(),
            ),
            _SettingsTile(
              icon: Icons.list_alt_outlined,
              title: 'Activity logs & audit',
              subtitle: 'System activity tracking',
              enabled: !creditsLocked,
              onTap: onOpenActivityLogs,
            ),
            _SettingsTile(
              icon: Icons.lock_outline,
              title: 'Account settings',
              subtitle: 'Admin password and portal admins',
              enabled: !creditsLocked,
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
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        enabled: enabled,
        onTap: enabled ? onTap : null,
      ),
    );
  }
}
