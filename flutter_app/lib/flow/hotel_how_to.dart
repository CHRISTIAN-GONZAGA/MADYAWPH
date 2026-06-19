import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Detailed in-app guide shown from the choose-hotel screen.
class HotelHowToGuide {
  HotelHowToGuide._();

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.88,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        builder: (_, scrollController) {
          return _HowToSheet(scrollController: scrollController);
        },
      ),
    );
  }
}

class _HowToSheet extends StatelessWidget {
  const _HowToSheet({required this.scrollController});

  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'How to use MADYAWPH',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: const [
                _Section(
                  title: '1. Getting started',
                  body:
                      'MADYAWPH is your hotel operations hub on mobile. From the home screen, tap the **property badge** to sign in with your hotel gate username and password.\n\n'
                      'New hotels tap **Register hotel** on that screen. After registration you land in the **admin dashboard** — add categories and rooms under Settings first.\n\n'
                      'Returning staff pick a **role** (Administrator, Super admin, Staff, Owner, or Public customer). Each role opens a workspace scoped to **that hotel only**.',
                ),
                _Section(
                  title: '2. Property sign-in',
                  body:
                      '• Enter the **gate username and password** from registration (same as you chose when creating the hotel).\n'
                      '• Tap **Register hotel** only when creating a brand-new property.\n'
                      '• After the gate, choose your **role** on System Access.\n'
                      '• Use **Switch hotel** to return to the property sign-in screen.',
                ),
                _Section(
                  title: '3. Account types',
                  body:
                      '**Super admin** — Full admin dashboard plus **Control** tab to add/remove administrators.\n'
                      '• Username: your registration username.\n'
                      '• Password: the password you chose on the registration form.\n\n'
                      '**Administrator** — Day-to-day operations: rooms, bookings, walk-in, chat, staff.\n'
                      '• Username: `{hotel_username}_admin`.\n'
                      '• Password: same as registration.\n\n'
                      '**Staff** — Tasks, room status, maintenance reports, chat with admin.\n\n'
                      '**Public customer** — Browse and book online (Online bookings).\n\n'
                      '**Guest (in-house)** — Room number + room password for amenities and chat.',
                ),
                _Section(
                  title: '4. Administrator workflow',
                  body:
                      '**Dashboard** — Occupancy snapshot, credits, recent activity.\n\n'
                      '**Rooms** — Add/edit rooms, set status (available, booked, maintenance), view charges, mark payment paid/unpaid, issue refunds (updates reports).\n\n'
                      '**Bookings** — Confirm walk-ins, external reservations, check-in/out.\n\n'
                      '**Categories** — Group rooms; availability counts show on the public customer portal.\n\n'
                      '**Staff** — Add staff accounts linked to tasks.\n\n'
                      '**Chat** — Separate **Guests** and **Staff** inboxes; attach photos from gallery or camera.\n\n'
                      '**Reports & analytics** — Revenue by period, profit overview (daily/weekly/monthly/annual), refunds, room/amenity breakdown, occupancy, transfers, task completion, activity timeline.\n\n'
                      '**Amenity menu** — Paid add-ons guests can order from their room.\n\n'
                      '**Activity logs** — Audit trail of admin/staff actions.',
                ),
                _Section(
                  title: '5. Super admin extras',
                  body:
                      'Use the **Control** tab to add or remove administrator accounts and upload the property picker banner. '
                      'Super admin has every administrator feature (rooms, walk-in, bookings, reports, chat). '
                      'Sign out and choose **Super admin** on System Access if you logged in as Administrator but need the Control tab.',
                ),
                _Section(
                  title: '6. Staff workflow',
                  body:
                      'Open **Staff** on the role menu after choosing your hotel. View assigned tasks, update room cleaning/maintenance status, message admin (with photo attachments), and report maintenance completion for a room.',
                ),
                _Section(
                  title: '7. Payments & reports',
                  body:
                      'When a booking is marked **paid**, revenue appears in reports based on billing charges (room nights, extend-stay, amenities). **Refunds** reduce net revenue. Charts use the period selector (daily / weekly / monthly / annual). Pull down to refresh any screen.',
                ),
                _Section(
                  title: '8. Tips & troubleshooting',
                  body:
                      '• Save credentials shown after registration — they are not emailed by default.\n'
                      '• Forgot admin/staff password? Contact your hotel administrator (email reset coming soon).\n'
                      '• If reports look empty, confirm bookings are marked paid and dates fall in the selected range.\n'
                      '• Chat images require network access to the API server.\n'
                      '• For support, keep your hotel name, username, and the error message on screen.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paragraphs = body.split('\n\n');
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          ...paragraphs.map((p) {
            final lines = p.split('\n');
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: lines.map((line) {
                  final trimmed = line.trim();
                  if (trimmed.isEmpty) return const SizedBox.shrink();
                  final isBullet = trimmed.startsWith('•');
                  return Padding(
                    padding: EdgeInsets.only(
                      left: isBullet ? 4 : 0,
                      bottom: 4,
                    ),
                    child: Text(
                      trimmed,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                    ),
                  );
                }).toList(),
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// Dialog after successful hotel registration with copy-friendly credentials.
Future<void> showHotelRegistrationCredentialsDialog(
  BuildContext context, {
  required String hotelName,
  required Map<String, dynamic>? portalAccounts,
  Map<String, dynamic>? welcomeCredits,
  String? verifiedEmail,
  String? registrationUsername,
  String? registrationPassword,
}) async {
  final email = (verifiedEmail ?? '').trim();
  final propertyA = portalAccounts?['property'] as Map<String, dynamic>?;
  final superA = portalAccounts?['super_admin'] as Map<String, dynamic>?;
  final adminA = portalAccounts?['admin'] as Map<String, dynamic>?;
  final propertyUser = (registrationUsername ?? propertyA?['username'] ?? superA?['username'] ?? '')
      .toString()
      .trim();
  final propertyPass = (registrationPassword ?? propertyA?['password'] ?? superA?['password'] ?? '')
      .toString();
  final ownerUser = propertyUser;
  final ownerPass = propertyPass;
  final adminUser = ownerUser.isEmpty
      ? (adminA?['username'] ?? '').toString()
      : '${ownerUser}_admin';
  final adminPass = ownerPass.isEmpty
      ? (adminA?['password'] ?? '').toString()
      : ownerPass;
  final freeCredits = (welcomeCredits?['free_credits'] as num?)?.toInt();
  final totalRooms = welcomeCredits?['total_rooms'];
  final tierLabel = (welcomeCredits?['tier_label'] ?? '').toString();

  final buffer = StringBuffer()
    ..writeln('Hotel: $hotelName')
    ..writeln()
    ..writeln('── Property login ──')
    ..writeln('Username: $propertyUser')
    ..writeln('Password: $propertyPass')
    ..writeln('(Home → Property sign in — unlocks your hotel in the app)')
    ..writeln()
    ..writeln('After property sign-in, open the role menu for staff roles.')
    ..writeln()
    ..writeln('── Super admin ──')
    ..writeln('Username: $ownerUser')
    ..writeln('Password: $ownerPass')
    ..writeln()
    ..writeln('── Administrator ──')
    ..writeln('Username: $adminUser')
    ..writeln('Password: $adminPass');

  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Hotel created — save these logins'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Write these down or copy them now. Passwords are shown once. '
              'Property login unlocks your hotel on the home screen; admin and super admin '
              'are used from the role menu after that. You will enter the admin dashboard next — '
              'use Settings → Categories & rooms to set up rooms.',
              style: Theme.of(ctx).textTheme.bodyMedium,
            ),
            if (freeCredits != null && freeCredits > 0) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome wallet credits',
                      style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '₱${freeCredits.toString()} added to your hotel wallet '
                      '($totalRooms room(s), $tierLabel tier).',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (email.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Email verified',
                      style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Text('Verified: $email', style: Theme.of(ctx).textTheme.bodySmall),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            _CredentialBlock(
              title: 'Property login',
              subtitle: 'Home → Property sign in · unlocks this hotel in the app',
              username: propertyUser,
              password: propertyPass,
            ),
            const SizedBox(height: 12),
            _CredentialBlock(
              title: 'Super admin',
              subtitle: 'Role menu → Super admin · same password you just entered',
              username: ownerUser,
              password: ownerPass,
            ),
            const SizedBox(height: 12),
            _CredentialBlock(
              title: 'Administrator',
              subtitle: 'Role menu → Administrator · username ends with _admin',
              username: adminUser,
              password: adminPass,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: buffer.toString()));
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('Credentials copied to clipboard')),
              );
            }
          },
          child: const Text('Copy all'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('I saved these'),
        ),
      ],
    ),
  );
}

class _CredentialBlock extends StatelessWidget {
  const _CredentialBlock({
    required this.title,
    required this.subtitle,
    required this.username,
    required this.password,
  });

  final String title;
  final String subtitle;
  final String username;
  final String password;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          Text(
            subtitle,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText('Username: $username'),
          SelectableText('Password: $password'),
        ],
      ),
    );
  }
}
