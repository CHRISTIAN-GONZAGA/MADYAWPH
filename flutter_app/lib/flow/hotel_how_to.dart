import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Detailed in-app guide shown from the hotel access (gate) screen.
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
                      'MADYAWPH is your hotel operations hub on mobile. Every person at your property starts on this screen with the **hotel username** and **password** you chose when the property was registered.\n\n'
                      'After hotel access succeeds, you pick a **role**: Administrator, Super admin, Staff, Public customer, or In-house Guest. Each role opens a different workspace scoped to your hotel only.',
                ),
                _Section(
                  title: '2. Hotel access (this screen)',
                  body:
                      '• Enter the property username and password.\n'
                      '• Tap **Continue** — you will see the role menu for that hotel.\n'
                      '• Tap **Register new hotel** only when creating a brand-new property (not for daily staff login).\n'
                      '• Use **Switch hotel** on the role menu if you manage more than one property and need to change context.',
                ),
                _Section(
                  title: '3. Account types',
                  body:
                      '**Hotel gate** — Shared property login (this screen). Required before any role.\n\n'
                      '**Super admin** — Owner account: manage hotel gate password, delete administrators, full settings.\n'
                      '• Username: your hotel username (same as gate username).\n'
                      '• Default password: the contact number from registration.\n\n'
                      '**Administrator** — Day-to-day operations: rooms, bookings, reports, chat, staff.\n'
                      '• Username: `{hotel_username}_admin`.\n'
                      '• Default password: `{hotel_username}123`.\n\n'
                      '**Staff** — Tasks, room status, maintenance reports, chat with admin.\n\n'
                      '**Public customer** — Browse categories, see availability, book or reserve with optional PWD/senior/student discount (ID photo).\n\n'
                      '**Guest (in-house)** — Checked-in guests use room number + room password for amenities, chat, billing, and checkout reminders.',
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
                      'From **Account & hotel login** you can change the hotel gate username/password (this signs everyone out). You can remove administrator accounts and manage who has admin access. Use super admin for ownership tasks; use administrator for daily front-desk work.',
                ),
                _Section(
                  title: '6. Staff workflow',
                  body:
                      'Open **Staff** on the role menu after hotel access. View assigned tasks, update room cleaning/maintenance status, message admin (with photo attachments), and report maintenance completion for a room.',
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
                      '• Forgot admin/staff password? Use forgot-password flow (SMS code to hotel contact number).\n'
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
  Map<String, dynamic>? sms,
  String? verificationCode,
}) async {
  final smsSent = sms?['sent'] == true;
  final smsPhone = (sms?['phone'] ?? '').toString();
  final smsError = (sms?['error'] ?? '').toString();
  final gate = portalAccounts?['hotel_gate'] as Map<String, dynamic>?;
  final superA = portalAccounts?['super_admin'] as Map<String, dynamic>?;
  final adminA = portalAccounts?['admin'] as Map<String, dynamic>?;

  final buffer = StringBuffer()
    ..writeln('Hotel: $hotelName')
    ..writeln()
    ..writeln('── Property login (Hotel access screen) ──')
    ..writeln('Username: ${gate?['username'] ?? ''}')
    ..writeln('Password: ${gate?['password'] ?? ''}')
    ..writeln()
    ..writeln('── Super admin (role menu) ──')
    ..writeln('Username: ${superA?['username'] ?? ''}')
    ..writeln('Password: ${superA?['password'] ?? ''}')
    ..writeln()
    ..writeln('── Administrator (role menu) ──')
    ..writeln('Username: ${adminA?['username'] ?? ''}')
    ..writeln('Password: ${adminA?['password'] ?? ''}');

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
              'Write these down or copy them now. Passwords are shown once.',
              style: Theme.of(ctx).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: smsSent
                    ? Colors.green.withValues(alpha: 0.12)
                    : Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    smsSent ? 'SMS sent' : 'SMS not sent',
                    style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  if (smsPhone.isNotEmpty)
                    Text('To: $smsPhone', style: Theme.of(ctx).textTheme.bodySmall),
                  if (!smsSent && smsError.isNotEmpty)
                    Text(smsError, style: Theme.of(ctx).textTheme.bodySmall),
                  if (!smsSent && verificationCode != null) ...[
                    const SizedBox(height: 8),
                    SelectableText(
                      'Verification code: $verificationCode',
                      style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            _CredentialBlock(
              title: 'Property login',
              subtitle: 'First screen · Hotel access',
              username: (gate?['username'] ?? '').toString(),
              password: (gate?['password'] ?? '').toString(),
            ),
            const SizedBox(height: 12),
            _CredentialBlock(
              title: 'Super admin',
              subtitle: 'Role menu → Super admin',
              username: (superA?['username'] ?? '').toString(),
              password: (superA?['password'] ?? '').toString(),
            ),
            const SizedBox(height: 12),
            _CredentialBlock(
              title: 'Administrator',
              subtitle: 'Role menu → Administrator',
              username: (adminA?['username'] ?? '').toString(),
              password: (adminA?['password'] ?? '').toString(),
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
