import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../dio_client.dart';
import '../../widgets/admin_curved_nav_bar.dart';
import 'admin_dashboard_models.dart';
import '../../widgets/theme_fab.dart';
import '../admin_chat.dart';
import 'admin_dashboard_header.dart';
import 'sections/amenities_section.dart';
import 'sections/bookings_section.dart';
import 'sections/checkout_section.dart';
import 'sections/guest_portfolio_section.dart';
import 'sections/room_summary_section.dart';
import 'sections/settings_section.dart';
import 'sections/super_admin_control_section.dart';

class AdminDashboardShell extends StatefulWidget {
  const AdminDashboardShell({
    super.key,
    required this.data,
    required this.onRefresh,
    required this.onSignOut,
    required this.busyAction,
    required this.isSuperAdmin,
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
  final bool isSuperAdmin;
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
  String _bookingListFilter = 'all';
  Map<String, dynamic>? _inbox;
  Timer? _chatPoll;

  List<AdminNavItem> _navItemsFor(Map<String, dynamic> d) {
    final reservations = d['reservations'] as List<dynamic>? ?? const [];
    final claims = d['amenityClaims'] as List<dynamic>? ?? const [];
    final pendingRes = AdminDashboardModels.pendingReservationCount(reservations);
    final checkoutSoon = AdminDashboardModels.checkoutSoonCount(_rooms);
    final pendingClaims = AdminDashboardModels.pendingAmenityClaimCount(claims);

    final items = <AdminNavItem>[
      const AdminNavItem(
        label: 'Summary',
        shortLabel: 'Rooms',
        icon: Icons.dashboard_outlined,
      ),
      AdminNavItem(
        label: 'Checkout',
        shortLabel: 'Out',
        icon: Icons.logout_outlined,
        badgeCount: checkoutSoon,
        badgeColor: const Color(0xFF1565C0),
      ),
      const AdminNavItem(
        label: 'Guests',
        shortLabel: 'Guests',
        icon: Icons.people_outline,
      ),
      AdminNavItem(
        label: 'Bookings',
        shortLabel: 'Book',
        icon: Icons.event_note_outlined,
        badgeCount: pendingRes,
        badgeColor: const Color(0xFF6A1B9A),
      ),
      AdminNavItem(
        label: 'Amenities',
        shortLabel: 'Store',
        icon: Icons.storefront_outlined,
        badgeCount: pendingClaims,
        badgeColor: const Color(0xFF2E7D32),
      ),
      const AdminNavItem(
        label: 'Settings',
        shortLabel: 'Setup',
        icon: Icons.settings_outlined,
      ),
    ];
    if (widget.isSuperAdmin) {
      items.add(
        const AdminNavItem(
          label: 'Control',
          shortLabel: 'Admins',
          icon: Icons.admin_panel_settings_outlined,
        ),
      );
    }
    return items;
  }

  @override
  void initState() {
    super.initState();
    _pollInbox();
    _chatPoll = Timer.periodic(const Duration(seconds: 15), (_) => _pollInbox());
  }

  @override
  void didUpdateWidget(AdminDashboardShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      _pollInbox();
    }
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

    final navItems = _navItemsFor(d);
    final safeTab = _tab.clamp(0, navItems.length - 1);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F2FF),
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                AdminDashboardHeader(
                  hotelName: hotelName,
                  adminName: adminName,
                  isSuperAdmin: widget.isSuperAdmin,
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
                      index: safeTab,
                      children: _allSections(d, balance),
                    ),
                  ),
                ),
                AdminCurvedNavBar(
                  items: navItems,
                  currentIndex: safeTab,
                  onTap: (i) => setState(() => _tab = i),
                ),
              ],
            ),
          ),
          const ThemeFab(),
        ],
      ),
    );
  }

  void _openBookingsTab(String filter) {
    setState(() {
      _bookingListFilter = filter;
      _tab = 3;
    });
  }

  List<Widget> _allSections(Map<String, dynamic> d, String balance) {
    final tasks = d['tasks'] as List<dynamic>? ?? [];
    final reservations = d['reservations'] as List<dynamic>? ?? [];
    final claims = d['amenityClaims'] as List<dynamic>? ?? [];
    final bookingStats =
        d['booking_stats'] as Map<String, dynamic>? ?? const {};
    final bookings = (d['bookings'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final localTotal = (bookingStats['local_total'] as num?)?.toInt() ?? 0;
    final onlineTotal = (bookingStats['online_total'] as num?)?.toInt() ?? 0;

    final refreshKey = ValueKey(
      '${_rooms.length}-${reservations.length}-${claims.length}-${tasks.length}-${bookings.length}-${widget.isSuperAdmin}',
    );

    final sections = <Widget>[
      RoomSummarySection(
        key: refreshKey,
        rooms: _rooms,
        tasks: tasks,
        localBookingsTotal: localTotal,
        onlineBookingsTotal: onlineTotal,
        onOpenLocalBookings: () => _openBookingsTab('local'),
        onOpenOnlineBookings: () => _openBookingsTab('online'),
      ),
      CheckoutSection(key: refreshKey, rooms: _rooms),
      GuestPortfolioSection(key: refreshKey, rooms: _rooms),
      BookingsSection(
        key: ValueKey('bookings-$_bookingListFilter-${bookings.length}'),
        rooms: _rooms,
        reservations: reservations,
        bookings: bookings,
        bookingFilter: _bookingListFilter,
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

    if (widget.isSuperAdmin) {
      sections.add(
        SuperAdminControlSection(
          key: refreshKey,
          onOpenAccountSettings: widget.onOpenAccountSettings,
        ),
      );
    }

    return sections;
  }
}
