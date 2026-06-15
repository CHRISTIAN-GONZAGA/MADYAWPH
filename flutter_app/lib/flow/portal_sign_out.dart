import 'package:flutter/material.dart';

import '../auth_storage.dart';
import 'flow_state.dart';
import 'public_hotel_search_screen.dart';
import 'system_access_screen.dart';

/// Secondary confirmation before signing out of a hotel portal dashboard.
Future<bool> confirmPortalSignOut(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Sign out'),
      content: const Text('Are you sure?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Sign out'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Clears portal credentials and returns to the role picker for this hotel.
Future<void> signOutPortalToRoleSelection(BuildContext context) async {
  await AuthStorage.clearPortalAuth();
  if (!context.mounted) return;

  final hotelId = await AuthStorage.hotelId();
  final hotelName = await AuthStorage.hotelName();
  if (!context.mounted) return;

  if (hotelId == null || hotelId.isEmpty) {
    hotelSessionNotifier.value = null;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const PublicHotelSearchScreen()),
      (_) => false,
    );
    return;
  }

  final session = HotelSession(
    hotelId: hotelId,
    hotelName: hotelName?.trim().isNotEmpty == true
        ? hotelName!.trim()
        : 'Hotel',
  );
  hotelSessionNotifier.value = session;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute<void>(
      builder: (_) => SystemAccessScreen(session: session),
    ),
    (_) => false,
  );
}

/// Confirmation prompt, then sign out back to role selection.
Future<void> confirmAndSignOutPortalToRoleSelection(BuildContext context) async {
  final confirmed = await confirmPortalSignOut(context);
  if (!confirmed || !context.mounted) return;
  await signOutPortalToRoleSelection(context);
}
