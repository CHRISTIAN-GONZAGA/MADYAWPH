import 'package:dio/dio.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../auth_storage.dart';
import '../../dio_client.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/chat_attachment.dart';
import '../public_hotel_search_screen.dart';
import '../portal_sign_out.dart';

const _kPlatformNavy = Color(0xFF1A2B4A);
const _kPlatformNavyDeep = Color(0xFF0F1A2E);
const _kPlatformGold = Color(0xFFD4A843);
const _kPlatformGoldLight = Color(0xFFF0D78C);

TextStyle _platformTitleStyle({double size = 18}) => TextStyle(
      color: Colors.white,
      fontSize: size,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.2,
    );

TextStyle _platformSubtitleStyle() => const TextStyle(
      color: Colors.white70,
      fontSize: 12,
      fontWeight: FontWeight.w500,
    );

/// Developer-only platform control panel (not hotel admin).
class CentralAdminDashboardScreen extends StatefulWidget {
  const CentralAdminDashboardScreen({super.key});

  @override
  State<CentralAdminDashboardScreen> createState() =>
      _CentralAdminDashboardScreenState();
}

class _CentralAdminDashboardScreenState extends State<CentralAdminDashboardScreen> {
  int _section = 0;
  String _revenuePeriod = 'month';
  String _guestsPeriod = 'month';
  int _approvalTab = 0;

  Map<String, dynamic>? _settings;
  Map<String, dynamic>? _revenue;
  Map<String, dynamic>? _guests;
  List<dynamic> _creditRequests = const [];
  List<dynamic> _memberRequests = const [];
  List<dynamic> _hotels = const [];
  bool _loading = true;
  String? _error;

  int get _pendingCredits => _creditRequests
      .whereType<Map<String, dynamic>>()
      .where((e) => (e['status'] ?? '') == 'pending')
      .length;

  int get _pendingMembers => _memberRequests
      .whereType<Map<String, dynamic>>()
      .where((e) => (e['status'] ?? '') == 'pending')
      .length;

  int get _depletedHotels => _hotels
      .whereType<Map<String, dynamic>>()
      .where((h) => h['is_depleted'] == true)
      .length;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        portalDio().get<Map<String, dynamic>>('/platform/settings'),
        portalDio().get<Map<String, dynamic>>(
          '/platform/revenue-analytics',
          queryParameters: {'period': _revenuePeriod},
        ),
        portalDio().get<Map<String, dynamic>>(
          '/platform/guest-demographics',
          queryParameters: {'period': _guestsPeriod},
        ),
        portalDio().get<Map<String, dynamic>>('/platform/credit-requests'),
        portalDio().get<Map<String, dynamic>>('/platform/member-requests'),
        portalDio().get<Map<String, dynamic>>('/platform/hotels'),
      ]);
      setState(() {
        _settings = results[0].data;
        _revenue = results[1].data;
        _guests = results[2].data;
        _creditRequests = (results[3].data?['data'] as List?) ?? const [];
        _memberRequests = (results[4].data?['data'] as List?) ?? const [];
        _hotels = (results[5].data?['data'] as List?) ?? const [];
        _loading = false;
      });
    } on DioException catch (e) {
      setState(() {
        _error = dioErrorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _reloadRevenue() async {
    try {
      final res = await portalDio().get<Map<String, dynamic>>(
        '/platform/revenue-analytics',
        queryParameters: {'period': _revenuePeriod},
      );
      if (mounted) setState(() => _revenue = res.data);
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  Future<void> _reloadGuests() async {
    try {
      final res = await portalDio().get<Map<String, dynamic>>(
        '/platform/guest-demographics',
        queryParameters: {'period': _guestsPeriod},
      );
      if (mounted) setState(() => _guests = res.data);
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  Future<void> _updateBookingFeePercent(double percent) async {
    try {
      await portalDio().patch<Map<String, dynamic>>(
        '/platform/settings/booking-fee-percent',
        data: {'booking_confirm_fee_percent': percent},
      );
      if (!mounted) return;
      showAppMessage(context, 'Booking fee percent updated.');
      await _loadAll();
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  Future<void> _updateMinCheckInPaymentPercent(double percent) async {
    try {
      await portalDio().patch<Map<String, dynamic>>(
        '/platform/settings/min-check-in-payment-percent',
        data: {'min_check_in_payment_percent': percent},
      );
      if (!mounted) return;
      showAppMessage(context, 'Minimum check-in payment percent updated.');
      await _loadAll();
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  Future<void> _updateLateCheckoutFee({
    required int graceMinutes,
    required double feeAmount,
  }) async {
    try {
      await portalDio().patch<Map<String, dynamic>>(
        '/platform/settings/late-checkout-fee',
        data: {
          'late_checkout_grace_minutes': graceMinutes,
          'late_checkout_fee_amount': feeAmount,
        },
      );
      if (!mounted) return;
      showAppMessage(context, 'Late check-out grace and fee updated.');
      await _loadAll();
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  Future<void> _updateEarlyCheckInFee({
    required int graceMinutes,
    required double feeAmount,
  }) async {
    try {
      await portalDio().patch<Map<String, dynamic>>(
        '/platform/settings/early-check-in-fee',
        data: {
          'early_check_in_grace_minutes': graceMinutes,
          'early_check_in_fee_amount': feeAmount,
        },
      );
      if (!mounted) return;
      showAppMessage(context, 'Early check-in grace and fee updated.');
      await _loadAll();
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  Future<void> _updateMemberBookingDiscountPercent(double percent) async {
    try {
      await portalDio().patch<Map<String, dynamic>>(
        '/platform/settings/member-booking-discount-percent',
        data: {'member_booking_discount_percent': percent},
      );
      if (!mounted) return;
      showAppMessage(context, 'Member booking discount updated.');
      await _loadAll();
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  Future<void> _updateMemberPointsSettings({
    required double pointsPerCheckIn,
    required double pointsPerPeso,
  }) async {
    try {
      await portalDio().patch<Map<String, dynamic>>(
        '/platform/settings/member-points',
        data: {
          'member_points_per_check_in': pointsPerCheckIn,
          'member_points_per_peso': pointsPerPeso,
        },
      );
      if (!mounted) return;
      showAppMessage(context, 'Member points settings updated.');
      await _loadAll();
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  Future<void> _uploadQr({required bool creditWallet}) async {
    final image = await ChatAttachment.pickRoomImageFromGallery(context);
    if (image == null || !mounted) return;
    try {
      final form = await ChatAttachment.formWithImage(
        fields: const <String, dynamic>{},
        file: image,
      );
      final path = creditWallet
          ? '/platform/settings/credit-wallet-qr'
          : '/platform/settings/member-qr';
      await portalDio().post(
        path,
        data: form,
        options: Options(contentType: 'multipart/form-data'),
      );
      if (!mounted) return;
      showAppMessage(context, 'QR image updated.');
      await _loadAll();
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  Future<void> _approveCredit(String id) async {
    HapticFeedback.lightImpact();
    try {
      await portalDio().post('/platform/credit-requests/$id/approve');
      await _loadAll();
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  Future<void> _rejectCredit(String id) async {
    try {
      await portalDio().post('/platform/credit-requests/$id/reject');
      await _loadAll();
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  Future<void> _approveMember(String id) async {
    HapticFeedback.lightImpact();
    try {
      await portalDio().post('/platform/member-requests/$id/approve');
      await _loadAll();
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  Future<void> _rejectMember(String id) async {
    try {
      await portalDio().post('/platform/member-requests/$id/reject');
      await _loadAll();
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  Future<void> _grantHotelCredits(String hotelId, String hotelName) async {
    final amountCtrl = TextEditingController(text: '5000');
    final reasonCtrl = TextEditingController(text: 'Platform credit top-up');

    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add credits — $hotelName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Amount (PHP)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
              if (amount <= 0) return;
              Navigator.pop(ctx, {
                'amount': amount,
                'reason': reasonCtrl.text.trim(),
              });
            },
            child: const Text('Grant credits'),
          ),
        ],
      ),
    );
    amountCtrl.dispose();
    reasonCtrl.dispose();
    if (payload == null) return;

    try {
      final res = await portalDio().post<Map<String, dynamic>>(
        '/platform/hotels/$hotelId/credits/grant',
        data: payload,
      );
      if (!mounted) return;
      final balance = res.data?['current_credits'];
      showAppMessage(context, 'Granted ₱${payload['amount']}. New balance: ₱$balance',);
      await _loadAll();
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  Future<void> _deleteHotel(String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete hotel?'),
        content: Text(
          'Permanently delete "$name" and all its rooms, bookings, and staff?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await portalDio().delete('/platform/hotels/$id');
      await AuthStorage.clearHotelsDirectoryCache();
      await _loadAll();
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  Future<void> _signOut() async {
    final confirmed = await confirmPortalSignOut(context);
    if (!confirmed || !mounted) return;
    await AuthStorage.clearPortalAuth();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const PublicHotelSearchScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendingTotal = _pendingCredits + _pendingMembers;

    return AppScaffold(
      appBar: AppBar(
        toolbarHeight: 76,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_kPlatformNavyDeep, _kPlatformNavy, Color(0xFF2D4A7A)],
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('MADYAWPH', style: _platformTitleStyle()),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _kPlatformGold.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _kPlatformGold.withValues(alpha: 0.55),
                    ),
                  ),
                  child: const Text(
                    'Platform control',
                    style: TextStyle(
                      color: _kPlatformGoldLight,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text('Central administration', style: _platformSubtitleStyle()),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadAll,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: _signOut,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _loadAll, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : IndexedStack(
                  index: _section,
                  children: [
                    _OverviewSection(
                      revenue: _revenue ?? const {},
                      guests: _guests ?? const {},
                      hotelCount: _hotels.length,
                      depletedHotels: _depletedHotels,
                      pendingCredits: _pendingCredits,
                      pendingMembers: _pendingMembers,
                      onOpenApprovals: () => setState(() => _section = 3),
                      onOpenRevenue: () => setState(() => _section = 1),
                      onOpenGuests: () => setState(() => _section = 2),
                      onOpenHotels: () => setState(() => _section = 5),
                    ),
                    _RevenueSection(
                      revenue: _revenue ?? const {},
                      period: _revenuePeriod,
                      onPeriodChanged: (p) {
                        setState(() => _revenuePeriod = p);
                        _reloadRevenue();
                      },
                    ),
                    _GuestsSection(
                      guests: _guests ?? const {},
                      period: _guestsPeriod,
                      onPeriodChanged: (p) {
                        setState(() => _guestsPeriod = p);
                        _reloadGuests();
                      },
                    ),
                    _ApprovalsSection(
                      tab: _approvalTab,
                      onTabChanged: (i) => setState(() => _approvalTab = i),
                      creditRequests: _creditRequests,
                      memberRequests: _memberRequests,
                      onApproveCredit: _approveCredit,
                      onRejectCredit: _rejectCredit,
                      onApproveMember: _approveMember,
                      onRejectMember: _rejectMember,
                    ),
                    _QrSettingsSection(
                      settings: _settings ?? const {},
                      onUploadCredit: () => _uploadQr(creditWallet: true),
                      onUploadMember: () => _uploadQr(creditWallet: false),
                      onUpdateBookingFeePercent: _updateBookingFeePercent,
                      onUpdateMinCheckInPaymentPercent:
                          _updateMinCheckInPaymentPercent,
                      onUpdateLateCheckoutFee: _updateLateCheckoutFee,
                      onUpdateEarlyCheckInFee: _updateEarlyCheckInFee,
                      onUpdateMemberBookingDiscountPercent:
                          _updateMemberBookingDiscountPercent,
                      onUpdateMemberPointsSettings: _updateMemberPointsSettings,
                    ),
                    _HotelsSection(
                      hotels: _hotels,
                      onDelete: _deleteHotel,
                      onGrantCredits: _grantHotelCredits,
                    ),
                  ],
                ),
      bottomNavigationBar: Theme(
        data: Theme.of(context).copyWith(
          navigationBarTheme: NavigationBarThemeData(
            height: 68,
            backgroundColor: Colors.white,
            indicatorColor: _kPlatformGold.withValues(alpha: 0.28),
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              final selected = states.contains(WidgetState.selected);
              return TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                color: selected ? _kPlatformNavy : Colors.black54,
              );
            }),
            iconTheme: WidgetStateProperty.resolveWith((states) {
              final selected = states.contains(WidgetState.selected);
              return IconThemeData(
                color: selected ? _kPlatformNavy : Colors.black45,
                size: 22,
              );
            }),
          ),
        ),
        child: NavigationBar(
        selectedIndex: _section,
        onDestinationSelected: (i) => setState(() => _section = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Overview',
          ),
          const NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Revenue',
          ),
          const NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups),
            label: 'Guests',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: pendingTotal > 0,
              label: Text('$pendingTotal'),
              child: const Icon(Icons.pending_actions_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: pendingTotal > 0,
              label: Text('$pendingTotal'),
              child: const Icon(Icons.pending_actions),
            ),
            label: 'Approvals',
          ),
          const NavigationDestination(
            icon: Icon(Icons.qr_code_2_outlined),
            selectedIcon: Icon(Icons.qr_code_2),
            label: 'QR',
          ),
          const NavigationDestination(
            icon: Icon(Icons.apartment_outlined),
            selectedIcon: Icon(Icons.apartment),
            label: 'Hotels',
          ),
        ],
        ),
      ),
    );
  }
}

class _PlatformSectionHeader extends StatelessWidget {
  const _PlatformSectionHeader({
    required this.title,
    this.subtitle,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kPlatformNavy, Color(0xFF2D4A7A)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _kPlatformNavy.withValues(alpha: 0.22),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _kPlatformGold.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: _kPlatformGoldLight, size: 22),
            ),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: _platformTitleStyle(size: 17),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: _platformSubtitleStyle()),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewSection extends StatelessWidget {
  const _OverviewSection({
    required this.revenue,
    required this.guests,
    required this.hotelCount,
    required this.depletedHotels,
    required this.pendingCredits,
    required this.pendingMembers,
    required this.onOpenApprovals,
    required this.onOpenRevenue,
    required this.onOpenGuests,
    required this.onOpenHotels,
  });

  final Map<String, dynamic> revenue;
  final Map<String, dynamic> guests;
  final int hotelCount;
  final int depletedHotels;
  final int pendingCredits;
  final int pendingMembers;
  final VoidCallback onOpenApprovals;
  final VoidCallback onOpenRevenue;
  final VoidCallback onOpenGuests;
  final VoidCallback onOpenHotels;

  @override
  Widget build(BuildContext context) {
    final totals = revenue['totals'] as Map<String, dynamic>? ?? {};
    final guestTotals = guests['totals'] as Map<String, dynamic>? ?? {};
    final period = (revenue['period'] ?? 'month').toString();

    return ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _PlatformSectionHeader(
            icon: Icons.dashboard_outlined,
            title: 'Overview',
            subtitle: 'This $period at a glance',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Key metrics',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: _kPlatformNavy,
                  ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child:
          LayoutBuilder(
            builder: (context, constraints) {
              final w = (constraints.maxWidth - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: w,
                    child: _KpiTile(
                      label: 'Hotel net revenue',
                      value: '₱${_fmt(totals['hotel_net_revenue'])}',
                      icon: Icons.payments_outlined,
                      color: _kPlatformNavy,
                    ),
                  ),
                  SizedBox(
                    width: w,
                    child: _KpiTile(
                      label: 'Platform revenue',
                      value: '₱${_fmt(totals['platform_revenue'])}',
                      icon: Icons.account_balance_wallet_outlined,
                      color: _kPlatformGold,
                    ),
                  ),
                  SizedBox(
                    width: w,
                    child: _KpiTile(
                      label: 'Paid bookings',
                      value: '${totals['paid_bookings'] ?? 0}',
                      icon: Icons.book_online_outlined,
                      color: Colors.teal.shade700,
                    ),
                  ),
                  SizedBox(
                    width: w,
                    child: _KpiTile(
                      label: 'Active hotels',
                      value: '$hotelCount',
                      icon: Icons.apartment_outlined,
                      color: Colors.indigo,
                    ),
                  ),
                ],
              );
            },
          ),
          ),
          const SizedBox(height: 20),
          if (pendingCredits > 0 || pendingMembers > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
              color: Colors.orange.shade50,
              child: ListTile(
                leading: const Icon(Icons.notifications_active_outlined),
                title: Text(
                  '${pendingCredits + pendingMembers} approval(s) waiting',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '$pendingCredits credit · $pendingMembers member',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: onOpenApprovals,
              ),
            ),
            ),
          if (depletedHotels > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                color: Colors.red.shade50,
                child: ListTile(
                  leading: Icon(Icons.warning_amber_outlined,
                      color: Colors.red.shade800),
                  title: Text(
                    '$depletedHotels hotel(s) out of credits',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text('Grant credits from the Hotels tab'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onOpenHotels,
                ),
              ),
            ),
          if (depletedHotels > 0) const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: _kPlatformGold.withValues(alpha: 0.2),
                  child: const Icon(Icons.insights_outlined, color: _kPlatformNavy),
                ),
                title: const Text(
                  'Revenue by hotel',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text('See breakdown for every property'),
                trailing: const Icon(Icons.chevron_right),
                onTap: onOpenRevenue,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.teal.withValues(alpha: 0.15),
                  child: Icon(Icons.groups_outlined, color: Colors.teal.shade800),
                ),
                title: const Text(
                  'Guest demographics',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '${guestTotals['total_guests'] ?? 0} guests · '
                  '${guestTotals['bookings'] ?? 0} bookings',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: onOpenGuests,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: _kPlatformNavy.withValues(alpha: 0.12),
                  child: const Icon(Icons.apartment_outlined, color: _kPlatformNavy),
                ),
                title: const Text(
                  'Manage hotels & credits',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text('$hotelCount registered properties'),
                trailing: const Icon(Icons.chevron_right),
                onTap: onOpenHotels,
              ),
            ),
          ),
        ],
    );
  }

  static String _fmt(Object? v) {
    final n = (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0;
    return n >= 1000 ? n.toStringAsFixed(0) : n.toStringAsFixed(2);
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 12),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RevenueSection extends StatelessWidget {
  const _RevenueSection({
    required this.revenue,
    required this.period,
    required this.onPeriodChanged,
  });

  final Map<String, dynamic> revenue;
  final String period;
  final ValueChanged<String> onPeriodChanged;

  @override
  Widget build(BuildContext context) {
    final totals = revenue['totals'] as Map<String, dynamic>? ?? {};
    final hotels = (revenue['hotels'] as List<dynamic>?) ?? const [];
    final from = (revenue['from'] ?? '').toString();
    final to = (revenue['to'] ?? '').toString();

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _PlatformSectionHeader(
          icon: Icons.insights_outlined,
          title: 'Revenue analytics',
          subtitle: from.isNotEmpty ? '$from → $to' : 'Track earnings by hotel',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: _PeriodSegmentedButton(
            period: period,
            onPeriodChanged: onPeriodChanged,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _TotalRow(label: 'Hotel gross', value: totals['hotel_gross_revenue']),
                  _TotalRow(label: 'Hotel net', value: totals['hotel_net_revenue'], bold: true),
                  const Divider(height: 20),
                  _TotalRow(label: 'Credit top-ups (approved)', value: totals['credit_topups_approved']),
                  _TotalRow(label: 'Member subscriptions', value: totals['member_subscriptions_approved']),
                  _TotalRow(label: 'Total platform revenue', value: totals['platform_revenue'], bold: true),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'By hotel',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: _kPlatformNavy,
                ),
          ),
        ),
        if (hotels.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 24, 16, 24),
            child: Center(child: Text('No hotel revenue in this period.')),
          )
        else
          ...List.generate(hotels.length, (i) {
            final h = hotels[i] as Map<String, dynamic>;
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (h['hotel_name'] ?? 'Hotel').toString(),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      if ((h['city'] ?? '').toString().isNotEmpty)
                        Text(
                          (h['city'] ?? '').toString(),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _MiniStat(
                              label: 'Net',
                              value: '₱${h['net_revenue']}',
                            ),
                          ),
                          Expanded(
                            child: _MiniStat(
                              label: 'Room',
                              value: '₱${h['room_revenue']}',
                            ),
                          ),
                          Expanded(
                            child: _MiniStat(
                              label: 'Bookings',
                              value: '${h['paid_bookings']}',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}

class _GuestsSection extends StatelessWidget {
  const _GuestsSection({
    required this.guests,
    required this.period,
    required this.onPeriodChanged,
  });

  final Map<String, dynamic> guests;
  final String period;
  final ValueChanged<String> onPeriodChanged;

  @override
  Widget build(BuildContext context) {
    final totals = guests['totals'] as Map<String, dynamic>? ?? {};
    final nationalities = (guests['nationalities'] as List<dynamic>?) ?? const [];
    final hotels = (guests['hotels'] as List<dynamic>?) ?? const [];
    final from = (guests['from'] ?? '').toString();
    final to = (guests['to'] ?? '').toString();

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _PlatformSectionHeader(
          icon: Icons.groups_outlined,
          title: 'Guest demographics',
          subtitle: from.isNotEmpty ? '$from → $to' : 'Guests by gender and nationality',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: _PeriodSegmentedButton(
            period: period,
            onPeriodChanged: onPeriodChanged,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _CountRow(label: 'Male', value: totals['male']),
                  _CountRow(label: 'Female', value: totals['female']),
                  _CountRow(
                    label: 'Total guests',
                    value: totals['total_guests'],
                    bold: true,
                  ),
                  const Divider(height: 20),
                  _CountRow(label: 'Bookings', value: totals['bookings']),
                ],
              ),
            ),
          ),
        ),
        if (nationalities.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Nationalities',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: _kPlatformNavy,
                  ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    for (final raw in nationalities)
                      if (raw is Map<String, dynamic>)
                        _CountRow(
                          label: (raw['label'] ?? 'Unknown').toString(),
                          value: raw['guests'],
                        ),
                  ],
                ),
              ),
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'By hotel',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: _kPlatformNavy,
                ),
          ),
        ),
        if (hotels.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 24, 16, 24),
            child: Center(child: Text('No guest data in this period.')),
          )
        else
          ...List.generate(hotels.length, (i) {
            final h = hotels[i] as Map<String, dynamic>;
            final hotelNats =
                (h['nationalities'] as List<dynamic>?) ?? const [];
            final topNats = hotelNats
                .whereType<Map<String, dynamic>>()
                .take(3)
                .map((n) =>
                    '${n['label'] ?? 'Unknown'} (${n['guests'] ?? 0})')
                .join(' · ');
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (h['hotel_name'] ?? 'Hotel').toString(),
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      if ((h['city'] ?? '').toString().isNotEmpty)
                        Text(
                          (h['city'] ?? '').toString(),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _MiniStat(
                              label: 'Male',
                              value: '${h['male'] ?? 0}',
                            ),
                          ),
                          Expanded(
                            child: _MiniStat(
                              label: 'Female',
                              value: '${h['female'] ?? 0}',
                            ),
                          ),
                          Expanded(
                            child: _MiniStat(
                              label: 'Total',
                              value: '${h['total_guests'] ?? 0}',
                            ),
                          ),
                        ],
                      ),
                      if (topNats.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          topNats,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}

class _CountRow extends StatelessWidget {
  const _CountRow({required this.label, required this.value, this.bold = false});

  final String label;
  final Object? value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            '${value ?? 0}',
            style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.value, this.bold = false});

  final String label;
  final Object? value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            '₱${(value is num) ? value : double.tryParse('$value') ?? 0}',
            style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _ApprovalsSection extends StatelessWidget {
  const _ApprovalsSection({
    required this.tab,
    required this.onTabChanged,
    required this.creditRequests,
    required this.memberRequests,
    required this.onApproveCredit,
    required this.onRejectCredit,
    required this.onApproveMember,
    required this.onRejectMember,
  });

  final int tab;
  final ValueChanged<int> onTabChanged;
  final List<dynamic> creditRequests;
  final List<dynamic> memberRequests;
  final void Function(String id) onApproveCredit;
  final void Function(String id) onRejectCredit;
  final void Function(String id) onApproveMember;
  final void Function(String id) onRejectMember;

  @override
  Widget build(BuildContext context) {
    final list = tab == 0 ? creditRequests : memberRequests;
    final pending = list
        .whereType<Map<String, dynamic>>()
        .where((e) => (e['status'] ?? '') == 'pending')
        .toList();

    return Column(
      children: [
        _PlatformSectionHeader(
          icon: Icons.pending_actions_outlined,
          title: 'Approvals',
          subtitle: 'Credit top-ups and member subscriptions',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Credit wallet')),
              ButtonSegment(value: 1, label: Text('Members')),
            ],
            selected: {tab},
            onSelectionChanged: (s) => onTabChanged(s.first),
          ),
        ),
        Expanded(
          child: pending.isEmpty
              ? Center(
                  child: Text(
                    tab == 0
                        ? 'No pending credit top-ups.'
                        : 'No pending member requests.',
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: pending.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final item = pending[i];
                    if (tab == 0) {
                      return _CreditCard(
                        item: item,
                        onApprove: () => onApproveCredit((item['id'] ?? '').toString()),
                        onReject: () => onRejectCredit((item['id'] ?? '').toString()),
                      );
                    }
                    return _MemberCard(
                      item: item,
                      onApprove: () => onApproveMember((item['id'] ?? '').toString()),
                      onReject: () => onRejectMember((item['id'] ?? '').toString()),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _CreditCard extends StatelessWidget {
  const _CreditCard({
    required this.item,
    required this.onApprove,
    required this.onReject,
  });

  final Map<String, dynamic> item;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: _kPlatformNavy.withValues(alpha: 0.12),
                  child: const Icon(Icons.account_balance_wallet_outlined, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (item['hotel_name'] ?? 'Hotel').toString(),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text('₱${item['amount']} top-up'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Ref: ${item['payment_reference']}'),
            Text('Requested by: ${item['requested_by_name'] ?? '—'}'),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: onReject, child: const Text('Reject'))),
                const SizedBox(width: 10),
                Expanded(child: FilledButton(onPressed: onApprove, child: const Text('Approve'))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.item,
    required this.onApprove,
    required this.onReject,
  });

  final Map<String, dynamic> item;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: _kPlatformGold.withValues(alpha: 0.2),
                  child: const Icon(Icons.workspace_premium_outlined, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (item['full_name'] ?? 'Member').toString(),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text('₱${item['amount']} / month'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(item['email']?.toString() ?? ''),
            Text(item['phone']?.toString() ?? ''),
            Text('Ref: ${item['payment_reference']}'),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: onReject, child: const Text('Reject'))),
                const SizedBox(width: 10),
                Expanded(child: FilledButton(onPressed: onApprove, child: const Text('Approve'))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QrSettingsSection extends StatefulWidget {
  const _QrSettingsSection({
    required this.settings,
    required this.onUploadCredit,
    required this.onUploadMember,
    required this.onUpdateBookingFeePercent,
    required this.onUpdateMinCheckInPaymentPercent,
    required this.onUpdateLateCheckoutFee,
    required this.onUpdateEarlyCheckInFee,
    required this.onUpdateMemberBookingDiscountPercent,
    required this.onUpdateMemberPointsSettings,
  });

  final Map<String, dynamic> settings;
  final VoidCallback onUploadCredit;
  final VoidCallback onUploadMember;
  final Future<void> Function(double percent) onUpdateBookingFeePercent;
  final Future<void> Function(double percent) onUpdateMinCheckInPaymentPercent;
  final Future<void> Function({
    required int graceMinutes,
    required double feeAmount,
  }) onUpdateLateCheckoutFee;
  final Future<void> Function({
    required int graceMinutes,
    required double feeAmount,
  }) onUpdateEarlyCheckInFee;
  final Future<void> Function(double percent) onUpdateMemberBookingDiscountPercent;
  final Future<void> Function({
    required double pointsPerCheckIn,
    required double pointsPerPeso,
  }) onUpdateMemberPointsSettings;

  @override
  State<_QrSettingsSection> createState() => _QrSettingsSectionState();
}

class _QrSettingsSectionState extends State<_QrSettingsSection> {
  late final TextEditingController _feePercentCtrl;
  late final TextEditingController _minCheckInPercentCtrl;
  late final TextEditingController _lateGraceCtrl;
  late final TextEditingController _lateFeeCtrl;
  late final TextEditingController _earlyGraceCtrl;
  late final TextEditingController _earlyFeeCtrl;
  late final TextEditingController _memberDiscountCtrl;
  late final TextEditingController _pointsPerCheckInCtrl;
  late final TextEditingController _pointsPerPesoCtrl;
  var _savingFee = false;
  var _savingMinCheckIn = false;
  var _savingLateCheckout = false;
  var _savingEarlyCheckIn = false;
  var _savingMemberDiscount = false;
  var _savingMemberPoints = false;

  @override
  void initState() {
    super.initState();
    _feePercentCtrl = TextEditingController(
      text: _feePercentText(widget.settings),
    );
    _minCheckInPercentCtrl = TextEditingController(
      text: _minCheckInPercentText(widget.settings),
    );
    _lateGraceCtrl = TextEditingController(
      text: _lateGraceText(widget.settings),
    );
    _lateFeeCtrl = TextEditingController(
      text: _lateFeeText(widget.settings),
    );
    _earlyGraceCtrl = TextEditingController(
      text: _earlyGraceText(widget.settings),
    );
    _earlyFeeCtrl = TextEditingController(
      text: _earlyFeeText(widget.settings),
    );
    _memberDiscountCtrl = TextEditingController(
      text: _memberDiscountText(widget.settings),
    );
    _pointsPerCheckInCtrl = TextEditingController(
      text: _pointsPerCheckInText(widget.settings),
    );
    _pointsPerPesoCtrl = TextEditingController(
      text: _pointsPerPesoText(widget.settings),
    );
  }

  @override
  void didUpdateWidget(covariant _QrSettingsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _feePercentText(widget.settings);
    if (next != _feePercentCtrl.text) {
      _feePercentCtrl.text = next;
    }
    final minCheckIn = _minCheckInPercentText(widget.settings);
    if (minCheckIn != _minCheckInPercentCtrl.text) {
      _minCheckInPercentCtrl.text = minCheckIn;
    }
    final lateGrace = _lateGraceText(widget.settings);
    if (lateGrace != _lateGraceCtrl.text) {
      _lateGraceCtrl.text = lateGrace;
    }
    final lateFee = _lateFeeText(widget.settings);
    if (lateFee != _lateFeeCtrl.text) {
      _lateFeeCtrl.text = lateFee;
    }
    final earlyGrace = _earlyGraceText(widget.settings);
    if (earlyGrace != _earlyGraceCtrl.text) {
      _earlyGraceCtrl.text = earlyGrace;
    }
    final earlyFee = _earlyFeeText(widget.settings);
    if (earlyFee != _earlyFeeCtrl.text) {
      _earlyFeeCtrl.text = earlyFee;
    }
    final memberNext = _memberDiscountText(widget.settings);
    if (memberNext != _memberDiscountCtrl.text) {
      _memberDiscountCtrl.text = memberNext;
    }
    final ptsCheckIn = _pointsPerCheckInText(widget.settings);
    if (ptsCheckIn != _pointsPerCheckInCtrl.text) {
      _pointsPerCheckInCtrl.text = ptsCheckIn;
    }
    final ptsPeso = _pointsPerPesoText(widget.settings);
    if (ptsPeso != _pointsPerPesoCtrl.text) {
      _pointsPerPesoCtrl.text = ptsPeso;
    }
  }

  @override
  void dispose() {
    _feePercentCtrl.dispose();
    _minCheckInPercentCtrl.dispose();
    _lateGraceCtrl.dispose();
    _lateFeeCtrl.dispose();
    _earlyGraceCtrl.dispose();
    _earlyFeeCtrl.dispose();
    _memberDiscountCtrl.dispose();
    _pointsPerCheckInCtrl.dispose();
    _pointsPerPesoCtrl.dispose();
    super.dispose();
  }

  static String _feePercentText(Map<String, dynamic> settings) {
    final raw = settings['booking_confirm_fee_percent'];
    if (raw == null) return '8';
    return (raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 8)
        .toStringAsFixed(raw is num && raw % 1 == 0 ? 0 : 1);
  }

  static String _minCheckInPercentText(Map<String, dynamic> settings) {
    final raw = settings['min_check_in_payment_percent'];
    if (raw == null) return '50';
    return (raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 50)
        .toStringAsFixed(raw is num && raw % 1 == 0 ? 0 : 1);
  }

  static String _lateGraceText(Map<String, dynamic> settings) {
    final raw = settings['late_checkout_grace_minutes'];
    if (raw == null) return '15';
    return '${raw is num ? raw.toInt() : int.tryParse('$raw') ?? 15}';
  }

  static String _lateFeeText(Map<String, dynamic> settings) {
    final raw = settings['late_checkout_fee_amount'];
    if (raw == null) return '500';
    final value = raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 500;
    return value == value.roundToDouble()
        ? '${value.toInt()}'
        : value.toStringAsFixed(2);
  }

  static String _earlyGraceText(Map<String, dynamic> settings) {
    final raw = settings['early_check_in_grace_minutes'];
    if (raw == null) return '15';
    return '${raw is num ? raw.toInt() : int.tryParse('$raw') ?? 15}';
  }

  static String _earlyFeeText(Map<String, dynamic> settings) {
    final raw = settings['early_check_in_fee_amount'];
    if (raw == null) return '500';
    final value = raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 500;
    return value == value.roundToDouble()
        ? '${value.toInt()}'
        : value.toStringAsFixed(2);
  }

  static String _memberDiscountText(Map<String, dynamic> settings) {
    final raw = settings['member_booking_discount_percent'];
    if (raw == null) return '10';
    return (raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 10)
        .toStringAsFixed(raw is num && raw % 1 == 0 ? 0 : 1);
  }

  static String _pointsPerCheckInText(Map<String, dynamic> settings) {
    final raw = settings['member_points_per_check_in'];
    if (raw == null) return '1000';
    return (raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 1000)
        .toStringAsFixed(0);
  }

  static String _pointsPerPesoText(Map<String, dynamic> settings) {
    final raw = settings['member_points_per_peso'];
    if (raw == null) return '10';
    return (raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 10)
        .toStringAsFixed(raw is num && raw % 1 == 0 ? 0 : 2);
  }

  Future<void> _saveMemberDiscountPercent() async {
    final parsed = double.tryParse(_memberDiscountCtrl.text.trim());
    if (parsed == null || parsed < 0 || parsed > 100) {
      showAppMessage(context, 'Enter a discount between 0 and 100.');
      return;
    }
    setState(() => _savingMemberDiscount = true);
    try {
      await widget.onUpdateMemberBookingDiscountPercent(parsed);
    } finally {
      if (mounted) setState(() => _savingMemberDiscount = false);
    }
  }

  Future<void> _saveMemberPoints() async {
    final checkIn = double.tryParse(_pointsPerCheckInCtrl.text.trim());
    final perPeso = double.tryParse(_pointsPerPesoCtrl.text.trim());
    if (checkIn == null || checkIn < 0) {
      showAppMessage(context, 'Enter a valid booking points amount.');
      return;
    }
    if (perPeso == null || perPeso <= 0) {
      showAppMessage(context, 'Points per peso must be greater than 0.');
      return;
    }
    setState(() => _savingMemberPoints = true);
    try {
      await widget.onUpdateMemberPointsSettings(
        pointsPerCheckIn: checkIn,
        pointsPerPeso: perPeso,
      );
    } finally {
      if (mounted) setState(() => _savingMemberPoints = false);
    }
  }

  Future<void> _saveFeePercent() async {
    final parsed = double.tryParse(_feePercentCtrl.text.trim());
    if (parsed == null || parsed < 0 || parsed > 100) {
      showAppMessage(context, 'Enter a fee between 0 and 100.');
      return;
    }
    setState(() => _savingFee = true);
    try {
      await widget.onUpdateBookingFeePercent(parsed);
    } finally {
      if (mounted) setState(() => _savingFee = false);
    }
  }

  Future<void> _saveMinCheckInPercent() async {
    final parsed = double.tryParse(_minCheckInPercentCtrl.text.trim());
    if (parsed == null || parsed < 0 || parsed > 100) {
      showAppMessage(context, 'Enter a percent between 0 and 100.');
      return;
    }
    setState(() => _savingMinCheckIn = true);
    try {
      await widget.onUpdateMinCheckInPaymentPercent(parsed);
    } finally {
      if (mounted) setState(() => _savingMinCheckIn = false);
    }
  }

  Future<void> _saveLateCheckoutFee() async {
    final grace = int.tryParse(_lateGraceCtrl.text.trim());
    final fee = double.tryParse(_lateFeeCtrl.text.trim());
    if (grace == null || grace < 0 || grace > 720) {
      showAppMessage(context, 'Enter grace minutes from 0 to 720.');
      return;
    }
    if (fee == null || fee < 0) {
      showAppMessage(context, 'Enter a fee amount of 0 or more.');
      return;
    }
    setState(() => _savingLateCheckout = true);
    try {
      await widget.onUpdateLateCheckoutFee(
        graceMinutes: grace,
        feeAmount: fee,
      );
    } finally {
      if (mounted) setState(() => _savingLateCheckout = false);
    }
  }

  Future<void> _saveEarlyCheckInFee() async {
    final grace = int.tryParse(_earlyGraceCtrl.text.trim());
    final fee = double.tryParse(_earlyFeeCtrl.text.trim());
    if (grace == null || grace < 0 || grace > 720) {
      showAppMessage(context, 'Enter grace minutes from 0 to 720.');
      return;
    }
    if (fee == null || fee < 0) {
      showAppMessage(context, 'Enter a fee amount of 0 or more.');
      return;
    }
    setState(() => _savingEarlyCheckIn = true);
    try {
      await widget.onUpdateEarlyCheckInFee(
        graceMinutes: grace,
        feeAmount: fee,
      );
    } finally {
      if (mounted) setState(() => _savingEarlyCheckIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final creditQr = ChatAttachment.resolveMediaUrl(
      (widget.settings['credit_wallet_qr_url'] ?? '').toString(),
    );
    final memberQr = ChatAttachment.resolveMediaUrl(
      (widget.settings['member_subscription_qr_url'] ?? '').toString(),
    );

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const _PlatformSectionHeader(
          icon: Icons.qr_code_2_outlined,
          title: 'QR Ph images',
          subtitle: 'Hotels and guests scan these for credits or membership',
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Upload payment QR codes',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: _kPlatformNavy,
                ),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              _QrUploadCard(
                title: 'Hotel credit wallet',
                subtitle: 'Used when hotels request credit top-ups.',
                imageUrl: creditQr,
                onUpload: widget.onUploadCredit,
              ),
              const SizedBox(height: 16),
              _QrUploadCard(
                title: 'Become a member',
                subtitle:
                    'Guests pay ₱${widget.settings['member_monthly_fee'] ?? 300}/month.',
                imageUrl: memberQr,
                onUpload: widget.onUploadMember,
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Booking confirmation fee',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Deducted from a hotel\'s credit wallet when a walk-in or public customer booking is confirmed.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _feePercentCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Fee percent',
                          suffixText: '%',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _savingFee ? null : _saveFeePercent,
                        style: FilledButton.styleFrom(
                          backgroundColor: _kPlatformNavy,
                          foregroundColor: Colors.white,
                        ),
                        icon: _savingFee
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(_savingFee ? 'Saving…' : 'Save fee percent'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Minimum check-in payment',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'When front desk checks a guest in, they must collect at least this percent of the remaining room balance (for example 50). The payment is deducted from the room bill.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _minCheckInPercentCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Minimum percent at check-in',
                          suffixText: '%',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed:
                            _savingMinCheckIn ? null : _saveMinCheckInPercent,
                        style: FilledButton.styleFrom(
                          backgroundColor: _kPlatformNavy,
                          foregroundColor: Colors.white,
                        ),
                        icon: _savingMinCheckIn
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(
                          _savingMinCheckIn
                              ? 'Saving…'
                              : 'Save check-in payment %',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Early check-in fee',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Default for all hotels (nightly rooms). Standard check-in is 3:00 PM. Arriving before 3:00 PM minus this grace period charges the fee. Hotels can override in Settings.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _earlyGraceCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Grace period',
                          suffixText: 'minutes',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _earlyFeeCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Early check-in fee',
                          prefixText: '₱ ',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed:
                            _savingEarlyCheckIn ? null : _saveEarlyCheckInFee,
                        style: FilledButton.styleFrom(
                          backgroundColor: _kPlatformNavy,
                          foregroundColor: Colors.white,
                        ),
                        icon: _savingEarlyCheckIn
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(
                          _savingEarlyCheckIn
                              ? 'Saving…'
                              : 'Save early check-in settings',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Late check-out fee',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Default for all hotels. A guest who leaves after scheduled check-out plus this grace period is charged the fee. Hotels can override in Settings.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _lateGraceCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Grace period',
                          suffixText: 'minutes',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _lateFeeCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Late check-out fee',
                          prefixText: '₱ ',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed:
                            _savingLateCheckout ? null : _saveLateCheckoutFee,
                        style: FilledButton.styleFrom(
                          backgroundColor: _kPlatformNavy,
                          foregroundColor: Colors.white,
                        ),
                        icon: _savingLateCheckout
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(
                          _savingLateCheckout
                              ? 'Saving…'
                              : 'Save late check-out settings',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Member room booking discount',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Applied when a signed-in member books in the customer app, or when hotel staff scan a membership QR / enter SHID on a walk-in.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _memberDiscountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Discount percent',
                          suffixText: '%',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed:
                            _savingMemberDiscount ? null : _saveMemberDiscountPercent,
                        style: FilledButton.styleFrom(
                          backgroundColor: _kPlatformNavy,
                          foregroundColor: Colors.white,
                        ),
                        icon: _savingMemberDiscount
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(
                          _savingMemberDiscount ? 'Saving…' : 'Save member discount',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Member points wallet',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Members earn points on every successful booking. Hotels can redeem points when scanning a member QR; the peso value is added to that hotel’s credit wallet.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _pointsPerCheckInCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Points per successful booking',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _pointsPerPesoCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Points per ₱1',
                          helperText: 'Default 10 → 1000 points = ₱100',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _savingMemberPoints ? null : _saveMemberPoints,
                        style: FilledButton.styleFrom(
                          backgroundColor: _kPlatformNavy,
                          foregroundColor: Colors.white,
                        ),
                        icon: _savingMemberPoints
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(
                          _savingMemberPoints ? 'Saving…' : 'Save points settings',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QrUploadCard extends StatelessWidget {
  const _QrUploadCard({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.onUpload,
  });

  final String title;
  final String subtitle;
  final String imageUrl;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 1,
                child: imageUrl.isEmpty
                    ? ColoredBox(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.qr_code_2, size: 56),
                      )
                    : NetworkMediaImage(url: imageUrl, fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onUpload,
              style: FilledButton.styleFrom(
                backgroundColor: _kPlatformNavy,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.upload_outlined),
              label: const Text('Upload QR Ph'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HotelsSection extends StatefulWidget {
  const _HotelsSection({
    required this.hotels,
    required this.onDelete,
    required this.onGrantCredits,
  });

  final List<dynamic> hotels;
  final Future<void> Function(String id, String name) onDelete;
  final Future<void> Function(String id, String name) onGrantCredits;

  @override
  State<_HotelsSection> createState() => _HotelsSectionState();
}

class _HotelsSectionState extends State<_HotelsSection> {
  String _query = '';

  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim().toLowerCase();
    return widget.hotels
        .whereType<Map<String, dynamic>>()
        .where((h) {
          if (q.isEmpty) return true;
          final name = (h['name'] ?? '').toString().toLowerCase();
          final city = (h['city'] ?? h['location'] ?? '').toString().toLowerCase();
          return name.contains(q) || city.contains(q);
        })
        .toList();
  }

  double get _totalCredits => widget.hotels
      .whereType<Map<String, dynamic>>()
      .fold<double>(
        0,
        (sum, h) => sum + ((h['current_credits'] as num?)?.toDouble() ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final depleted = widget.hotels
        .whereType<Map<String, dynamic>>()
        .where((h) => h['is_depleted'] == true)
        .length;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const _PlatformSectionHeader(
          icon: Icons.apartment_outlined,
          title: 'Hotels',
          subtitle: 'Credits, search, and property management',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: _MiniStatChip(
                  label: 'Properties',
                  value: '${widget.hotels.length}',
                  icon: Icons.apartment_outlined,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniStatChip(
                  label: 'Total credits',
                  value: '₱${_fmtCredits(_totalCredits)}',
                  icon: Icons.account_balance_wallet_outlined,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniStatChip(
                  label: 'Depleted',
                  value: '$depleted',
                  icon: Icons.warning_amber_outlined,
                  warn: depleted > 0,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search hotels…',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        const SizedBox(height: 8),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 32, 16, 24),
            child: Center(
              child: Text(
                widget.hotels.isEmpty
                    ? 'No hotels registered.'
                    : 'No hotels match your search.',
              ),
            ),
          )
        else
          ...filtered.map((h) {
            final id = (h['id'] ?? '').toString();
            final name = (h['name'] ?? 'Hotel').toString();
            final credits =
                (h['current_credits'] as num?)?.toDouble() ?? 0;
            final isDepleted = h['is_depleted'] == true;
            final isLow = h['is_low_balance'] == true;

            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor:
                                _kPlatformNavy.withValues(alpha: 0.12),
                            foregroundColor: _kPlatformNavy,
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  (h['city'] ?? h['location'] ?? '')
                                      .toString(),
                                  style:
                                      Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          if (isDepleted)
                            _StatusPill(
                              label: 'Empty',
                              color: Colors.red.shade700,
                            )
                          else if (isLow)
                            _StatusPill(
                              label: 'Low',
                              color: Colors.orange.shade800,
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(Icons.payments_outlined,
                              size: 18, color: _kPlatformGold),
                          const SizedBox(width: 6),
                          Text(
                            '₱${_fmtCredits(credits)} credits',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  widget.onGrantCredits(id, name),
                              icon: const Icon(Icons.add_circle_outline),
                              label: const Text('Add credits'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Delete hotel',
                            onPressed: () => widget.onDelete(id, name),
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }

  static String _fmtCredits(double n) {
    if (n >= 1000) return n.toStringAsFixed(0);
    return n.toStringAsFixed(2);
  }
}

class _PeriodSegmentedButton extends StatelessWidget {
  const _PeriodSegmentedButton({
    required this.period,
    required this.onPeriodChanged,
  });

  final String period;
  final ValueChanged<String> onPeriodChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: const [
                ButtonSegment(value: 'day', label: Text('Today')),
                ButtonSegment(value: 'week', label: Text('Week')),
                ButtonSegment(value: 'month', label: Text('Month')),
                ButtonSegment(value: 'year', label: Text('Year')),
              ],
              selected: {period},
              onSelectionChanged: (s) => onPeriodChanged(s.first),
            ),
          ),
        );
      },
    );
  }
}

class _MiniStatChip extends StatelessWidget {
  const _MiniStatChip({
    required this.label,
    required this.value,
    required this.icon,
    this.warn = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final color = warn ? Colors.orange.shade800 : _kPlatformNavy;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 13),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
