import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../auth_storage.dart';
import '../../dio_client.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/chat_attachment.dart';
import '../public_hotel_search_screen.dart';

const _kPlatformNavy = Color(0xFF1A2B4A);
const _kPlatformGold = Color(0xFFD4A843);

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
  int _approvalTab = 0;

  Map<String, dynamic>? _settings;
  Map<String, dynamic>? _revenue;
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
        portalDio().get<Map<String, dynamic>>('/platform/credit-requests'),
        portalDio().get<Map<String, dynamic>>('/platform/member-requests'),
        portalDio().get<Map<String, dynamic>>('/platform/hotels'),
      ]);
      setState(() {
        _settings = results[0].data;
        _revenue = results[1].data;
        _creditRequests = (results[2].data?['data'] as List?) ?? const [];
        _memberRequests = (results[3].data?['data'] as List?) ?? const [];
        _hotels = (results[4].data?['data'] as List?) ?? const [];
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dioErrorMessage(e))),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('QR image updated.')),
      );
      await _loadAll();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dioErrorMessage(e))),
      );
    }
  }

  Future<void> _approveCredit(String id) async {
    HapticFeedback.lightImpact();
    try {
      await portalDio().post('/platform/credit-requests/$id/approve');
      await _loadAll();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dioErrorMessage(e))),
      );
    }
  }

  Future<void> _rejectCredit(String id) async {
    try {
      await portalDio().post('/platform/credit-requests/$id/reject');
      await _loadAll();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dioErrorMessage(e))),
      );
    }
  }

  Future<void> _approveMember(String id) async {
    HapticFeedback.lightImpact();
    try {
      await portalDio().post('/platform/member-requests/$id/approve');
      await _loadAll();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dioErrorMessage(e))),
      );
    }
  }

  Future<void> _rejectMember(String id) async {
    try {
      await portalDio().post('/platform/member-requests/$id/reject');
      await _loadAll();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dioErrorMessage(e))),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dioErrorMessage(e))),
      );
    }
  }

  Future<void> _signOut() async {
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('MADYAWPH Platform'),
            Text(
              'Central administration',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white70,
                  ),
            ),
          ],
        ),
        backgroundColor: _kPlatformNavy,
        foregroundColor: Colors.white,
        actions: [
          IconButton(onPressed: _loadAll, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: _signOut, icon: const Icon(Icons.logout)),
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
                      hotelCount: _hotels.length,
                      pendingCredits: _pendingCredits,
                      pendingMembers: _pendingMembers,
                      onOpenApprovals: () => setState(() => _section = 2),
                      onOpenRevenue: () => setState(() => _section = 1),
                    ),
                    _RevenueSection(
                      revenue: _revenue ?? const {},
                      period: _revenuePeriod,
                      onPeriodChanged: (p) {
                        setState(() => _revenuePeriod = p);
                        _reloadRevenue();
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
                    ),
                    _HotelsSection(
                      hotels: _hotels,
                      onDelete: _deleteHotel,
                    ),
                  ],
                ),
      bottomNavigationBar: NavigationBar(
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
    );
  }
}

class _OverviewSection extends StatelessWidget {
  const _OverviewSection({
    required this.revenue,
    required this.hotelCount,
    required this.pendingCredits,
    required this.pendingMembers,
    required this.onOpenApprovals,
    required this.onOpenRevenue,
  });

  final Map<String, dynamic> revenue;
  final int hotelCount;
  final int pendingCredits;
  final int pendingMembers;
  final VoidCallback onOpenApprovals;
  final VoidCallback onOpenRevenue;

  @override
  Widget build(BuildContext context) {
    final totals = revenue['totals'] as Map<String, dynamic>? ?? {};
    final period = (revenue['period'] ?? 'month').toString();

    return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text(
            'This $period at a glance',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 14),
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
          const SizedBox(height: 20),
          if (pendingCredits > 0 || pendingMembers > 0)
            Card(
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
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.insights_outlined),
              title: const Text('Revenue by hotel'),
              subtitle: const Text('See breakdown for every property'),
              trailing: const Icon(Icons.chevron_right),
              onTap: onOpenRevenue,
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Revenue analytics',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              if (from.isNotEmpty)
                Text(
                  '$from → $to',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'day', label: Text('Today')),
                  ButtonSegment(value: 'week', label: Text('Week')),
                  ButtonSegment(value: 'month', label: Text('Month')),
                  ButtonSegment(value: 'year', label: Text('Year')),
                ],
                selected: {period},
                onSelectionChanged: (s) => onPeriodChanged(s.first),
              ),
            ],
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
                ),
          ),
        ),
        Expanded(
          child: hotels.isEmpty
              ? const Center(child: Text('No hotel revenue in this period.'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: hotels.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final h = hotels[i] as Map<String, dynamic>;
                    return Card(
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
                    );
                  },
                ),
        ),
      ],
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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

class _QrSettingsSection extends StatelessWidget {
  const _QrSettingsSection({
    required this.settings,
    required this.onUploadCredit,
    required this.onUploadMember,
  });

  final Map<String, dynamic> settings;
  final VoidCallback onUploadCredit;
  final VoidCallback onUploadMember;

  @override
  Widget build(BuildContext context) {
    final creditQr = ChatAttachment.resolveMediaUrl(
      (settings['credit_wallet_qr_url'] ?? '').toString(),
    );
    final memberQr = ChatAttachment.resolveMediaUrl(
      (settings['member_subscription_qr_url'] ?? '').toString(),
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'QR Ph payment images',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          'Hotels and guests scan these when paying for credits or membership.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        _QrUploadCard(
          title: 'Hotel credit wallet',
          subtitle: 'Used when hotels request credit top-ups.',
          imageUrl: creditQr,
          onUpload: onUploadCredit,
        ),
        const SizedBox(height: 16),
        _QrUploadCard(
          title: 'Become a member',
          subtitle: 'Guests pay ₱${settings['member_monthly_fee'] ?? 300}/month.',
          imageUrl: memberQr,
          onUpload: onUploadMember,
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
              icon: const Icon(Icons.upload_outlined),
              label: const Text('Upload QR Ph'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HotelsSection extends StatelessWidget {
  const _HotelsSection({required this.hotels, required this.onDelete});

  final List<dynamic> hotels;
  final Future<void> Function(String id, String name) onDelete;

  @override
  Widget build(BuildContext context) {
    if (hotels.isEmpty) {
      return const Center(child: Text('No hotels registered.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: hotels.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final h = hotels[i] as Map<String, dynamic>;
        final id = (h['id'] ?? '').toString();
        final name = (h['name'] ?? 'Hotel').toString();
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?'),
            ),
            title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text((h['city'] ?? h['location'] ?? '').toString()),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: () => onDelete(id, name),
            ),
          ),
        );
      },
    );
  }
}
