import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../dio_client.dart';
import '../../widgets/admin_curved_nav_bar.dart';
import '../admin_chat.dart';
import 'admin_dashboard_header.dart';
import 'sections/amenities_section.dart';
import 'sections/checkout_section.dart';
import 'sections/guest_portfolio_section.dart';
import 'sections/reservation_section.dart';
import 'sections/room_summary_section.dart';
import 'sections/settings_section.dart';

class AdminDashboardShell extends StatefulWidget {
  const AdminDashboardShell({
    super.key,
    required this.data,
    required this.onRefresh,
    required this.onSignOut,
    required this.busyAction,
    required this.onRecharge,
    required this.onSurgePricing,
    required this.onThemeReset,
    required this.onProcessReminders,
    required this.onAmenityAddProduct,
    required this.onOpenActivityLogs,
    required this.onOpenAccountSettings,
  });

  final Map<String, dynamic> data;
  final Future<void> Function() onRefresh;
  final VoidCallback onSignOut;
  final bool busyAction;
  final VoidCallback onRecharge;
  final VoidCallback onSurgePricing;
  final Future<void> Function() onThemeReset;
  final Future<void> Function() onProcessReminders;
  final Future<void> Function() onAmenityAddProduct;
  final VoidCallback onOpenActivityLogs;
  final VoidCallback onOpenAccountSettings;

  @override
  State<AdminDashboardShell> createState() => _AdminDashboardShellState();
}

class _AdminDashboardShellState extends State<AdminDashboardShell> {
  int _tab = 0;
  Map<String, dynamic>? _inbox;
  Timer? _chatPoll;

  static const _navItems = [
    AdminNavItem(label: 'Summary', icon: Icons.dashboard_outlined),
    AdminNavItem(label: 'Checkout', icon: Icons.logout_outlined),
    AdminNavItem(label: 'Guests', icon: Icons.people_outline),
    AdminNavItem(label: 'Bookings', icon: Icons.event_note_outlined),
    AdminNavItem(label: 'Amenities', icon: Icons.storefront_outlined),
    AdminNavItem(label: 'Settings', icon: Icons.settings_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _pollInbox();
    _chatPoll = Timer.periodic(const Duration(seconds: 15), (_) => _pollInbox());
  }

  @override
  void dispose() {
    _chatPoll?.cancel();
    super.dispose();
  }

  Future<void> _pollInbox() async {
    try {
      final res =
          await portalDio().get<Map<String, dynamic>>('/admin/chat/inbox');
      if (!mounted) return;
      setState(() => _inbox = res.data);
    } on DioException {
      // Keep last inbox snapshot.
    }
  }

  List<Map<String, dynamic>> get _rooms {
    return (widget.data['rooms'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final auth = d['auth'] as Map<String, dynamic>?;
    final user = auth?['user'] as Map<String, dynamic>?;
    final hotelName =
        (user?['hotelName'] ?? user?['hotel_name'] ?? 'Hotel').toString();
    final adminName = (user?['name'] ?? user?['username'] ?? 'Admin').toString();
    final chats = d['guestMessages'] as List<dynamic>? ?? [];
    final credits = d['credits'] as Map<String, dynamic>?;
    final balance =
        credits != null ? '${credits['currentCredits'] ?? ''}' : '—';

    final badge = adminChatBadgeFromData(
      inbox: _inbox,
      guestMessages: chats,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF5F2FF),
      body: SafeArea(
        child: Column(
          children: [
            AdminDashboardHeader(
              hotelName: hotelName,
              adminName: adminName,
              chatBadge: badge,
              onOpenChat: () async {
                await Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminChatHubScreen(),
                  ),
                );
                await widget.onRefresh();
                await _pollInbox();
              },
              onRefresh: () async {
                await widget.onRefresh();
                await _pollInbox();
              },
              onSignOut: widget.onSignOut,
            ),
            if (widget.busyAction)
              const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  await widget.onRefresh();
                  await _pollInbox();
                },
                child: IndexedStack(
                  index: _tab,
                  children: _allSections(d, balance),
                ),
              ),
            ),
            AdminCurvedNavBar(
              items: _navItems,
              currentIndex: _tab,
              onTap: (i) => setState(() => _tab = i),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _allSections(Map<String, dynamic> d, String balance) {
    final tasks = d['tasks'] as List<dynamic>? ?? [];
    final reservations = d['reservations'] as List<dynamic>? ?? [];
    final claims = d['amenityClaims'] as List<dynamic>? ?? [];

    final refreshKey = ValueKey(
      '${_rooms.length}-${reservations.length}-${claims.length}-${tasks.length}',
    );

    return [
      RoomSummarySection(key: refreshKey, rooms: _rooms, tasks: tasks),
      CheckoutSection(key: refreshKey, rooms: _rooms),
      GuestPortfolioSection(key: refreshKey, rooms: _rooms),
      ReservationSection(
        key: refreshKey,
        reservations: reservations,
        onChanged: widget.onRefresh,
      ),
      AmenitiesSection(
        key: refreshKey,
        claims: claims,
        onAddProduct: widget.onAmenityAddProduct,
        onRefresh: widget.onRefresh,
      ),
      SettingsSection(
        creditBalance: balance,
        onRecharge: widget.onRecharge,
        onSurgePricing: widget.onSurgePricing,
        onThemeReset: widget.onThemeReset,
        onProcessReminders: widget.onProcessReminders,
        onOpenActivityLogs: widget.onOpenActivityLogs,
        onOpenAccountSettings: widget.onOpenAccountSettings,
        onRefreshAfterNav: widget.onRefresh,
      ),
    ];
  }
}
