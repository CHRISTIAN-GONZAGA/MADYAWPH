import 'package:flutter/material.dart';

import '../../../locale_controller.dart';
import '../../../widgets/language_picker_button.dart';
import '../../admin_categories.dart';
import '../../admin_chat.dart';
import '../../admin_rooms.dart';
import '../../admin_staff.dart';
import '../../admin_tasks.dart';
import '../admin_guest_portal_qr_screen.dart';
import '../admin_hotel_logo_screen.dart';
import '../admin_online_payment_screen.dart';
import '../admin_portal_users_screen.dart';
import '../admin_room_fee_presets_screen.dart';
import '../admin_cancellation_retention_screen.dart';
import '../admin_min_check_in_payment_screen.dart';
import '../admin_early_check_in_fee_screen.dart';
import '../admin_late_checkout_fee_screen.dart';
import '../admin_notification_emails_screen.dart';

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
    this.isFrontDesk = false,
    this.isSuperAdmin = false,
  });

  final String creditBalance;
  final bool creditsLocked;
  final bool isFrontDesk;
  final bool isSuperAdmin;
  final VoidCallback onRecharge;
  final VoidCallback onSurgePricing;
  final Future<void> Function() onThemeReset;
  final Future<void> Function() onProcessReminders;
  final VoidCallback onOpenActivityLogs;
  final VoidCallback onOpenAccountSettings;
  final Future<void> Function() onRefreshAfterNav;

  bool get _opsEnabled => isFrontDesk || !creditsLocked;

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
            enabled: _opsEnabled,
            onTap: _opsEnabled
                ? () => LanguagePickerButton.showPicker(context)
                : null,
          ),
        ),
        if (creditsLocked) ...[
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                isFrontDesk
                    ? 'Credits are depleted. Operational tabs are locked. You can still view Hotel totals reports and change your password here.'
                    : 'Credits are depleted. Only recharge is available until your balance is above ₱0.',
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
              enabled: _opsEnabled,
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
        if (!isFrontDesk) ...[
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
                icon: Icons.receipt_long_outlined,
                title: 'Room fee options',
                subtitle: 'Preset reasons for Add fee in room details',
                enabled: !creditsLocked,
                onTap: () async {
                  await Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const AdminRoomFeePresetsScreen(),
                    ),
                  );
                  await onRefreshAfterNav();
                },
              ),
              _SettingsTile(
                icon: Icons.cancel_outlined,
                title: 'Cancellation retention',
                subtitle: 'Percent of paid booking kept when cancelled',
                enabled: !creditsLocked,
                onTap: () async {
                  await Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const AdminCancellationRetentionScreen(),
                    ),
                  );
                  await onRefreshAfterNav();
                },
              ),
              if (!isFrontDesk)
                _SettingsTile(
                  icon: Icons.payments_outlined,
                  title: 'Check-in payment %',
                  subtitle:
                      'Minimum percent of the room bill required before check-in',
                  enabled: !creditsLocked,
                  onTap: () async {
                    await Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const AdminMinCheckInPaymentScreen(),
                      ),
                    );
                    await onRefreshAfterNav();
                  },
                ),
              if (!isFrontDesk)
                _SettingsTile(
                  icon: Icons.login_outlined,
                  title: 'Early check-in fee',
                  subtitle:
                      'Grace minutes before 3:00 PM, and the fee amount',
                  enabled: !creditsLocked,
                  onTap: () async {
                    await Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const AdminEarlyCheckInFeeScreen(),
                      ),
                    );
                    await onRefreshAfterNav();
                  },
                ),
              if (!isFrontDesk)
                _SettingsTile(
                  icon: Icons.schedule_outlined,
                  title: 'Late check-out fee',
                  subtitle:
                      'Grace minutes after check-out time, and the fee amount',
                  enabled: !creditsLocked,
                  onTap: () async {
                    await Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const AdminLateCheckoutFeeScreen(),
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
                subtitle: 'Add maintenance, reception, and other staff logins',
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
                icon: Icons.badge_outlined,
                title: isSuperAdmin ? 'Portal accounts' : 'Front desk accounts',
                subtitle: isSuperAdmin
                    ? 'Create administrators and front desk logins'
                    : 'Create and remove front desk sign-in accounts',
                enabled: !creditsLocked,
                onTap: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => AdminPortalUsersScreen(
                        canManageAdmins: isSuperAdmin,
                      ),
                    ),
                  );
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
        ],
        _SettingsGroup(
          title: isFrontDesk ? 'Account' : 'System',
          tiles: [
            if (!isFrontDesk)
              _SettingsTile(
                icon: Icons.account_balance_wallet_outlined,
                title: 'Credits: $creditBalance',
                subtitle: 'Recharge via GCash or PayMaya',
                onTap: onRecharge,
              ),
            if (!isFrontDesk) ...[
              _SettingsTile(
                icon: Icons.receipt_long_outlined,
                title: 'Checkout reminders',
                subtitle: 'Process due billing reminders',
                enabled: !creditsLocked,
                onTap: () => onProcessReminders(),
              ),
              _SettingsTile(
                icon: Icons.list_alt_outlined,
                title: 'Activity logs & audit',
                subtitle: 'System activity tracking',
                enabled: !creditsLocked,
                onTap: onOpenActivityLogs,
              ),
            ],
            _SettingsTile(
              icon: Icons.palette_outlined,
              title: 'Theme customization',
              subtitle: 'Reset personal admin theme',
              enabled: _opsEnabled,
              onTap: () => onThemeReset(),
            ),
            if (!isFrontDesk) ...[
              _SettingsTile(
                icon: Icons.mark_email_read_outlined,
                title: 'Owner & notification Gmail',
                subtitle: 'Guest portal check-in and room status alerts',
                enabled: !creditsLocked,
                onTap: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const AdminNotificationEmailsScreen(),
                    ),
                  );
                },
              ),
            ],
            _SettingsTile(
              icon: Icons.lock_outline,
              title: 'Account settings',
              subtitle: isFrontDesk
                  ? 'Change your password'
                  : 'Password, Gmail, and portal admins',
              enabled: isFrontDesk || !creditsLocked,
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
