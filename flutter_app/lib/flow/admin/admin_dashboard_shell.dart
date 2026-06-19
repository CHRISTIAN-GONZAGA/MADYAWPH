import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../dio_client.dart';
import '../../widgets/admin_curved_nav_bar.dart';
import '../../widgets/hotel_credits_policy.dart';
import 'admin_dashboard_models.dart';
import '../../widgets/theme_fab.dart';
import '../admin_chat.dart';
import 'admin_dashboard_header.dart';
import 'sections/amenities_section.dart';
import 'sections/bookings_section.dart';
import 'sections/checkout_section.dart';
import 'sections/guest_portfolio_section.dart';
import 'sections/manual_booking_section.dart';
import 'sections/room_summary_section.dart';
import 'sections/resellers_section.dart';
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
    this.onBindBackHandler,
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
  final ValueChanged<bool Function()>? onBindBackHandler;

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
      const AdminNavItem(
        label: 'Walk-in',
        shortLabel: 'Walk-in',
        icon: Icons.meeting_room_outlined,
      ),
      AdminNavItem(
        label: 'Amenities',
        shortLabel: 'Store',
        icon: Icons.storefront_outlined,
        badgeCount: pendingClaims,
        badgeColor: const Color(0xFF2E7D32),
      ),
      const AdminNavItem(
        label: 'Resellers',
        shortLabel: 'QR',
        icon: Icons.qr_code_scanner_outlined,
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
    _chatPoll = Timer.periodic(const Duration(seconds: 10), (_) => _pollInbox());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onBindBackHandler?.call(_handleInnerBack);
      if (!mounted) return;
      final credits = widget.data['credits'] as Map<String, dynamic>?;
      final balance =
          (credits?['currentCredits'] as num?)?.toDouble() ?? 0;
      if (HotelCreditsPolicy.isDepleted(balance)) {
        setState(() => _tab = _settingsTabIndex(widget.data));
      }
    });
  }

  @override
  void didUpdateWidget(AdminDashboardShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      _pollInbox();
      _maybeRedirectToCreditsTab(oldWidget.data, widget.data);
    }
    final oldMsgs = oldWidget.data['guestMessages'] as List? ?? const [];
    final newMsgs = widget.data['guestMessages'] as List? ?? const [];
    if (oldMsgs != newMsgs && mounted) {
      setState(() {});
    }
  }

  int _settingsTabIndex(Map<String, dynamic> d) => 7;

  void _maybeRedirectToCreditsTab(
    Map<String, dynamic> oldData,
    Map<String, dynamic> newData,
  ) {
    final oldCredits = oldData['credits'] as Map<String, dynamic>?;
    final newCredits = newData['credits'] as Map<String, dynamic>?;
    final oldBalance =
        (oldCredits?['currentCredits'] as num?)?.toDouble() ?? 0;
    final newBalance =
        (newCredits?['currentCredits'] as num?)?.toDouble() ?? 0;
    if (!HotelCreditsPolicy.isDepleted(oldBalance) &&
        HotelCreditsPolicy.isDepleted(newBalance)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _tab = _settingsTabIndex(newData));
      });
    }
  }

  @override
  void dispose() {
    widget.onBindBackHandler?.call(() => false);
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
      // Keep last inbox snapshot; guestMessages fallback still drives badge.
    }
  }

  AdminChatBadgeInfo _chatBadge(Map<String, dynamic> d) {
    final chats = d['guestMessages'] as List<dynamic>? ?? [];
    return adminChatBadgeFromData(inbox: _inbox, guestMessages: chats);
  }

  List<Map<String, dynamic>> get _rooms {
    return AdminDashboardModels.parseRoomMaps(
      widget.data['rooms'] as List<dynamic>?,
    );
  }

  bool _handleInnerBack() => false;

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final auth = d['auth'] as Map<String, dynamic>?;
    final user = auth?['user'] as Map<String, dynamic>?;
    final hotelName =
        (user?['hotelName'] ?? user?['hotel_name'] ?? 'Hotel').toString();
    final adminName = (user?['name'] ?? user?['username'] ?? 'Admin').toString();
    final credits = d['credits'] as Map<String, dynamic>?;
    final creditAmount = (credits?['currentCredits'] as num?)?.toDouble() ?? 0;
    final balance =
        credits != null ? '${credits['currentCredits'] ?? ''}' : '—';

    final badge = _chatBadge(d);

    final navItems = _navItemsFor(d);
    final safeTab = _tab.clamp(0, navItems.length - 1);
    final creditsLocked = HotelCreditsPolicy.areActionsLocked(creditAmount);
    final settingsTab = _settingsTabIndex(d);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F2FF),
      body: Stack(
        fit: StackFit.expand,
        children: [
          SafeArea(
            child: Column(
              children: [
                AdminDashboardHeader(
                  hotelName: hotelName,
                  adminName: adminName,
                  isSuperAdmin: widget.isSuperAdmin,
                  creditsLocked: creditsLocked,
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
                HotelCreditsReminderBanner(
                  balance: creditAmount,
                  onTopUp: widget.onRecharge,
                ),
                if (widget.busyAction)
                  const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: AdminCreditsGate(
                    balance: creditAmount,
                    onTopUp: widget.onRecharge,
                    child: RefreshIndicator(
                      onRefresh: creditsLocked && safeTab != settingsTab
                          ? () async {}
                          : () async {
                              await widget.onRefresh();
                              await _pollInbox();
                            },
                      child: IndexedStack(
                        index: safeTab,
                        children: _allSections(
                          d,
                          hotelName,
                          balance,
                          creditAmount,
                          settingsTab,
                        ),
                      ),
                    ),
                  ),
                ),
                AdminCurvedNavBar(
                  items: navItems,
                  currentIndex: safeTab,
                  canSelectTab: creditsLocked
                      ? (i) => i == settingsTab
                      : null,
                  onBlockedTabTap: creditsLocked
                      ? () => AdminCreditsGate.showActionsBlockedMessage(
                            context,
                          )
                      : null,
                  onTap: (i) => setState(() => _tab = i),
                ),
              ],
            ),
          ),
          if (!creditsLocked) const ThemeFab(),
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

  List<Widget> _allSections(
    Map<String, dynamic> d,
    String hotelName,
    String balance,
    double creditAmount,
    int settingsTab,
  ) {
    final creditsLocked = HotelCreditsPolicy.areActionsLocked(creditAmount);
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
    final recentBookings24h =
        (bookingStats['recent_24h'] as num?)?.toInt() ?? 0;
    final pendingReservationsStat =
        (bookingStats['pending_reservations'] as num?)?.toInt() ??
            AdminDashboardModels.pendingReservationCount(reservations);

    final refreshKey = ValueKey(
      '${_rooms.length}-${reservations.length}-${claims.length}-${tasks.length}-${bookings.length}-${widget.isSuperAdmin}',
    );

    Widget wrapTab(Widget section, int index) {
      if (!creditsLocked || index == settingsTab) {
        return section;
      }
      return CreditsLockedOverlay(
        locked: true,
        onTopUp: widget.onRecharge,
        child: section,
      );
    }

    final auth = d['auth'] as Map<String, dynamic>?;
    final portalUser = auth?['user'] as Map<String, dynamic>?;
    final hotelId =
        (portalUser?['hotel_id'] ?? portalUser?['hotelId'] ?? '').toString();

    final sections = <Widget>[
      wrapTab(
        RoomSummarySection(
          key: refreshKey,
          rooms: _rooms,
          tasks: tasks,
          hotelName: hotelName,
          localBookingsTotal: localTotal,
          onlineBookingsTotal: onlineTotal,
          recentBookings24h: recentBookings24h,
          pendingReservations: pendingReservationsStat,
          onRefresh: widget.onRefresh,
          onOpenLocalBookings: creditsLocked
              ? () => AdminCreditsGate.showActionsBlockedMessage(context)
              : () => _openBookingsTab('local'),
          onOpenOnlineBookings: creditsLocked
              ? () => AdminCreditsGate.showActionsBlockedMessage(context)
              : () => _openBookingsTab('online'),
          onOpenBookingsAlert: creditsLocked
              ? () => AdminCreditsGate.showActionsBlockedMessage(context)
              : () => _openBookingsTab('all'),
        ),
        0,
      ),
      wrapTab(CheckoutSection(key: refreshKey, rooms: _rooms), 1),
      wrapTab(GuestPortfolioSection(key: refreshKey, rooms: _rooms), 2),
      wrapTab(
        BookingsSection(
          key: ValueKey('bookings-$_bookingListFilter-${bookings.length}'),
          rooms: _rooms,
          reservations: reservations,
          bookings: bookings,
          bookingFilter: _bookingListFilter,
          onChanged: widget.onRefresh,
          currentCredits: creditAmount,
          onTopUpCredits: widget.onRecharge,
        ),
        3,
      ),
      wrapTab(
        ManualBookingSection(
          key: refreshKey,
          rooms: _rooms,
          hotelName: hotelName,
          onChanged: widget.onRefresh,
        ),
        4,
      ),
      wrapTab(
        AmenitiesSection(
          key: refreshKey,
          claims: claims,
          onAddProduct: widget.onAmenityAddProduct,
          onRefresh: widget.onRefresh,
        ),
        5,
      ),
      wrapTab(
        ResellersSection(
          key: refreshKey,
          onRefresh: widget.onRefresh,
        ),
        6,
      ),
      SettingsSection(
        creditBalance: balance,
        creditsLocked: creditsLocked,
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
        wrapTab(
          SuperAdminControlSection(
            key: refreshKey,
            onOpenAccountSettings: widget.onOpenAccountSettings,
          ),
          sections.length,
        ),
      );
    }

    return sections;
  }
}
