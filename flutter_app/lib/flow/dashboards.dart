import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../auth_storage.dart';
import '../locale_controller.dart';
import '../dio_client.dart';
import '../navigation_keys.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_input.dart';
import '../widgets/app_scaffold.dart';
import 'admin/widgets/admin_opaque_scaffold.dart';
import '../widgets/app_state_views.dart';
import '../widgets/dashboard_clock.dart';
import '../widgets/dashboard_exit_guard.dart';
import 'admin/admin_dashboard_models.dart';
import 'admin/admin_dashboard_shell.dart';
import 'admin/widgets/admin_room_navigation.dart';
import 'admin/widgets/hourly_billing.dart';
import 'admin/widgets/manual_booking_dialog.dart';
import 'widgets/complete_guest_booking_dialog.dart';
import 'customer_booking_status_screen.dart';
import 'customer_browse_layout.dart';
import 'customer_landscape_grid.dart';
import 'customer_search_context.dart';
import 'customer_tools.dart';
import '../widgets/chat_attachment.dart';
import '../widgets/payment_redirect.dart';
import 'portal_sign_out.dart';
// --- Admin ---

/// Reserve API only for future check-in; same-day and Book always use /customer/bookings.
bool customerStayUsesReservationApi({
  required bool reserveIntent,
  required String checkInIso,
}) {
  if (!reserveIntent) return false;
  final parsed = DateTime.tryParse(checkInIso.split('T').first);
  if (parsed == null) return true;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final checkIn = DateTime(parsed.year, parsed.month, parsed.day);
  return checkIn.isAfter(today);
}

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key, this.isSuperAdmin = false});

  /// When true, shows the same dashboard plus the admin control panel tab.
  final bool isSuperAdmin;

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;
  bool _refreshing = false;
  bool _busyAction = false;
  Timer? _dashboardPoll;
  bool Function()? _shellBackHandler;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _dashboardPoll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) _load(silent: true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _load(silent: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dashboardPoll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent || _data == null) {
      setState(() {
        if (!silent) {
          _loading = true;
        } else {
          _refreshing = true;
        }
        _error = null;
      });
    } else {
      setState(() => _refreshing = true);
    }
    try {
      final res =
          await portalDio().get<Map<String, dynamic>>('/admin/dashboard');
      if (!mounted) return;
      setState(() {
        _data = res.data;
        _loading = false;
        _refreshing = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        if (_data == null) {
          _error = dioErrorMessage(e);
        }
        _loading = false;
        _refreshing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (_data == null) {
          _error = '$e';
        }
        _loading = false;
        _refreshing = false;
      });
    }
  }

  Future<void> _signOut() async {
    await confirmAndSignOutPortalToRoleSelection(context);
  }

  Future<void> _runAction(
    String label,
    Future<Map<String, dynamic>?> Function() action,
  ) async {
    if (_busyAction) return;
    setState(() => _busyAction = true);
    try {
      final payload = await action();
      if (!mounted) return;

      if (!mounted) return;
      if (PaymentRedirect.responseRequiresRedirect(payload)) {
        await PaymentRedirect.maybeOpenFromResponse(context, payload);
      }

      if (!mounted) return;
      final msg = payload?['message']?.toString() ?? '$label completed.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      await _load(silent: true);
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label failed: ${dioErrorMessage(e)}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
  }

  Future<void> _showSurgePricingDialog() async {
    try {
      final current =
          await portalDio().get<Map<String, dynamic>>('/admin/pricing/surge');
      bool enabled = current.data?['enabled'] == true;
      final thresholdCtrl = TextEditingController(
          text: '${current.data?['threshold_percent'] ?? 50}');
      final markupCtrl = TextEditingController(
          text: '${current.data?['markup_percent'] ?? 20}');

      if (!mounted) return;
      final payload = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: const Text('Surge pricing'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  value: enabled,
                  onChanged: (v) => setLocal(() => enabled = v),
                  title: const Text('Enable surge pricing'),
                ),
                TextField(
                  controller: thresholdCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Threshold % (more than)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: markupCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Markup %',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel')),
              FilledButton(
                onPressed: () => Navigator.of(context).pop({
                  'enabled': enabled,
                  'threshold_percent':
                      double.tryParse(thresholdCtrl.text.trim()) ?? 50,
                  'markup_percent':
                      double.tryParse(markupCtrl.text.trim()) ?? 20,
                }),
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      );
      if (payload == null) return;
      await portalDio().patch('/admin/pricing/surge', data: payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Surge pricing updated.')),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dioErrorMessage(e))),
      );
    }
  }

  Future<void> _showRechargeDialog() async {
    final amountCtrl = TextEditingController(text: '1000');
    final refCtrl = TextEditingController();
    String method = 'qrph';
    String qrUrl = '';
    try {
      final info = await publicDio().get<Map<String, dynamic>>('/platform/info');
      qrUrl = ChatAttachment.resolveMediaUrl(
        (info.data?['credit_wallet_qr_url'] ?? '').toString(),
      );
    } catch (_) {}

    if (!mounted) return;
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Recharge credits'),
          content: SingleChildScrollView(
            child: Column(
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
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: method,
                  items: const [
                    DropdownMenuItem(value: 'qrph', child: Text('QR Ph (manual approval)')),
                    DropdownMenuItem(value: 'gcash', child: Text('GCash (online)')),
                    DropdownMenuItem(value: 'paymaya', child: Text('PayMaya (online)')),
                  ],
                  onChanged: (v) => setLocal(() => method = v ?? method),
                  decoration: const InputDecoration(
                    labelText: 'Payment method',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (method == 'qrph') ...[
                  const SizedBox(height: 12),
                  if (qrUrl.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: NetworkMediaImage(
                        url: qrUrl,
                        width: 180,
                        height: 180,
                        fit: BoxFit.contain,
                      ),
                    ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: refCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Payment reference / transaction ID',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.of(context).pop({
                'amount': double.tryParse(amountCtrl.text.trim()) ?? 0,
                'method': method,
                if (method == 'qrph') 'payment_reference': refCtrl.text.trim(),
              }),
              child: Text(method == 'qrph' ? 'Submit for approval' : 'Recharge'),
            ),
          ],
        ),
      ),
    );
    if (payload == null) return;

    if (payload['method'] == 'qrph') {
      await _runAction('Submit credit top-up', () async {
        final res = await portalDio().post<Map<String, dynamic>>(
          '/admin/credits/recharge-request',
          data: {
            'amount': payload['amount'],
            'payment_reference': payload['payment_reference'],
          },
        );
        return {
          ...Map<String, dynamic>.from(res.data ?? {}),
          'message':
              'Top-up submitted. Credits apply after platform approval.',
        };
      });
      return;
    }

    await _runAction('Recharge credits', () async {
      final res = await portalDio().post<Map<String, dynamic>>(
        '/admin/credits/recharge',
        data: payload,
      );
      final data = Map<String, dynamic>.from(res.data ?? {});

      return {
        ...data,
        'message': (data['message'] ??
                'Complete payment in your browser. Credits update after payment succeeds.')
            .toString(),
      };
    });
  }

  Future<void> _manageAmenityMenu() async {
    final typeCtrl = TextEditingController(text: 'Breakfast');
    final nameCtrl = TextEditingController(text: 'Tapsilog');
    final priceCtrl = TextEditingController(text: '120');
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Add amenity menu item',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Guests see these items when requesting amenities from their room.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: typeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Category / type',
                      hintText: 'e.g. Breakfast, Laundry',
                      prefixIcon: Icon(Icons.category_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Item name',
                      hintText: 'Displayed on menus',
                      prefixIcon: Icon(Icons.restaurant_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: priceCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Price (PHP)',
                      prefixIcon: Icon(Icons.payments_outlined),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop({
                          'amenity_type': typeCtrl.text.trim(),
                          'name': nameCtrl.text.trim(),
                          'price': double.tryParse(priceCtrl.text.trim()) ?? 0,
                          'is_active': true,
                        }),
                        child: const Text('Create'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (payload == null) return;

    await _runAction('Amenity menu', () async {
      await portalDio().post('/admin/amenity-menu', data: payload);
      return {'message': 'Amenity menu item created.'};
    });
  }

  @override
  Widget build(BuildContext context) {
    return DashboardExitGuard(
      navigatorKey: adminDashboardNavigatorKey,
      onRequestInnerPop: () => _shellBackHandler?.call() ?? false,
      child: Scaffold(
        body: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading && _data == null) return const AppLoadingView();
    if (_error != null && _data == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => _load(), child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    var isSuper = widget.isSuperAdmin;
    final auth = _data!['auth'] as Map<String, dynamic>?;
    final user = auth?['user'] as Map<String, dynamic>?;
    if ((user?['role'] ?? '').toString() == 'super_admin') {
      isSuper = true;
    }

    return Column(
      children: [
        if (_refreshing) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: Navigator(
            key: adminDashboardNavigatorKey,
            onGenerateRoute: (settings) {
              return MaterialPageRoute<void>(
                builder: (_) => AdminDashboardShell(
                  data: _data!,
                  isSuperAdmin: isSuper,
                  onBindBackHandler: (handler) {
                    _shellBackHandler = handler;
                  },
                  onRefresh: () => _load(silent: true),
                  onSignOut: _signOut,
                  busyAction: _busyAction,
                  onRecharge: _showRechargeDialog,
                  onSurgePricing: _showSurgePricingDialog,
                  onThemeReset: () => _runAction('Reset personal theme', () async {
                    await portalDio().delete('/admin/theme/reset');
                    return {'message': 'Personal theme reset.'};
                  }),
                  onProcessReminders: () => _runAction('Process reminders', () async {
                    final res = await portalDio()
                        .post<Map<String, dynamic>>('/checkouts/process-reminders');
                    return {
                      'message': 'Processed ${res.data?['processed'] ?? 0} reminders.',
                    };
                  }),
                  onAmenityAddProduct: _manageAmenityMenu,
                  onOpenActivityLogs: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const AdminActivityLogsScreen(),
                      ),
                    );
                  },
                  onOpenAccountSettings: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const AdminAccountSettingsScreen(),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class AdminRoomSummaryScreen extends StatelessWidget {
  const AdminRoomSummaryScreen({super.key, required this.rooms});

  final List<Map<String, dynamic>> rooms;

  List<Map<String, dynamic>> _byStatus(String status) {
    return rooms
        .where((room) =>
            (room['status'] ?? '').toString().toLowerCase() ==
            status.toLowerCase())
        .toList();
  }

  void _openDetail(
    BuildContext context, {
    required String title,
    required List<Map<String, dynamic>> list,
    required bool showGuest,
  }) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AdminRoomSummaryDetailScreen(
          title: title,
          rooms: list,
          showGuest: showGuest,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final booked = _byStatus('booked');
    final available = _byStatus('available');
    final maintenance = _byStatus('maintenance');
    final checkedIn = _byStatus('checked_in');
    return AppScaffold(
      appBar: AppBar(title: const Text('Room summary')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Tap any category to open the full room list and manage details.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.15,
            children: [
              _AdminSummaryCategoryCard(
                label: 'Booked',
                count: booked.length,
                icon: Icons.book_online_outlined,
                color: scheme.primaryContainer,
                onTap: () => _openDetail(
                  context,
                  title: 'Booked rooms',
                  list: booked,
                  showGuest: true,
                ),
              ),
              _AdminSummaryCategoryCard(
                label: 'Available',
                count: available.length,
                icon: Icons.event_available_outlined,
                color: scheme.secondaryContainer,
                onTap: () => _openDetail(
                  context,
                  title: 'Available rooms',
                  list: available,
                  showGuest: false,
                ),
              ),
              _AdminSummaryCategoryCard(
                label: 'Maintenance',
                count: maintenance.length,
                icon: Icons.build_circle_outlined,
                color: scheme.tertiaryContainer,
                onTap: () => _openDetail(
                  context,
                  title: 'Maintenance rooms',
                  list: maintenance,
                  showGuest: false,
                ),
              ),
              _AdminSummaryCategoryCard(
                label: 'Checked in',
                count: checkedIn.length,
                icon: Icons.hotel_class_outlined,
                color: scheme.surfaceContainerHighest,
                onTap: () => _openDetail(
                  context,
                  title: 'Checked-in rooms',
                  list: checkedIn,
                  showGuest: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AdminSummaryCategoryCard extends StatelessWidget {
  const _AdminSummaryCategoryCard({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final int count;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 28, color: scheme.onSurface),
              const Spacer(),
              Text(
                '$count',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              Text(
                label,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Tap for details',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AdminRoomSummaryDetailScreen extends StatelessWidget {
  const AdminRoomSummaryDetailScreen({
    super.key,
    required this.title,
    required this.rooms,
    required this.showGuest,
  });

  final String title;
  final List<Map<String, dynamic>> rooms;
  final bool showGuest;

  @override
  Widget build(BuildContext context) {
    return AdminOpaqueScaffold(
      appBar: AppBar(title: Text(title)),
      body: rooms.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No rooms in this category.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rooms.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final room = rooms[i];
                final roomId = AdminDashboardModels.roomIdOf(
                  room as Map<String, dynamic>,
                );
                final roomNo = (room['room_number'] ?? '-').toString();
                final guest =
                    (room['current_guest_name'] ?? '').toString().trim();
                final category =
                    (room['category_name'] ?? '').toString().trim();
                final status = (room['status'] ?? '').toString();
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.meeting_room_outlined),
                    title: Text('Room $roomNo'),
                    subtitle: Text(
                      [
                        if (category.isNotEmpty) 'Category: $category',
                        'Status: $status',
                        if (showGuest && guest.isNotEmpty) 'Guest: $guest',
                        if (showGuest && guest.isEmpty) 'Guest: —',
                      ].join('\n'),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: roomId.isEmpty
                        ? null
                        : () {
                            AdminRoomNavigation.openDetailById(context, roomId);
                          },
                  ),
                );
              },
            ),
    );
  }
}

class AdminActivityLogsScreen extends StatefulWidget {
  const AdminActivityLogsScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<AdminActivityLogsScreen> createState() => _AdminActivityLogsScreenState();
}

class _AdminActivityLogsScreenState extends State<AdminActivityLogsScreen> {
  List<dynamic> _logs = const [];
  bool _loading = true;
  String? _error;
  static const _pageSize = 25;
  int _page = 1;
  int _lastPage = 1;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _load(page: 1);
  }

  Future<void> _load({required int page}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await portalDio().get<Map<String, dynamic>>(
        '/activity-logs',
        queryParameters: {
          'page': page,
          'per_page': _pageSize,
        },
      );
      final body = res.data ?? const <String, dynamic>{};
      final data = (body['data'] as List<dynamic>?) ?? const [];
      final currentPage = (body['current_page'] as num?)?.toInt() ??
          ((body['meta'] as Map?)?['current_page'] as num?)?.toInt() ??
          page;
      final lastPage = (body['last_page'] as num?)?.toInt() ??
          ((body['meta'] as Map?)?['last_page'] as num?)?.toInt() ??
          (data.length < _pageSize ? page : page + 1);
      final total = (body['total'] as num?)?.toInt() ??
          ((body['meta'] as Map?)?['total'] as num?)?.toInt() ??
          data.length;
      setState(() {
        _logs = data;
        _page = currentPage;
        _lastPage = lastPage;
        _total = total;
        _loading = false;
      });
    } on DioException catch (e) {
      setState(() {
        _error = dioErrorMessage(e);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Widget _buildLogList() {
    if (_loading) return const AppLoadingView();
    if (_error != null) {
      return AppErrorView(message: _error!, onRetry: () => _load(page: _page));
    }
    if (_logs.isEmpty) {
      return const Center(child: Text('No activity recorded yet.'));
    }

    return RefreshIndicator(
      onRefresh: () => _load(page: 1),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: _logs.length + 1,
        itemBuilder: (context, i) {
          if (i == _logs.length) {
            if (_lastPage <= 1) return const SizedBox(height: 8);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Previous page',
                    onPressed: _page > 1
                        ? () => _load(page: _page - 1)
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'Page $_page of $_lastPage · $_total entries',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next page',
                    onPressed: _page < _lastPage
                        ? () => _load(page: _page + 1)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            );
          }
          final log = _logs[i] as Map<String, dynamic>;
          final when = (log['created_at'] ?? log['timestamp'] ?? '').toString();
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (log['action'] ?? '').toString(),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'By ${(log['user_name'] ?? 'System').toString()}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (when.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        when,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildLogList();
    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Activity trail',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                IconButton(
                  onPressed: () => _load(page: _page),
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ),
          Expanded(child: body),
        ],
      );
    }
    return AppScaffold(
      appBar: AppBar(
        title: const Text('Activity logs'),
        actions: [
          IconButton(
            onPressed: () => _load(page: _page),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: body,
    );
  }
}

// --- Staff ---

class StaffDashboardScreen extends StatefulWidget {
  const StaffDashboardScreen({super.key});

  @override
  State<StaffDashboardScreen> createState() => _StaffDashboardScreenState();
}

class _StaffDashboardScreenState extends State<StaffDashboardScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res =
          await portalDio().get<Map<String, dynamic>>('/staff/dashboard');
      setState(() {
        _data = res.data;
        _loading = false;
      });
    } on DioException catch (e) {
      setState(() {
        _error = dioErrorMessage(e);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _staffChangePassword(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final auth = (_data?['auth'] as Map<String, dynamic>?)?['user']
        as Map<String, dynamic>?;
    nameCtrl.text = (auth?['name'] ?? '').toString();
    final messenger = ScaffoldMessenger.of(context);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change password'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppInput(controller: nameCtrl, label: 'Username'),
              const SizedBox(height: 8),
              AppInput(
                controller: currentCtrl,
                label: 'Current password',
                obscureText: true,
              ),
              const SizedBox(height: 8),
              AppInput(
                controller: newCtrl,
                label: 'New password',
                obscureText: true,
              ),
              const SizedBox(height: 8),
              AppInput(
                controller: confirmCtrl,
                label: 'Confirm new password',
                obscureText: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    if (newCtrl.text.isNotEmpty && newCtrl.text != confirmCtrl.text) {
      messenger.showSnackBar(
        const SnackBar(content: Text('New passwords do not match.')),
      );
      return;
    }
    try {
      await portalDio().put('/staff/profile', data: {
        'name': nameCtrl.text.trim(),
        if (newCtrl.text.isNotEmpty) 'current_password': currentCtrl.text,
        if (newCtrl.text.isNotEmpty) 'password': newCtrl.text,
        if (newCtrl.text.isNotEmpty) 'password_confirmation': confirmCtrl.text,
      });
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Staff profile updated.')),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(dioErrorMessage(e))),
      );
    }
  }

  Future<void> _signOut() async {
    await confirmAndSignOutPortalToRoleSelection(context);
  }

  @override
  Widget build(BuildContext context) {
    return DashboardExitGuard(
      child: AppScaffold(
      appBar: AppBar(
        title: const Text('Staff dashboard'),
        actions: [
          const DashboardClockAction(),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'out') _signOut();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'out', child: Text('Sign out')),
            ],
          ),
        ],
      ),
      body: _buildBody(),
    ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const AppLoadingView();
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    final tasks = (_data!['tasks'] as List<dynamic>?) ?? [];
    final msgs = (_data!['guestMessages'] as List<dynamic>?) ?? [];
    final rooms = (_data!['rooms'] as List<dynamic>?) ?? [];
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Operations', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.7,
            children: [
              AppMetricCard(
                  label: 'Tasks',
                  value: '${tasks.length}',
                  icon: Icons.task_outlined),
              AppMetricCard(
                  label: 'Guest msgs',
                  value: '${msgs.length}',
                  icon: Icons.chat_outlined),
              AppMetricCard(
                  label: 'Rooms',
                  value: '${rooms.length}',
                  icon: Icons.meeting_room_outlined),
              const AppMetricCard(
                  label: 'Role', value: 'Staff', icon: Icons.badge_outlined),
            ],
          ),
          const SizedBox(height: 16),
          AppActionTile(
            title: 'My assigned tasks',
            subtitle: 'Open full list and update statuses inside',
            icon: Icons.assignment_ind_outlined,
            onTap: () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const StaffAssignedTasksScreen(),
                ),
              );
              await _load();
            },
          ),
          AppActionTile(
            title: 'Room operations',
            subtitle:
                'View all rooms by category and maintenance assignments',
            icon: Icons.hotel_outlined,
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => StaffRoomOperationsScreen(
                  groupedRooms:
                      (_data!['roomOperations'] as List<dynamic>? ?? const []),
                ),
              ),
            ),
          ),
          AppActionTile(
            title: 'Message admin',
            subtitle: 'Send updates or request help from administrators',
            icon: Icons.support_agent_outlined,
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const StaffAdminMessagesScreen(),
              ),
            ),
          ),
          AppActionTile(
            title: 'Change my password',
            subtitle: 'Update your staff login username or password',
            icon: Icons.lock_outline,
            onTap: () => _staffChangePassword(context),
          ),
          const SizedBox(height: 16),
          Text('Recent Tasks', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...tasks.take(5).map((t) {
            final m = t as Map<String, dynamic>;
            return Card(
              child: ListTile(
                leading: const Icon(Icons.task_alt_outlined),
                title: Text((m['title'] ?? 'Task').toString()),
                subtitle:
                    Text('Status: ${(m['status'] ?? 'pending').toString()}'),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class StaffAssignedTasksScreen extends StatefulWidget {
  const StaffAssignedTasksScreen({super.key});

  @override
  State<StaffAssignedTasksScreen> createState() => _StaffAssignedTasksScreenState();
}

class _StaffAssignedTasksScreenState extends State<StaffAssignedTasksScreen> {
  List<dynamic> _tasks = const [];
  bool _loading = true;
  String? _error;
  String _statusFilter = 'all';
  final Set<String> _savingIds = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await portalDio().get<List<dynamic>>('/tasks/assigned-to-me');
      setState(() {
        _tasks = res.data ?? const [];
        _loading = false;
      });
    } on DioException catch (e) {
      setState(() {
        _error = dioErrorMessage(e);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _updateTaskStatus(Map<String, dynamic> task, String status) async {
    final taskId = (task['id'] ?? '').toString();
    if (taskId.isEmpty || _savingIds.contains(taskId)) return;
    setState(() => _savingIds.add(taskId));
    try {
      await portalDio().put('/tasks/$taskId/status', data: {'status': status});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Task updated to $status.')),
      );
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dioErrorMessage(e))),
      );
    } finally {
      if (mounted) {
        setState(() => _savingIds.remove(taskId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppBar(
        title: const Text('My assigned tasks'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) return const AppLoadingView();
    if (_error != null) return AppErrorView(message: _error!, onRetry: _load);
    final filtered = _tasks.where((raw) {
      final task = raw as Map<String, dynamic>;
      final status = (task['status'] ?? '').toString().toLowerCase();
      return _statusFilter == 'all' || status == _statusFilter;
    }).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('All'),
                selected: _statusFilter == 'all',
                onSelected: (_) => setState(() => _statusFilter = 'all'),
              ),
              ChoiceChip(
                label: const Text('Pending'),
                selected: _statusFilter == 'pending',
                onSelected: (_) => setState(() => _statusFilter = 'pending'),
              ),
              ChoiceChip(
                label: const Text('In progress'),
                selected: _statusFilter == 'in-progress',
                onSelected: (_) => setState(() => _statusFilter = 'in-progress'),
              ),
              ChoiceChip(
                label: const Text('Completed'),
                selected: _statusFilter == 'completed',
                onSelected: (_) => setState(() => _statusFilter = 'completed'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (filtered.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.task_alt_outlined),
                title: Text('No tasks found for this filter.'),
              ),
            ),
          ...filtered.map((raw) {
            final task = raw as Map<String, dynamic>;
            final taskId = (task['id'] ?? '').toString();
            final title = (task['title'] ?? 'Task').toString();
            final desc = (task['description'] ?? '').toString();
            final current = (task['status'] ?? 'pending').toString();
            final saving = _savingIds.contains(taskId);
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    if (desc.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(desc),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: current,
                            items: const [
                              DropdownMenuItem(
                                  value: 'pending', child: Text('pending')),
                              DropdownMenuItem(
                                  value: 'in-progress',
                                  child: Text('in-progress')),
                              DropdownMenuItem(
                                  value: 'completed', child: Text('completed')),
                            ],
                            onChanged: saving
                                ? null
                                : (v) {
                                    final next = (v ?? current).trim();
                                    if (next.isEmpty || next == current) return;
                                    _updateTaskStatus(task, next);
                                  },
                            decoration: const InputDecoration(
                              labelText: 'Status',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        if (saving) ...[
                          const SizedBox(width: 10),
                          const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class StaffRoomOperationsScreen extends StatelessWidget {
  const StaffRoomOperationsScreen({super.key, required this.groupedRooms});

  final List<dynamic> groupedRooms;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppBar(title: const Text('Room operations')),
      body: groupedRooms.isEmpty
          ? const Center(child: Text('No room data available.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: groupedRooms.map((groupRaw) {
                final group = groupRaw as Map<String, dynamic>;
                final category = (group['category'] ?? 'Uncategorized').toString();
                final rooms = (group['rooms'] as List<dynamic>? ?? const []);
                return AppSectionCard(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(category, style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        ...rooms.map((roomRaw) {
                          final room = roomRaw as Map<String, dynamic>;
                          final roomNo = (room['room_number'] ?? '').toString();
                          final status = (room['status'] ?? 'unknown').toString();
                          final assignment =
                              room['maintenanceAssignment'] as Map<String, dynamic>?;
                          final assignee = (assignment?['assignedStaffName'] ??
                                  'No active maintenance assignment')
                              .toString();
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.meeting_room_outlined),
                            title: Text('Room $roomNo'),
                            subtitle: Text(
                                'Status: $status\nMaintenance staff: $assignee'),
                            dense: true,
                          );
                        }),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class StaffAdminMessagesScreen extends StatefulWidget {
  const StaffAdminMessagesScreen({super.key});

  @override
  State<StaffAdminMessagesScreen> createState() => _StaffAdminMessagesScreenState();
}

class _StaffAdminMessagesScreenState extends State<StaffAdminMessagesScreen> {
  List<dynamic> _messages = const [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await portalDio().get<Map<String, dynamic>>(
        '/staff/chat/admin/messages',
      );
      setState(() {
        _messages = (res.data?['messages'] as List<dynamic>?) ?? const [];
        _loading = false;
      });
    } on DioException catch (e) {
      setState(() {
        _error = dioErrorMessage(e);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _send({XFile? image}) async {
    final message = _ctrl.text.trim();
    if (message.isEmpty && image == null) return;
    if (_sending) return;
    setState(() => _sending = true);
    try {
      if (image != null) {
        final form = await ChatAttachment.formWithImage(
          fields: {
            'message': message.isEmpty ? '(image)' : message,
          },
          file: image,
        );
        await portalDio().post('/staff/chat/admin/messages', data: form);
      } else {
        await portalDio().post('/staff/chat/admin/messages', data: {
          'message': message,
        });
      }
      _ctrl.clear();
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dioErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppBar(
        title: const Text('Message admin'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildBody()),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Attach photo',
                  onPressed: _sending
                      ? null
                      : () async {
                          final file = await ChatAttachment.pick(context);
                          if (file != null) await _send(image: file);
                        },
                  icon: const Icon(Icons.attach_file),
                ),
                Expanded(
                  child: AppInput(
                    controller: _ctrl,
                    label: 'Message',
                    hint: 'Type a message to admin',
                  ),
                ),
                const SizedBox(width: 10),
                AppPrimaryButton(
                  label: 'Send',
                  onPressed: _sending ? null : () => _send(),
                  isLoading: _sending,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const AppLoadingView();
    if (_error != null) return AppErrorView(message: _error!, onRetry: _load);
    if (_messages.isEmpty) {
      return const Center(
        child: Text('No messages yet. Start the conversation with admin.'),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _messages.length,
      itemBuilder: (context, i) {
        final m = _messages[i] as Map<String, dynamic>;
        final role = (m['sender_role'] ?? '').toString();
        return ChatMessageBubble.fromMap(m, isMine: role == 'staff');
      },
    );
  }
}

// --- Guest ---

class GuestDashboardScreen extends StatefulWidget {
  const GuestDashboardScreen({super.key});

  @override
  State<GuestDashboardScreen> createState() => _GuestDashboardScreenState();
}

class _GuestDashboardScreenState extends State<GuestDashboardScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;
  bool _busyAction = false;

  List<dynamic> _chatMessages = const [];
  final _chatInput = TextEditingController();
  final _chatScroll = ScrollController();
  Timer? _poll;
  bool _chatSending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _chatInput.dispose();
    _chatScroll.dispose();
    super.dispose();
  }

  void _startChatPoll() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 12), (_) {
      if (mounted) _refreshChat(silent: true);
    });
  }

  Future<void> _refreshChat({bool silent = false}) async {
    try {
      final res =
          await guestDio().get<Map<String, dynamic>>(
            '/guest/chat/messages',
            queryParameters: {
              'locale': AppLocales.code(appLocaleNotifier.value),
            },
          );
      if (!mounted) return;
      final list = (res.data?['messages'] as List?) ?? [];
      setState(() => _chatMessages = list);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollChatToEnd());
    } catch (_) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not refresh messages.')),
        );
      }
    }
  }

  void _scrollChatToEnd() {
    if (!_chatScroll.hasClients) return;
    final max = _chatScroll.position.maxScrollExtent;
    _chatScroll.animateTo(
      max,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res =
          await guestDio().get<Map<String, dynamic>>('/guest/dashboard');
      setState(() {
        _data = res.data;
        _loading = false;
      });
      await _refreshChat(silent: true);
      _startChatPoll();
    } on DioException catch (e) {
      setState(() {
        _error = dioErrorMessage(e);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _silentReload() async {
    try {
      final res =
          await guestDio().get<Map<String, dynamic>>('/guest/dashboard');
      if (!mounted) return;
      setState(() => _data = res.data);
      await _refreshChat(silent: true);
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dioErrorMessage(e))),
      );
    }
  }

  bool _isGuestMessage(Map<String, dynamic> m) {
    final r =
        (m['sender_role'] ?? m['senderRole'] ?? '').toString().toLowerCase();
    return r == 'guest';
  }

  Future<void> _sendChatLine({XFile? image}) async {
    final text = _chatInput.text.trim();
    if (text.isEmpty && image == null) return;
    if (_chatSending) return;
    setState(() => _chatSending = true);
    try {
      if (image != null) {
        final form = await ChatAttachment.formWithImage(
          fields: {'message': text.isEmpty ? '(image)' : text},
          file: image,
        );
        await guestDio().post('/guest/chat/messages', data: form);
      } else {
        await guestDio().post('/guest/chat/messages', data: {'message': text});
      }
      if (!mounted) return;
      _chatInput.clear();
      await _refreshChat(silent: true);
    } on DioException catch (e) {
      if (!mounted) return;
      if (e.response?.statusCode == 401) {
        await _signOut();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dioErrorMessage(e))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _chatSending = false);
    }
  }

  Future<void> _signOut() async {
    try {
      await guestDio().post('/guest/logout');
    } catch (_) {}
    await AuthStorage.clearGuestAuth();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _runGuestAction(
    String label,
    Future<Map<String, dynamic>?> Function() action,
  ) async {
    if (_busyAction) return;
    setState(() => _busyAction = true);
    try {
      final payload = await action();
      if (!mounted) return;
      final msg = payload?['message']?.toString() ?? '$label completed.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      if (e.response?.statusCode == 401) {
        await _signOut();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label failed: ${dioErrorMessage(e)}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
  }

  Future<void> _claimAmenity() async {
    final qtyCtrl = TextEditingController(text: '1');
    final items = (_data?['amenityMenu'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    if (items.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No amenity menu available yet.')),
      );
      return;
    }
    String selectedId = (items.first['id'] ?? '').toString();
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Request amenity',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    key: ValueKey<String>(selectedId),
                    initialValue: selectedId,
                    decoration: const InputDecoration(
                      labelText: 'Menu item',
                    ),
                    items: items.map((item) {
                      final id = (item['id'] ?? '').toString();
                      final name = (item['amenityName'] ?? '').toString();
                      final type = (item['amenityType'] ?? '').toString();
                      final price = (item['price'] ?? 0).toString();
                      return DropdownMenuItem(
                        value: id,
                        child: Text('$name ($type) · ₱$price'),
                      );
                    }).toList(),
                    onChanged: (v) =>
                        setLocal(() => selectedId = v ?? selectedId),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Quantity',
                      prefixIcon: Icon(Icons.numbers_outlined),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop({
                          'amenityItemId': selectedId,
                          'quantity': int.tryParse(qtyCtrl.text.trim()) ?? 1,
                        }),
                        child: const Text('Submit'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (payload == null) return;

    await _runGuestAction('Amenity request', () async {
      await guestDio().post('/guest/amenities/claim', data: payload);
      return {'message': 'Amenity request submitted and added to charges.'};
    });
  }

  Future<void> _extendStay() async {
    final roomInfo = _data?['roomInfo'] as Map<String, dynamic>?;
    final billingMode =
        (roomInfo?['billingMode'] ?? 'nightly').toString().toLowerCase();
    final isHourly = billingMode == 'hourly';
    final hourOptions = (roomInfo?['extendHourOptions'] as List<dynamic>? ?? [])
        .map((e) => (e as num).toInt())
        .where((h) => h > 0)
        .toList();
    final blockHours = (roomInfo?['blockHours'] as num?)?.toInt() ?? 3;
    final pricePerBlock =
        (roomInfo?['pricePerBlock'] as num?)?.toDouble() ?? 0;

    if (isHourly && hourOptions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hourly extension options are not available.'),
        ),
      );
      return;
    }

    int? nights;
    int? hours;
    if (isHourly) {
      var selectedHours = hourOptions.first;
      final picked = await showDialog<int>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: const Text('Extend Stay'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Extend by multiples of $blockHours hour(s)',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: ValueKey<int>(selectedHours),
                  initialValue: selectedHours,
                  items: hourOptions
                      .map(
                        (h) => DropdownMenuItem(
                          value: h,
                          child: Text(
                            '$h hours — ₱${((h / blockHours) * pricePerBlock).toStringAsFixed(0)}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) =>
                      setLocal(() => selectedHours = v ?? selectedHours),
                  decoration: const InputDecoration(
                    labelText: 'Additional hours',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(selectedHours),
                child: const Text('Submit'),
              ),
            ],
          ),
        ),
      );
      hours = picked;
      if (hours == null || hours < 1) return;
    } else {
      final ctrl = TextEditingController(text: '1');
      nights = await showDialog<int>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Extend Stay'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              labelText: 'Additional nights',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(int.tryParse(ctrl.text.trim()) ?? 1),
              child: const Text('Submit'),
            ),
          ],
        ),
      );
      ctrl.dispose();
      if (nights == null || nights < 1) return;
    }

    await _runGuestAction('Extend stay', () async {
      final res = await guestDio().post<Map<String, dynamic>>(
        '/guest/extend-stay',
        data: isHourly ? {'hours': hours} : {'nights': nights},
      );
      final checkout = res.data?['new_checkout_date'] ?? '-';
      final checkoutTime = res.data?['new_checkout_time'];
      final when = checkoutTime != null ? '$checkout $checkoutTime' : checkout;
      return {
        'message':
            'Extended stay. New checkout: $when, additional fee: ${res.data?['extension_fee'] ?? '-'}',
      };
    });
  }

  Future<void> _submitReview() async {
    final room = _data?['roomInfo'] as Map<String, dynamic>?;
    final bookingId = room?['activeBookingId']?.toString() ?? '';
    if (bookingId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No active booking found.')));
      return;
    }
    final commentCtrl = TextEditingController();
    int rating = 5;
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Submit Review'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                key: ValueKey<int>(rating),
                initialValue: rating,
                items: const [
                  DropdownMenuItem(value: 5, child: Text('5 - Excellent')),
                  DropdownMenuItem(value: 4, child: Text('4 - Good')),
                  DropdownMenuItem(value: 3, child: Text('3 - Fair')),
                  DropdownMenuItem(value: 2, child: Text('2 - Poor')),
                  DropdownMenuItem(value: 1, child: Text('1 - Bad')),
                ],
                onChanged: (v) => setLocal(() => rating = v ?? 5),
                decoration: const InputDecoration(labelText: 'Rating'),
              ),
              TextField(
                controller: commentCtrl,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Comment'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.of(context).pop({
                'booking_id': bookingId,
                'rating': rating,
                'comment': commentCtrl.text.trim(),
              }),
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
    if (payload == null) return;
    await _runGuestAction('Review', () async {
      await guestDio().post('/guest/review', data: payload);
      return {'message': 'Thank you for your review.'};
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppBar(
        title: const Text('Guest dashboard'),
        actions: [
          const DashboardClockAction(),
          IconButton(onPressed: _silentReload, icon: const Icon(Icons.refresh)),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'out') _signOut();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'out', child: Text('Sign out')),
            ],
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) return const AppLoadingView();
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    final room = _data!['roomInfo'] as Map<String, dynamic>?;
    final auth = _data!['auth'] as Map<String, dynamic>?;
    final u = auth?['user'] as Map<String, dynamic>?;
    final claims = (_data!['amenityClaims'] as List<dynamic>?) ?? [];
    final hotel = u?['hotelName'] ?? 'Hotel';
    final roomNo = room?['roomNumber'] ?? '—';
    final checkout = room?['checkOutAt']?.toString() ?? '—';

    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Expanded(
          flex: 11,
          child: RefreshIndicator(
            onRefresh: _silentReload,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              children: [
                Text(hotel, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text('Room $roomNo · Checkout: $checkout'),
                const SizedBox(height: 14),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.7,
                  children: [
                    AppMetricCard(
                        label: 'Amenity claims',
                        value: '${claims.length}',
                        icon: Icons.local_mall_outlined),
                    AppMetricCard(
                        label: 'Review prompt',
                        value: (room?['showReviewPrompt'] == true)
                            ? 'Yes'
                            : 'No',
                        icon: Icons.reviews_outlined),
                  ],
                ),
                const SizedBox(height: 16),
                AppActionTile(
                  title: 'Request amenity',
                  subtitle: 'Submit a housekeeping/amenity claim',
                  icon: Icons.room_service_outlined,
                  onTap: _claimAmenity,
                ),
                AppActionTile(
                  title: 'Extend stay',
                  subtitle: 'Extend by hotel minimum hours or nights',
                  icon: Icons.calendar_month_outlined,
                  onTap: _extendStay,
                ),
                AppActionTile(
                  title: 'Submit review',
                  subtitle: 'Rate your stay and leave feedback',
                  icon: Icons.rate_review_outlined,
                  onTap: _submitReview,
                ),
                const SizedBox(height: 12),
                Text('Recent amenity claims',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ...claims.take(5).map((c) {
                  final m = c as Map<String, dynamic>;
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.shopping_bag_outlined),
                      title: Text((m['amenityName'] ?? '').toString()),
                      subtitle: Text(
                          'Qty ${(m['quantity'] ?? 1)} · Status ${(m['status'] ?? 'pending')}'),
                    ),
                  );
                }),
                if (_busyAction) ...[
                  const SizedBox(height: 10),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
          ),
        ),
        Expanded(
          flex: 10,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Material(
              elevation: 1,
              shadowColor: Colors.black26,
              borderRadius: BorderRadius.circular(16),
              color: scheme.surfaceContainerLow,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                      child: Row(
                        children: [
                          Icon(Icons.forum_outlined, color: scheme.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Concierge chat',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          TextButton(
                            onPressed: () => _refreshChat(silent: false),
                            child: const Text('Refresh'),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: scheme.outlineVariant),
                    Expanded(
                      child: _chatMessages.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  'No messages yet.\nSay hello to the front desk — replies appear here.',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                              ),
                            )
                          : ListView.builder(
                              controller: _chatScroll,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              itemCount: _chatMessages.length,
                              itemBuilder: (context, i) {
                                final raw = _chatMessages[i];
                                final m = raw is Map<String, dynamic>
                                    ? raw
                                    : <String, dynamic>{};
                                final guestSide = _isGuestMessage(m);
                                return ChatMessageBubble.fromMap(
                                  m,
                                  isMine: guestSide,
                                );
                              },
                            ),
                    ),
                    Divider(height: 1, color: scheme.outlineVariant),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          IconButton(
                            tooltip: 'Attach photo',
                            onPressed: _chatSending
                                ? null
                                : () async {
                                    final file =
                                        await ChatAttachment.pick(context);
                                    if (file != null) {
                                      await _sendChatLine(image: file);
                                    }
                                  },
                            icon: const Icon(Icons.attach_file),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _chatInput,
                              minLines: 1,
                              maxLines: 4,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _sendChatLine(),
                              decoration: InputDecoration(
                                hintText: 'Message the hotel…',
                                filled: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: _chatSending
                                ? null
                                : () => _sendChatLine(),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.all(16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: _chatSending
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.send_rounded),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class AdminAccountSettingsScreen extends StatefulWidget {
  const AdminAccountSettingsScreen({super.key});

  @override
  State<AdminAccountSettingsScreen> createState() =>
      _AdminAccountSettingsScreenState();
}

class _AdminAccountSettingsScreenState extends State<AdminAccountSettingsScreen> {
  final _nameCtrl = TextEditingController();
  final _adminCurrentPass = TextEditingController();
  final _adminNewPass = TextEditingController();
  final _adminNewPass2 = TextEditingController();
  bool _busy = false;
  bool _isSuperAdmin = false;

  @override
  void initState() {
    super.initState();
    _loadDefaults();
  }

  Future<void> _loadDefaults() async {
    final role = await AuthStorage.portalRole();
    var isSuper = role == 'super_admin';
    try {
      final r = await portalDio().get<Map<String, dynamic>>('/admin/dashboard');
      final u =
          (r.data?['auth'] as Map<String, dynamic>?)?['user'] as Map<String, dynamic>?;
      final n = (u?['name'] ?? '').toString();
      final apiRole = (u?['role'] ?? '').toString();
      if (apiRole == 'super_admin') isSuper = true;
      if (mounted && n.isNotEmpty) _nameCtrl.text = n;
    } catch (_) {}
    if (mounted) setState(() => _isSuperAdmin = isSuper);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _adminCurrentPass.dispose();
    _adminNewPass.dispose();
    _adminNewPass2.dispose();
    super.dispose();
  }

  Future<void> _saveAdminProfile() async {
    if (_busy) return;
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a username / display name.')),
      );
      return;
    }
    final hasNew = _adminNewPass.text.isNotEmpty;
    if (hasNew && _adminNewPass.text != _adminNewPass2.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('New passwords do not match.')),
      );
      return;
    }
    if (hasNew && _adminCurrentPass.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your current password to set a new one.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final data = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
      };
      if (hasNew) {
        data['current_password'] = _adminCurrentPass.text;
        data['password'] = _adminNewPass.text;
        data['password_confirmation'] = _adminNewPass2.text;
      }
      await portalDio().put<Map<String, dynamic>>('/admin/profile', data: data);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Admin profile updated.')),
      );
      _adminCurrentPass.clear();
      _adminNewPass.clear();
      _adminNewPass2.clear();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dioErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppBar(title: const Text('Account settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Admin sign-in',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Username is the same value you use on the staff/admin login screen (stored as name).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          AppInput(controller: _nameCtrl, label: 'Username'),
          const SizedBox(height: 8),
          AppInput(
            controller: _adminCurrentPass,
            label: 'Current password',
            obscureText: true,
          ),
          const SizedBox(height: 8),
          AppInput(
            controller: _adminNewPass,
            label: 'New password (optional)',
            obscureText: true,
          ),
          const SizedBox(height: 8),
          AppInput(
            controller: _adminNewPass2,
            label: 'Confirm new password',
            obscureText: true,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _saveAdminProfile,
            child: const Text('Change my password / username'),
          ),
          if (_isSuperAdmin) ...[
            const SizedBox(height: 28),
            Card(
              child: ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: const Text('Manage administrators'),
                subtitle: const Text(
                  'Add or remove admin accounts from the Control tab on your dashboard.',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// --- Public customer ---

class CustomerDashboardScreen extends StatefulWidget {
  const CustomerDashboardScreen({
    super.key,
    required this.hotelId,
    this.searchContext,
  });

  final String hotelId;
  final CustomerSearchContext? searchContext;

  @override
  State<CustomerDashboardScreen> createState() =>
      _CustomerDashboardScreenState();
}

class _CustomerDashboardScreenState extends State<CustomerDashboardScreen> {
  Map<String, dynamic>? _categoriesRes;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final params = <String, dynamic>{'hotel_id': widget.hotelId};
      if (widget.searchContext != null) {
        params.addAll(widget.searchContext!.queryParams);
      }
      final res = await publicDio().get<Map<String, dynamic>>(
        '/customer/categories',
        queryParameters: params,
      );
      setState(() {
        _categoriesRes = res.data;
        _loading = false;
      });
    } on DioException catch (e) {
      setState(() {
        _error = dioErrorMessage(e);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LocaleScope(
      builder: (context, _) => AppScaffold(
        appBar: AppBar(
          title: Text(context.tr('book_a_stay')),
          actions: [
            IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
            IconButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => CustomerToolsScreen(hotelId: widget.hotelId),
                ),
              ),
              icon: const Icon(Icons.manage_search_outlined),
              tooltip: context.tr('track_booking'),
            ),
          ],
        ),
        body: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) return const AppLoadingView();
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _load,
                child: Text(context.tr('retry')),
              ),
            ],
          ),
        ),
      );
    }
    final hotel = _categoriesRes?['hotel'] as Map<String, dynamic>?;
    final hotelName = hotel?['name'] ?? 'Hotel';
    var categories = (_categoriesRes?['categories'] as List<dynamic>?) ?? [];
    if (widget.searchContext != null) {
      categories = categories.where((c) {
        final m = c as Map<String, dynamic>;
        return ((m['available_rooms'] as num?)?.toInt() ?? 0) > 0;
      }).toList();
    }

    final scheme = Theme.of(context).colorScheme;
    final search = widget.searchContext;
    if (customerUseWideBrowseLayout(context)) {
      return CustomerBrowseRefresh(
        onRefresh: _load,
        landscape: true,
        child: _buildLandscapeCategories(
          context,
          hotelName: hotelName,
          categories: categories,
          scheme: scheme,
          search: search,
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _CustomerMadyawHeader(hotelName: hotelName, scheme: scheme),
          if (search != null) ...[
            Card(
              color: scheme.primaryContainer.withValues(alpha: 0.35),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.event_available, color: scheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${context.tr('your_stay', {
                          'checkin': search.checkInIso,
                          'checkout': search.checkOutIso,
                        })}\n'
                        '${context.tr('guest_party_line', {
                          'rooms': '${search.rooms}',
                          'adults': '${search.adults}',
                          'children': '${search.children}',
                        })}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            context.tr('find_your_room'),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            context.tr('find_room_sub'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 20),
          if (categories.isEmpty) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(Icons.event_busy_outlined,
                        size: 48, color: scheme.outline),
                    const SizedBox(height: 12),
                    Text(
                      search != null
                          ? context.tr('no_rooms_for_dates')
                          : context.tr('no_categories_available'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (search != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        context.tr('try_different_dates'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
          ...categories.map((c) {
            final m = c as Map<String, dynamic>;
            final id = '${m['id']}';
            final name = '${m['name']}';
            final imageUrl =
                ChatAttachment.resolveMediaUrl('${m['image_url'] ?? ''}');
            final desc = '${m['description'] ?? ''}'.trim();
            final available = (m['available_rooms'] as num?)?.toInt() ?? 0;
            final availLabel = available == 1
                ? context.tr('one_room_available')
                : context.tr('rooms_available_label', {'n': '$available'});
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Material(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => CustomerRoomsScreen(
                          hotelId: widget.hotelId,
                          categoryId: id,
                          categoryName: name,
                          categoryImageUrl: imageUrl,
                          searchContext: widget.searchContext,
                          hotelName: hotelName,
                        ),
                      ),
                    );
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (imageUrl.isEmpty)
                        Container(
                          height: 140,
                          color: scheme.surfaceContainerHighest,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.category_outlined,
                            size: 48,
                            color: scheme.outline,
                          ),
                        )
                      else
                        NetworkMediaImage(
                          url: imageUrl,
                          height: 140,
                          width: double.infinity,
                          error: Container(
                            height: 140,
                            color: scheme.surfaceContainerHighest,
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.broken_image_outlined,
                              color: scheme.outline,
                              size: 40,
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    name,
                                    softWrap: true,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          height: 1.2,
                                        ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: available > 0
                                        ? scheme.primaryContainer
                                        : scheme.errorContainer
                                            .withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    availLabel,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: available > 0
                                              ? scheme.onPrimaryContainer
                                              : scheme.onErrorContainer,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                            if (desc.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                desc,
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                softWrap: true,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 18,
                                  color: scheme.primary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  context.tr('see_rooms_prices'),
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(
                                        color: scheme.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildLandscapeCategories(
    BuildContext context, {
    required String hotelName,
    required List<dynamic> categories,
    required ColorScheme scheme,
    required CustomerSearchContext? search,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  'assets/branding/madyaw_logo.png',
                  height: 40,
                  width: 40,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.sailing_outlined,
                    size: 32,
                    color: scheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hotelName,
                      softWrap: true,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                    ),
                    Text(
                      context.tr('find_your_room'),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              if (search != null)
                Flexible(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${search.checkInIso} → ${search.checkOutIso}',
                      maxLines: 2,
                      softWrap: true,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (categories.isEmpty)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.event_busy_outlined,
                          size: 48, color: scheme.outline),
                      const SizedBox(height: 12),
                      Text(
                        search != null
                            ? context.tr('no_rooms_for_dates')
                            : context.tr('no_categories_available'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: CustomerLandscapePagedGrid(
                itemCount: categories.length,
                itemBuilder: (context, i) {
                  final m = categories[i] as Map<String, dynamic>;
                  final id = '${m['id']}';
                  final name = '${m['name']}';
                  final imageUrl =
                      ChatAttachment.resolveMediaUrl('${m['image_url'] ?? ''}');
                  final desc = '${m['description'] ?? ''}'.trim();
                  final available = (m['available_rooms'] as num?)?.toInt() ?? 0;
                  final availLabel = available == 1
                      ? context.tr('one_room_available')
                      : context.tr('rooms_available_label', {'n': '$available'});
                  return CustomerLandscapeCategoryTile(
                    name: name,
                    imageUrl: imageUrl,
                    availLabel: availLabel,
                    available: available > 0,
                    description: desc.isEmpty ? null : desc,
                    onTap: () {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => CustomerRoomsScreen(
                            hotelId: widget.hotelId,
                            categoryId: id,
                            categoryName: name,
                            categoryImageUrl: imageUrl,
                            searchContext: widget.searchContext,
                            hotelName: hotelName,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// Branded header for the public customer booking flow (MADYAW logo asset).
class _CustomerMadyawHeader extends StatelessWidget {
  const _CustomerMadyawHeader({
    required this.hotelName,
    required this.scheme,
  });

  final String hotelName;
  final ColorScheme scheme;

  static const _logoBackground = Color(0xFFE0E4E8);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: ColoredBox(
          color: _logoBackground,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 22),
            child: Column(
              children: [
                Image.asset(
                  'assets/branding/madyaw_logo.png',
                  height: 130,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.sailing_outlined,
                    size: 72,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  hotelName,
                  textAlign: TextAlign.center,
                  softWrap: true,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1A304D),
                        height: 1.25,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CustomerRoomsScreen extends StatefulWidget {
  const CustomerRoomsScreen({
    super.key,
    required this.hotelId,
    required this.categoryId,
    required this.categoryName,
    this.categoryImageUrl = '',
    this.searchContext,
    this.hotelName = 'Hotel',
    this.adminLocalBooking = false,
    this.onBooked,
  });

  final String hotelId;
  final String categoryId;
  final String categoryName;
  final String categoryImageUrl;
  final CustomerSearchContext? searchContext;
  final String hotelName;
  /// When true, booking form matches customer UI but saves via `/admin/bookings` (local).
  final bool adminLocalBooking;
  final Future<void> Function()? onBooked;

  @override
  State<CustomerRoomsScreen> createState() => _CustomerRoomsScreenState();
}

class _CustomerRoomsScreenState extends State<CustomerRoomsScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;
  bool _booking = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final params = <String, dynamic>{'hotel_id': widget.hotelId};
      if (widget.searchContext != null) {
        params.addAll(widget.searchContext!.queryParams);
      }
      final res = await publicDio().get<Map<String, dynamic>>(
        '/customer/categories/${widget.categoryId}/rooms',
        queryParameters: params,
      );
      setState(() {
        _data = res.data;
        _loading = false;
      });
    } on DioException catch (e) {
      setState(() {
        _error = dioErrorMessage(e);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  bool _searchUsesReservationApi() {
    final ctx = widget.searchContext;
    if (ctx == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final checkIn =
        DateTime(ctx.checkIn.year, ctx.checkIn.month, ctx.checkIn.day);
    return checkIn.isAfter(today);
  }

  Future<void> _bookRoom(
    Map<String, dynamic> room, {
    required bool reserve,
  }) async {
    final adminLocal = widget.adminLocalBooking;
    final fromSearch = widget.searchContext != null;
    final forceReserve = !adminLocal && (fromSearch || reserve);
    final savedGuest = await AuthStorage.customerGuestContact();
    if (!mounted) return;

    final nameCtrl = TextEditingController(text: savedGuest?.name ?? '');
    final emailCtrl = TextEditingController(text: savedGuest?.email ?? '');
    final phoneCtrl = TextEditingController(text: savedGuest?.phone ?? '');
    final checkInCtrl = TextEditingController();
    final checkOutCtrl = TextEditingController();
    DateTime? checkInDate = fromSearch ? widget.searchContext!.checkIn : null;
    DateTime? checkOutDate = fromSearch ? widget.searchContext!.checkOut : null;
    if (adminLocal && !fromSearch) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      checkInDate = today;
      checkOutDate = today.add(const Duration(days: 1));
    }
    if (fromSearch) {
      checkInCtrl.text = widget.searchContext!.checkInIso;
      checkOutCtrl.text = widget.searchContext!.checkOutIso;
    } else if (adminLocal && checkInDate != null && checkOutDate != null) {
      checkInCtrl.text = checkInDate.toIso8601String().split('T').first;
      checkOutCtrl.text = checkOutDate.toIso8601String().split('T').first;
    }
    var discountType = 'none';
    var paymentMethod = 'Cash';
    XFile? discountIdFile;
    XFile? guestIdFile;
    String paymentQrUrl = '';
    var qrLoading = false;

    Future<void> loadPaymentQr(void Function(void Function()) setLocal) async {
      setLocal(() => qrLoading = true);
      try {
        final res = await publicDio().get<Map<String, dynamic>>(
          '/customer/payment-qr',
          queryParameters: {'hotel_id': widget.hotelId},
        );
        paymentQrUrl = (res.data?['qr_url'] ?? '').toString();
      } catch (_) {
        paymentQrUrl = '';
      } finally {
        setLocal(() => qrLoading = false);
      }
    }

    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          final nights = (checkInDate != null && checkOutDate != null)
              ? checkOutDate!.difference(checkInDate!).inDays
              : 0;
          final safeNights = nights > 0 ? nights : 0;
          final estTotal = (checkInDate != null && checkOutDate != null)
              ? HourlyBilling.customerDateStayCharge(
                  room,
                  checkInDate!,
                  checkOutDate!,
                )
              : 0.0;
          final discountPct = switch (discountType) {
            'pwd' => 20.0,
            'senior' => 20.0,
            _ => 0.0,
          };
          final estAfterDiscount = HourlyBilling.round50(
            estTotal * (1 - (discountPct / 100)),
          );
          final durationLabel = (checkInDate != null && checkOutDate != null)
              ? (HourlyBilling.isHourly(room)
                  ? () {
                      final inAt = HourlyBilling.customerStayCheckIn(checkInDate!);
                      final outAt = HourlyBilling.customerStayCheckOut(
                        room,
                        checkInDate!,
                        checkOutDate!,
                      );
                      final hours = HourlyBilling.stayHours(inAt, outAt);
                      final blocks = HourlyBilling.blocksForStay(
                        hours,
                        HourlyBilling.blockHours(room),
                      );
                      return '$hours hr(s) · $blocks block(s) of ${HourlyBilling.blockHours(room)}h';
                    }()
                  : '$safeNights night${safeNights == 1 ? '' : 's'}')
              : '';

          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final firstCheckIn =
              forceReserve ? today.add(const Duration(days: 1)) : today;

          Future<void> pickCheckIn() async {
            if (fromSearch) return;
            final picked = await showDatePicker(
              context: context,
              firstDate: firstCheckIn,
              lastDate: forceReserve
                  ? today.add(const Duration(days: 365))
                  : today,
              initialDate: checkInDate ?? firstCheckIn,
            );
            if (picked == null) return;
            checkInDate = picked;
            if (checkOutDate != null && !checkOutDate!.isAfter(picked)) {
              checkOutDate = null;
              checkOutCtrl.clear();
            }
            checkInCtrl.text = picked.toIso8601String().split('T').first;
            setLocal(() {});
          }

          Future<void> pickCheckOut() async {
            if (fromSearch) return;
            if (checkInDate == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.tr('select_checkin_first'))),
              );
              return;
            }
            final picked = await showDatePicker(
              context: context,
              firstDate: HourlyBilling.isHourly(room) && !forceReserve
                  ? checkInDate!
                  : checkInDate!.add(const Duration(days: 1)),
              lastDate: checkInDate!.add(const Duration(days: 365)),
              initialDate: checkOutDate ??
                  (HourlyBilling.isHourly(room) && !forceReserve
                      ? checkInDate!
                      : checkInDate!.add(const Duration(days: 1))),
            );
            if (picked == null) return;
            checkOutDate = picked;
            checkOutCtrl.text = picked.toIso8601String().split('T').first;
            setLocal(() {});
          }

          return AlertDialog(
            title: Text(
              adminLocal
                  ? 'Complete your booking'
                  : (fromSearch
                      ? context.tr('complete_booking')
                      : (forceReserve
                          ? context.tr('request_reservation')
                          : context.tr('book_room_title'))),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (fromSearch && widget.searchContext != null) ...[
                    Card(
                      color: Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withValues(alpha: 0.35),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'From your search',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              context.tr('guest_party_line', {
                                'rooms': '${widget.searchContext!.rooms}',
                                'adults': '${widget.searchContext!.adults}',
                                'children': '${widget.searchContext!.children}',
                              }),
                            ),
                            Text(
                              '${widget.searchContext!.checkInIso} → ${widget.searchContext!.checkOutIso}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  AppInput(controller: nameCtrl, label: context.tr('full_name')),
                  const SizedBox(height: 8),
                  AppInput(
                    controller: emailCtrl,
                    label: context.tr('email_gmail'),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 8),
                  AppInput(
                    controller: phoneCtrl,
                    label: context.tr('phone_number'),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final file = await ChatAttachment.pick(context);
                      if (file != null) setLocal(() => guestIdFile = file);
                    },
                    icon: const Icon(Icons.credit_card_outlined),
                    label: Text(
                      guestIdFile == null
                          ? (fromSearch
                              ? 'Upload government ID *'
                              : 'Upload government ID (optional)')
                          : 'ID attached — tap to replace',
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: discountType,
                    decoration: const InputDecoration(
                      labelText: 'Discount (optional)',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'none', child: Text('No discount')),
                      DropdownMenuItem(value: 'pwd', child: Text('PWD (20% off)')),
                      DropdownMenuItem(
                        value: 'senior',
                        child: Text('Senior citizen (20% off)'),
                      ),
                    ],
                    onChanged: (v) => setLocal(() {
                      discountType = v ?? 'none';
                      if (discountType == 'none') discountIdFile = null;
                    }),
                  ),
                  if (discountType != 'none') ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final file = await ChatAttachment.pick(context);
                        if (file != null) setLocal(() => discountIdFile = file);
                      },
                      icon: const Icon(Icons.badge_outlined),
                      label: Text(
                        discountIdFile == null
                            ? 'Upload discount ID photo'
                            : 'Discount ID attached — tap to replace',
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  AppInput(
                    controller: checkInCtrl,
                    label: fromSearch
                        ? 'Check-in'
                        : (forceReserve
                            ? 'Check-in (from tomorrow)'
                            : 'Check-in (today for walk-in)'),
                    hint: fromSearch ? null : 'Tap to open calendar',
                    readOnly: true,
                    onTap: fromSearch ? null : pickCheckIn,
                    suffixIcon: const Icon(Icons.calendar_month_outlined),
                  ),
                  const SizedBox(height: 8),
                  AppInput(
                    controller: checkOutCtrl,
                    label: 'Check-out date',
                    hint: fromSearch ? null : 'Tap to open calendar',
                    readOnly: true,
                    onTap: fromSearch ? null : pickCheckOut,
                    suffixIcon: const Icon(Icons.calendar_month_outlined),
                  ),
                  if (fromSearch || adminLocal) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: paymentMethod,
                      decoration: const InputDecoration(
                        labelText: 'Payment method',
                        border: OutlineInputBorder(),
                      ),
                      items: adminLocal
                          ? const [
                              DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                              DropdownMenuItem(value: 'GCash', child: Text('GCash')),
                              DropdownMenuItem(value: 'PayMaya', child: Text('PayMaya')),
                              DropdownMenuItem(
                                value: 'Credit Card',
                                child: Text('Credit Card'),
                              ),
                            ]
                          : const [
                              DropdownMenuItem(value: 'Cash', child: Text('Cash at hotel')),
                              DropdownMenuItem(value: 'Online', child: Text('Online (QR Ph)')),
                            ],
                      onChanged: (v) async {
                        final next = v ?? 'Cash';
                        setLocal(() => paymentMethod = next);
                        if (!adminLocal &&
                            next == 'Online' &&
                            paymentQrUrl.isEmpty) {
                          await loadPaymentQr(setLocal);
                        }
                      },
                    ),
                    if (!adminLocal && paymentMethod == 'Online') ...[
                      const SizedBox(height: 12),
                      if (qrLoading)
                        const Center(child: CircularProgressIndicator())
                      else if (paymentQrUrl.isEmpty)
                        const Text(
                          'Hotel has not uploaded a payment QR yet. You may still submit — pay at the desk if needed.',
                          style: TextStyle(fontSize: 12),
                        )
                      else
                        Center(
                          child: Column(
                            children: [
                              const Text(
                                'Scan to pay via GCash / Maya / QR Ph',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 8),
                              NetworkMediaImage(
                                url: paymentQrUrl,
                                width: 200,
                                height: 200,
                                fit: BoxFit.contain,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      fromSearch
                          ? 'Duration: $durationLabel\n'
                              'Estimated: ₱${estTotal.toStringAsFixed(2)}'
                              '${discountPct > 0 ? ' → ₱${estAfterDiscount.toStringAsFixed(2)} after discount' : ''}\n'
                              'Your request will be reviewed by the hotel.'
                          : forceReserve
                              ? 'The hotel will approve your dates. You will be notified when the stay is activated on check-in day.'
                              : 'Duration: $durationLabel\n'
                                  'Estimated: ₱${estTotal.toStringAsFixed(2)}'
                                  '${discountPct > 0 ? ' → ₱${estAfterDiscount.toStringAsFixed(2)} after discount' : ''}',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              AppPrimaryButton(
                label: adminLocal || fromSearch
                    ? 'Submit booking'
                    : (forceReserve ? 'Submit request' : 'Book now'),
                onPressed: () {
                  final name = nameCtrl.text.trim();
                  final email = emailCtrl.text.trim();
                  final phone = phoneCtrl.text.trim();
                  if (name.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Enter your full name.')),
                    );
                    return;
                  }
                  if (email.isEmpty || !email.contains('@')) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Enter a valid email address.')),
                    );
                    return;
                  }
                  if (phone.length < 7) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Enter a valid phone number.')),
                    );
                    return;
                  }
                  if (fromSearch && guestIdFile == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Upload your government ID.')),
                    );
                    return;
                  }
                  if (discountType != 'none' && discountIdFile == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Upload a photo of your discount ID.'),
                      ),
                    );
                    return;
                  }
                  if (checkInCtrl.text.trim().isEmpty ||
                      checkOutCtrl.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Select check-in and check-out.')),
                    );
                    return;
                  }
                  Navigator.of(context).pop({
                    'room_id': (room['id'] ?? '').toString(),
                    'guest_name': nameCtrl.text.trim(),
                    'guest_email': emailCtrl.text.trim(),
                    'guest_phone': phoneCtrl.text.trim(),
                    'check_in': checkInCtrl.text.trim(),
                    'check_out': checkOutCtrl.text.trim(),
                    'discount_type': discountType,
                    if (fromSearch || adminLocal) 'payment_method': paymentMethod,
                  });
                },
              ),
            ],
          );
        },
      ),
    );
    if (payload == null || _booking) return;

    if (adminLocal) {
      setState(() => _booking = true);
      try {
        await submitAdminWalkInBooking(
          room: room,
          payload: CompleteGuestBookingPayload(
            guestName: (payload['guest_name'] ?? '').toString(),
            guestEmail: (payload['guest_email'] ?? '').toString(),
            guestPhone: (payload['guest_phone'] ?? '').toString(),
            checkIn: (payload['check_in'] ?? '').toString(),
            checkOut: (payload['check_out'] ?? '').toString(),
            discountType: (payload['discount_type'] ?? 'none').toString(),
            paymentMethod: (payload['payment_method'] ?? 'Cash').toString(),
            guestIdFile: guestIdFile,
            discountIdFile: discountIdFile,
          ),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Room ${room['room_number']} booked as a local walk-in.',
            ),
          ),
        );
        await widget.onBooked?.call();
        await _load();
      } on DioException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(dioErrorMessage(e))),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      } finally {
        if (mounted) setState(() => _booking = false);
      }
      return;
    }

    setState(() => _booking = true);
    try {
      final checkInIso = (payload['check_in'] ?? '').toString();
      final path = customerStayUsesReservationApi(
            reserveIntent: reserve,
            checkInIso: checkInIso,
          )
          ? '/customer/reservations'
          : '/customer/bookings';
      final discount = (payload['discount_type'] ?? 'none').toString();
      final Map<String, dynamic> body = {
        'hotel_id': widget.hotelId,
        ...payload,
      };
      if (widget.searchContext != null) {
        body['rooms'] = widget.searchContext!.rooms;
        body['adults'] = widget.searchContext!.adults;
        body['children'] = widget.searchContext!.children;
      }

      await AuthStorage.setCustomerGuestContact(
        name: (payload['guest_name'] ?? '').toString(),
        email: (payload['guest_email'] ?? '').toString(),
        phone: (payload['guest_phone'] ?? '').toString(),
      );

      final Response<Map<String, dynamic>> res;
      final hasDiscountFile = discount != 'none' && discountIdFile != null;
      final hasGuestId = guestIdFile != null;

      if (hasDiscountFile || hasGuestId) {
        body.remove('discount_type');
        final map = <String, dynamic>{};
        for (final entry in body.entries) {
          final v = entry.value;
          if (v != null) {
            map[entry.key] = v is num || v is bool ? v.toString() : v;
          }
        }
        if (discount != 'none') map['discount_type'] = discount;
        if (hasGuestId) {
          map['guest_id_file'] = await MultipartFile.fromFile(
            guestIdFile!.path,
            filename: guestIdFile!.name.isNotEmpty ? guestIdFile!.name : 'guest_id.jpg',
          );
        }
        if (hasDiscountFile) {
          map['discount_id_file'] = await MultipartFile.fromFile(
            discountIdFile!.path,
            filename: discountIdFile!.name.isNotEmpty ? discountIdFile!.name : 'discount_id.jpg',
          );
        }
        res = await publicDio().post<Map<String, dynamic>>(
          path,
          data: FormData.fromMap(map),
        );
      } else {
        res = await publicDio().post<Map<String, dynamic>>(path, data: body);
      }
      if (!mounted) return;
      final booking = res.data?['booking'] as Map<String, dynamic>?;
      final reservation = res.data?['reservation'] as Map<String, dynamic>?;
      final ref = (reservation?['external_reference'] ??
              booking?['booking_reference'] ??
              '')
          .toString();
      final guestEmail = (payload['guest_email'] ?? '').toString();
      final usedReservationApi = customerStayUsesReservationApi(
        reserveIntent: reserve,
        checkInIso: checkInIso,
      );

      if (fromSearch && ref.isNotEmpty) {
        if (!mounted) return;
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => CustomerBookingStatusScreen(
              hotelId: widget.hotelId,
              hotelName: widget.hotelName,
              reference: ref,
              guestEmail: guestEmail,
              initialReservation: reservation != null
                  ? Map<String, dynamic>.from(reservation)
                  : null,
            ),
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            usedReservationApi
                ? 'Request sent (ref ${ref.isEmpty ? 'pending' : ref}). Awaiting hotel approval.'
                : 'Booking submitted: ${ref.isEmpty ? 'Reference generated' : ref}',
          ),
        ),
      );
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(dioErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LocaleScope(
      builder: (context, _) => AppScaffold(
        appBar: AppBar(
          title: Text(widget.categoryName),
          actions: [
            IconButton(onPressed: _load, icon: const Icon(Icons.refresh))
          ],
        ),
        body: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) return const AppLoadingView();
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _load,
                child: Text(context.tr('retry')),
              ),
            ],
          ),
        ),
      );
    }
    final allRooms = (_data!['rooms'] as List<dynamic>?) ?? [];
    final rooms = allRooms.where((raw) {
      final r = raw as Map<String, dynamic>;
      final status = '${r['status'] ?? ''}'.toLowerCase();
      return status == 'available' || status.isEmpty;
    }).toList();
    final category = _data?['category'] as Map<String, dynamic>?;
    final categoryBanner = ChatAttachment.resolveMediaUrl(
      '${category?['image_url'] ?? widget.categoryImageUrl}',
    );
    final scheme = Theme.of(context).colorScheme;
    if (customerUseWideBrowseLayout(context)) {
      return CustomerBrowseRefresh(
        onRefresh: _load,
        landscape: true,
        child: _buildLandscapeRooms(context, rooms, scheme),
      );
    }
    if (rooms.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            if (categoryBanner.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: NetworkMediaImage(
                  url: categoryBanner,
                  height: 180,
                  width: double.infinity,
                  error: const SizedBox.shrink(),
                ),
              ),
              const SizedBox(height: 24),
            ],
            Icon(Icons.bed_outlined, size: 56, color: scheme.outline),
            const SizedBox(height: 16),
            Text(
              widget.searchContext != null
                  ? 'No rooms free for your dates in this category.'
                  : 'No rooms available in this category.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Try another category or adjust your stay dates.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: rooms.length + (categoryBanner.isEmpty ? 0 : 1),
        itemBuilder: (context, i) {
          if (categoryBanner.isNotEmpty && i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: NetworkMediaImage(
                  url: categoryBanner,
                  height: 180,
                  width: double.infinity,
                  error: const SizedBox.shrink(),
                ),
              ),
            );
          }
          final roomIndex = categoryBanner.isEmpty ? i : i - 1;
          final r = rooms[roomIndex] as Map<String, dynamic>;
          final roomNo = '${r['room_number'] ?? ''}';
          final title = '${r['display_name'] ?? r['room_number']}';
          final priceLabel = HourlyBilling.priceLabel(r);
          final surge = r['base_price_per_night'] != null &&
              r['base_price_per_night'] != r['price_per_night'];
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Material(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAlias,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Stack(
                      children: [
                        NetworkMediaImage(
                          url: (r['image_url'] ?? '').toString(),
                          height: 160,
                          width: double.infinity,
                          error: Container(
                            height: 160,
                            color: scheme.surfaceContainerHighest,
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.bed_outlined,
                              size: 40,
                              color: scheme.outline,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 10,
                          right: 10,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              child: Text(
                                priceLabel,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ),
                              Chip(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                label: const Text(
                                  'Available',
                                  style: TextStyle(fontSize: 12),
                                ),
                                backgroundColor: scheme.primaryContainer,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Room $roomNo'
                            '${surge ? ' · Includes demand pricing' : ''}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 12),
                          if (widget.adminLocalBooking)
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: _booking
                                    ? null
                                    : () => _bookRoom(r, reserve: false),
                                child: const Text('Book this room'),
                              ),
                            )
                          else if (widget.searchContext != null)
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: _booking
                                    ? null
                                    : () => _bookRoom(
                                          r,
                                          reserve: _searchUsesReservationApi(),
                                        ),
                                child: const Text('Book this room'),
                              ),
                            )
                          else
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: _booking
                                        ? null
                                        : () => _bookRoom(r, reserve: true),
                                    child: const Text('Reserve'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: FilledButton(
                                    onPressed: _booking
                                        ? null
                                        : () => _bookRoom(r, reserve: false),
                                    child: const Text('Book'),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLandscapeRooms(
    BuildContext context,
    List<dynamic> rooms,
    ColorScheme scheme,
  ) {
    final fromSearch = widget.searchContext != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.categoryName,
                  softWrap: true,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                ),
              ),
              if (rooms.isNotEmpty)
                Text(
                  '${rooms.length} available',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (rooms.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.bed_outlined, size: 48, color: scheme.outline),
                    const SizedBox(height: 12),
                    Text(
                      widget.searchContext != null
                          ? 'No rooms free for your dates in this category.'
                          : 'No rooms available in this category.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: CustomerLandscapePagedGrid(
                itemCount: rooms.length,
                itemBuilder: (context, i) {
                  final r = rooms[i] as Map<String, dynamic>;
                  final title = '${r['display_name'] ?? r['room_number']}';
                  final priceLabel = HourlyBilling.priceLabel(r);
                  return CustomerLandscapeRoomTile(
                    title: title,
                    priceLabel: priceLabel,
                    imageUrl: (r['image_url'] ?? '').toString(),
                    busy: _booking,
                    onBook: () => _bookRoom(
                          r,
                          reserve: widget.adminLocalBooking
                              ? false
                              : (fromSearch
                                  ? _searchUsesReservationApi()
                                  : false),
                        ),
                    onReserve: widget.adminLocalBooking || fromSearch
                        ? null
                        : () => _bookRoom(r, reserve: true),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
