import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../auth_storage.dart';
import '../dio_client.dart';
import '../locale_controller.dart';
import 'central_admin/central_admin_dashboard_screen.dart';
import 'dashboards.dart';
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
    });
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
