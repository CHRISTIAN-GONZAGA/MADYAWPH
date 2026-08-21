import 'package:flutter/material.dart';

import '../auth_storage.dart';
import '../ui/luxury_page_route.dart';
import 'dashboards.dart';
import 'hotel_screens.dart';

/// Opens room login then the in-house guest dashboard on success.
Future<void> openGuestPortalLogin(
  BuildContext context, {
  required String hotelId,
  String? hotelName,
  String? roomId,
  String? roomNumber,
  bool roomBoundFromQr = false,
}) async {
  await AuthStorage.clearPortalAuth();
  await AuthStorage.clearGuestAuth();

  if (!context.mounted) return;

  final loggedIn = await Navigator.of(context).push<bool>(
    LuxuryPageRoute<bool>(
      builder: (_) => GuestRoomLoginScreen(
        hotelId: hotelId,
        hotelName: hotelName,
        roomId: roomId,
        roomNumber: roomNumber,
        roomBoundFromQr: roomBoundFromQr,
      ),
    ),
  );

  if (loggedIn != true || !context.mounted) return;

  await Navigator.of(context).pushAndRemoveUntil(
    LuxuryPageRoute<void>(
      builder: (_) => const GuestDashboardScreen(),
    ),
    (route) => route.isFirst,
  );
}
