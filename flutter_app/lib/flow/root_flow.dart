import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../auth_storage.dart';
import '../dio_client.dart';
import '../locale_controller.dart';
import 'central_admin/central_admin_dashboard_screen.dart';
import 'dashboards.dart';
import 'flow_state.dart';
import 'owner_dashboard_screen.dart';
import 'public_hotel_search_screen.dart';

/// App home after intro: public hotel search (Agoda-style). Staff use the badge icon.
class FlowRoot extends StatefulWidget {
  const FlowRoot({super.key});

  @override
  State<FlowRoot> createState() => _FlowRootState();
}

class _FlowRootState extends State<FlowRoot> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resumeCentralAdminSession();
      _resumeGuestSession();
      _resumeHotelStaffSession();
    });
  }

  Future<void> _resumeHotelStaffSession() async {
    await AuthStorage.enforcePortalSessionTimeout();
    final role = await AuthStorage.portalRole();
    final token = await AuthStorage.portalToken();
    final hotelId = await AuthStorage.hotelId();
    final hotelName = await AuthStorage.hotelName();
    if (!mounted ||
        token == null ||
        token.isEmpty ||
        hotelId == null ||
        hotelId.isEmpty) {
      return;
    }
    if (role == 'central_admin') return;

    const staffRoles = {'admin', 'frontdesk', 'staff', 'super_admin', 'owner'};
    if (role == null || !staffRoles.contains(role)) return;

    try {
      final res = await portalDio().get<Map<String, dynamic>>('/auth/session');
      if (!mounted) return;
      final apiRole =
          ((res.data?['user'] as Map<String, dynamic>?)?['role'] ?? '')
              .toString();
      if (!staffRoles.contains(apiRole)) {
        await AuthStorage.clearPortalAuth();
        return;
      }

      hotelSessionNotifier.value = HotelSession(
        hotelId: hotelId,
        hotelName: hotelName ?? 'Hotel',
      );

      final screen = switch (apiRole) {
        'frontdesk' => const AdminDashboardScreen(isFrontDesk: true),
        'staff' => const StaffDashboardScreen(),
        'owner' => const OwnerDashboardScreen(),
        'super_admin' => const AdminDashboardScreen(isSuperAdmin: true),
        _ => const AdminDashboardScreen(),
      };

      await Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => screen),
        (_) => false,
      );
    } on DioException catch (_) {
      await AuthStorage.clearPortalAuth();
    }
  }

  Future<void> _resumeCentralAdminSession() async {
    final role = await AuthStorage.portalRole();
    if (role != 'central_admin' || !mounted) return;
    try {
      await portalDio().get<Map<String, dynamic>>('/platform/settings');
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const CentralAdminDashboardScreen(),
        ),
      );
    } on DioException catch (_) {
      await AuthStorage.clearPortalAuth();
    }
  }

  Future<void> _resumeGuestSession() async {
    final token = await AuthStorage.guestToken();
    if (token == null || token.isEmpty || !mounted) return;

    try {
      await guestDio().get<Map<String, dynamic>>('/guest/dashboard');
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const GuestDashboardScreen(),
        ),
      );
    } on DioException catch (_) {
      await AuthStorage.clearGuestAuth();
    } catch (_) {
      await AuthStorage.clearGuestAuth();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LocaleScope(
      builder: (context, _) => const PublicHotelSearchScreen(),
    );
  }
}
