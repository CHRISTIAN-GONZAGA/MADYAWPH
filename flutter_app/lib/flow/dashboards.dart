import 'dart:async';
import 'package:gloretto_mobile/widgets/app_notice.dart';

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
import 'widgets/extend_stay_dialog.dart';
import 'admin/widgets/admin_opaque_scaffold.dart';
import '../widgets/app_state_views.dart';
import '../widgets/dashboard_clock.dart';
import '../widgets/dashboard_exit_guard.dart';
import 'admin/admin_dashboard_models.dart';
import 'admin/widgets/portal_shift_session.dart';
import 'admin/widgets/front_desk_shift.dart';
import 'admin/admin_dashboard_shell.dart';
import 'admin/admin_notification_emails_screen.dart';
import 'admin/widgets/admin_room_detail_navigation.dart';
import 'admin/widgets/admin_hotel_totals_room_panel.dart';
import 'admin/widgets/admin_walk_in_customer_booking.dart';
import 'admin/widgets/hourly_billing.dart';
import 'customer_room_detail_screen.dart';
import 'customer_browse_layout.dart';
import 'customer_landscape_grid.dart';
import 'customer_search_context.dart';
import 'customer_tools.dart';
import '../widgets/chat_attachment.dart';
import '../widgets/payment_redirect.dart';
import '../utils/money_format.dart';
import 'portal_sign_out.dart';
// --- Admin ---

/// Public customer bookings always use the reservation request API (admin approval required).
bool customerStayUsesReservationApi({
  required String checkInIso,
}) {
  return true;
}

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({
    super.key,
    this.isSuperAdmin = false,
    this.isFrontDesk = false,
  });

  /// When true, shows the same dashboard plus the admin control panel tab.
  final bool isSuperAdmin;

  /// Front desk staff — operational tabs only (no setup / resellers).
  final bool isFrontDesk;

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
  bool Function()? _panelBackHandler;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _dashboardPoll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted || AdminRoomDetailNavigation.isRoomOverlayOpen) return;
      _load(silent: true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        mounted &&
        !AdminRoomDetailNavigation.isRoomOverlayOpen) {
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
          await portalDioWithLongTimeout().get<Map<String, dynamic>>('/admin/dashboard');
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
      showAppMessage(context, msg);
      await _load(silent: true);
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, '$label failed: ${dioErrorMessage(e)}', isError: true);
    } catch (e) {
      if (!mounted) return;
      showAppMessage(context, '$label failed: $e');
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
      showAppMessage(context, 'Surge pricing updated.');
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
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
    return HotelTotalsRoomPanelHost(
      onBindBackHandler: (handler) => _panelBackHandler = handler,
      onRefresh: () => _load(silent: true),
      resolveLiveRooms: () => AdminDashboardModels.parseRoomMaps(
        _data?['rooms'] as List<dynamic>?,
      ),
      child: DashboardExitGuard(
        navigatorKey: adminDashboardNavigatorKey,
        onRequestInnerPop: () =>
            (_panelBackHandler?.call() ?? false) ||
            (_shellBackHandler?.call() ?? false),
        child: Scaffold(
          body: _buildBody(context),
        ),
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
    var isFrontDesk = widget.isFrontDesk;
    final auth = _data!['auth'] as Map<String, dynamic>?;
    final user = auth?['user'] as Map<String, dynamic>?;
    final userRole = (user?['role'] ?? '').toString();
    if (userRole == 'super_admin') {
      isSuper = true;
    }
    if (userRole == 'frontdesk') {
      isFrontDesk = true;
    }

    return Column(
      children: [
        if (_refreshing) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: Navigator(
            key: adminDashboardNavigatorKey,
            initialRoute: '/',
            onGenerateRoute: (settings) {
              return MaterialPageRoute<void>(
                builder: (_) => AdminDashboardShell(
                  data: _data!,
                  isSuperAdmin: isSuper,
                  isFrontDesk: isFrontDesk,
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
    AdminRoomDetailNavigation.pushSummaryList(
      context: context,
      title: title,
      rooms: list,
      showGuest: showGuest,
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
  FrontDeskShift? _shift;
  bool _shiftPromptShown = false;
  Timer? _shiftPoll;

  @override
  void initState() {
    super.initState();
    _load();
    _shiftPoll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _shift != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _shiftPoll?.cancel();
    super.dispose();
  }

  Future<void> _initStaffShift() async {
    final auth = (_data?['auth'] as Map<String, dynamic>?)?['user']
        as Map<String, dynamic>?;
    final userId = (auth?['id'] ?? auth?['_id'] ?? '').toString();
    final hotelId = (auth?['hotel_id'] ?? auth?['hotelId'] ?? '').toString();
    final staffName = (auth?['name'] ?? auth?['username'] ?? 'Staff').toString();
    if (userId.isEmpty || hotelId.isEmpty || !mounted) return;

    final shift = await PortalShiftSession.ensureShift(
      context: context,
      userId: userId,
      hotelId: hotelId,
      staffName: staffName,
      shiftPromptShown: _shiftPromptShown,
      onPromptShown: (shown) => _shiftPromptShown = shown,
      shiftSetupTitle: 'Start staff shift',
      shiftSetupDescription:
          'Set your time in and scheduled time out for this staff session.',
    );
    if (mounted) setState(() => _shift = shift);
  }

  Future<void> _handleTimeOut() async {
    final shift = _shift;
    if (shift == null || !shift.canTimeOut) return;
    await PortalShiftSession.handleTimeOut(
      context: context,
      shift: shift,
      summaryTitle: 'Staff shift summary',
    );
    if (!mounted) return;
    setState(() => _shift = null);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res =
          await portalDioWithLongTimeout().get<Map<String, dynamic>>('/staff/dashboard');
      setState(() {
        _data = res.data;
        _loading = false;
      });
      if (mounted) {
        await _initStaffShift();
      }
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
      showAppMessage(context, 'New passwords do not match.');
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
      showAppMessage(context, 'Staff profile updated.');
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
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
          if (_shift != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                onPressed: _shift!.canTimeOut ? _handleTimeOut : null,
                child: Text(
                  PortalShiftSession.timeOutButtonLabel(_shift),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
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
      showAppMessage(context, 'Task updated to $status.');
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
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
      showAppMessage(context, dioErrorMessage(e), isError: true);
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
        showAppMessage(context, 'Could not refresh messages.');
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
      showAppMessage(context, dioErrorMessage(e), isError: true);
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
      showAppMessage(context, dioErrorMessage(e), isError: true);
    } catch (e) {
      if (!mounted) return;
      showAppMessage(context, '$e');
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
      showAppMessage(context, msg);
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      if (e.response?.statusCode == 401) {
        await _signOut();
        return;
      }
      showAppMessage(context, '$label failed: ${dioErrorMessage(e)}', isError: true);
    } catch (e) {
      if (!mounted) return;
      showAppMessage(context, '$label failed: $e');
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
      showAppMessage(context, 'No amenity menu available yet.');
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

    final payload = await showExtendStayDialog(
      context,
      roomInfo: roomInfo,
      maxPickerHours: 10,
    );
    if (payload == null) {
      if (!mounted) return;
      if (isHourly) {
        showAppMessage(context, 'Extension is not available. Ask the front desk to set the category extra-hour rate.',);
      }
      return;
    }

    await _runGuestAction('Extend stay', () async {
      final res = await guestDio().post<Map<String, dynamic>>(
        '/guest/extend-stay',
        data: isHourly
            ? payload
            : {'nights': payload['nights']},
      );
      final checkout = res.data?['new_checkout_date'] ?? '-';
      final checkoutTime = res.data?['new_checkout_time'];
      final when = checkoutTime != null ? '$checkout $checkoutTime' : checkout;
      final fee = parseJsonDouble(res.data?['extension_fee']);
      return {
        'message':
            'Extended stay. New checkout: $when, additional fee: ${formatPeso(fee)}',
      };
    });
  }

  Future<void> _submitReview() async {
    final room = _data?['roomInfo'] as Map<String, dynamic>?;
    final bookingId = room?['activeBookingId']?.toString() ?? '';
    if (bookingId.isEmpty) {
      showAppMessage(context, 'No active booking found.');
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
    final bill = _data!['currentBill'] as Map<String, dynamic>?;
    final billCharges = (bill?['charges'] as List<dynamic>?) ?? [];
    final hotel = u?['hotelName'] ?? 'Hotel';
    final roomNo = room?['roomNumber'] ?? '—';
    final checkoutDate = room?['checkOutAt']?.toString() ?? '—';
    final checkoutTime = room?['checkOutTime']?.toString();
    final checkout = checkoutTime != null && checkoutTime.isNotEmpty
        ? '$checkoutDate $checkoutTime'
        : checkoutDate;

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
                Text('Current bill',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (bill == null)
                  const Text('No active booking bill.')
                else ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Payment: ${(bill['paymentStatus'] ?? 'unpaid').toString()}',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              Text(
                                formatPeso(
                                  parseJsonDouble(
                                    bill['totalDue'] ??
                                        bill['chargesTotal'] ??
                                        bill['bookingTotal'],
                                  ),
                                ),
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                          if (billCharges.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text('No charges yet.'),
                            )
                          else
                            ...billCharges.take(15).map((raw) {
                              final line = Map<String, dynamic>.from(
                                raw as Map,
                              );
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        (line['label'] ?? 'Charge').toString(),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ),
                                    Text(
                                      formatBillLineAmount(line),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                AppActionTile(
                  title: 'Request amenity',
                  subtitle: 'Submit a housekeeping/amenity claim',
                  icon: Icons.room_service_outlined,
                  onTap: _claimAmenity,
                ),
                AppActionTile(
                  title: 'Extend stay',
                  subtitle: (room?['billingMode'] ?? 'nightly')
                              .toString()
                              .toLowerCase() ==
                          'hourly'
                      ? 'Add 1–10 hours at the category hourly rate'
                      : 'Add more nights to your stay',
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
  String _portalRole = '';

  bool _isFrontDeskOnly() => _portalRole == 'frontdesk';

  @override
  void initState() {
    super.initState();
    _loadDefaults();
  }

  Future<void> _loadDefaults() async {
    final role = (await AuthStorage.portalRole()) ?? '';
    var isSuper = role == 'super_admin';
    var resolvedRole = role;
    try {
      final r = await portalDioWithLongTimeout().get<Map<String, dynamic>>('/admin/dashboard');
      final u =
          (r.data?['auth'] as Map<String, dynamic>?)?['user'] as Map<String, dynamic>?;
      final n = (u?['name'] ?? '').toString();
      final apiRole = (u?['role'] ?? '').toString();
      if (apiRole.isNotEmpty) {
        resolvedRole = apiRole;
      }
      if (apiRole == 'super_admin') {
        isSuper = true;
      }
      if (mounted && n.isNotEmpty) {
        _nameCtrl.text = n;
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _isSuperAdmin = isSuper;
        _portalRole = resolvedRole;
      });
    }
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
      showAppMessage(context, 'Enter a username / display name.');
      return;
    }
    final hasNew = _adminNewPass.text.isNotEmpty;
    if (hasNew && _adminNewPass.text != _adminNewPass2.text) {
      showAppMessage(context, 'New passwords do not match.');
      return;
    }
    if (hasNew && _adminCurrentPass.text.isEmpty) {
      showAppMessage(context, 'Enter your current password to set a new one.');
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
      showAppMessage(context, 'Admin profile updated.');
      _adminCurrentPass.clear();
      _adminNewPass.clear();
      _adminNewPass2.clear();
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
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
          if (_isSuperAdmin || !_isFrontDeskOnly()) ...[
            const SizedBox(height: 28),
            Text(
              'Notification Gmail',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              _isSuperAdmin
                  ? 'Set owner Gmail, your super-admin Gmail, and the administrator Gmail for guest check-in and room status alerts.'
                  : 'Set owner Gmail and your admin Gmail for guest check-in and room status alerts.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminNotificationEmailsScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.mark_email_read_outlined),
              label: const Text('Manage owner & notification Gmail'),
            ),
          ],
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
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          height: 1.2,
                                        ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
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
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.end,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: available > 0
                                                ? scheme.onPrimaryContainer
                                                : scheme.onErrorContainer,
                                          ),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackHeader = constraints.maxWidth < 560;

        Widget searchChip() {
          if (search == null) return const SizedBox.shrink();
          return Container(
            width: stackHeader ? double.infinity : null,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${search.checkInIso} → ${search.checkOutIso}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: stackHeader ? TextAlign.start : TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          );
        }

        final header = stackHeader
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.asset(
                          'assets/branding/madyaw_logo.png',
                          height: 36,
                          width: 36,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.sailing_outlined,
                            size: 28,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              hotelName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    height: 1.15,
                                  ),
                            ),
                            Text(
                              context.tr('find_your_room'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (search != null) ...[
                    const SizedBox(height: 6),
                    searchChip(),
                  ],
                ],
              )
            : Row(
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
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                height: 1.15,
                              ),
                        ),
                        Text(
                          context.tr('find_your_room'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  if (search != null) ...[
                    const SizedBox(width: 8),
                    Flexible(child: searchChip()),
                  ],
                ],
              );

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const SizedBox(height: 8),
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
                      final imageUrl = ChatAttachment.resolveMediaUrl(
                          '${m['image_url'] ?? ''}');
                      final desc = '${m['description'] ?? ''}'.trim();
                      final available =
                          (m['available_rooms'] as num?)?.toInt() ?? 0;
                      final availLabel = available == 1
                          ? context.tr('one_room_available')
                          : context.tr('rooms_available_label',
                              {'n': '$available'});
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
      },
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
    this.hideImages = false,
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
  /// Text-only room cards (no photos). Defaults on for [adminLocalBooking].
  final bool hideImages;
  final Future<void> Function()? onBooked;

  @override
  State<CustomerRoomsScreen> createState() => _CustomerRoomsScreenState();
}

class _CustomerRoomsScreenState extends State<CustomerRoomsScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;
  bool _booking = false;

  bool get _noImages => widget.hideImages || widget.adminLocalBooking;

  /// Customer portal search locks dates; admin walk-in keeps the calendar editable.
  bool get _fromCustomerSearch =>
      widget.searchContext != null && !widget.adminLocalBooking;

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
      final params = <String, dynamic>{
        'hotel_id': widget.hotelId,
        if (widget.adminLocalBooking) 'admin_walk_in': '1',
      };
      if (widget.searchContext != null && !widget.adminLocalBooking) {
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

  bool _searchUsesReservationApi() => true;

  Future<void> _bookRoom(
    Map<String, dynamic> room, {
    required bool reserve,
  }) async {
    final adminLocal = widget.adminLocalBooking;
    if (adminLocal) {
      if (_booking) return;
      setState(() => _booking = true);
      try {
        final booked = await showAdminWalkInCustomerStyleBooking(
          context: context,
          hotelId: widget.hotelId,
          room: room,
        );
        if (!mounted) return;
        if (booked) {
          await widget.onBooked?.call();
          if (mounted) {
            Navigator.of(context).pop();
          }
        }
      } finally {
        if (mounted) setState(() => _booking = false);
      }
      return;
    }

    if (_booking) return;
    setState(() => _booking = true);
    try {
      final category = _data?['category'] as Map<String, dynamic>?;
      final categoryImage = ChatAttachment.resolveMediaUrl(
        '${category?['image_url'] ?? widget.categoryImageUrl}',
      );
      final refreshed = await openCustomerRoomDetail(
        context,
        hotelId: widget.hotelId,
        hotelName: widget.hotelName,
        room: room,
        categoryName: widget.categoryName,
        categoryImageUrl: categoryImage,
        categoryDescription: (category?['description'] ?? '').toString(),
        searchContext: widget.searchContext,
        preferReserve: reserve,
      );
      if (refreshed == true && mounted) {
        await _load();
      }
    } finally {
      if (mounted) setState(() => _booking = false);
    }
    return;
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody(context);
    final appBar = AppBar(
      title: Text(widget.categoryName),
      actions: [
        IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
      ],
    );

    return LocaleScope(
      builder: (context, _) {
        if (widget.adminLocalBooking) {
          return AdminOpaqueScaffold(appBar: appBar, body: body);
        }
        return AppScaffold(appBar: appBar, body: body);
      },
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
    final rooms = widget.searchContext != null || widget.adminLocalBooking
        ? allRooms
        : allRooms.where((raw) {
            final r = raw as Map<String, dynamic>;
            final status = '${r['status'] ?? ''}'.toLowerCase();
            return status == 'available' || status.isEmpty;
          }).toList();
    final category = _data?['category'] as Map<String, dynamic>?;
    final categoryBanner = _noImages
        ? ''
        : ChatAttachment.resolveMediaUrl(
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
    if (_noImages) {
      return _buildCompactRoomsGrid(context, rooms, scheme);
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
                    InkWell(
                      onTap: widget.adminLocalBooking || _booking
                          ? null
                          : () => _bookRoom(
                                r,
                                reserve: widget.searchContext != null
                                    ? _searchUsesReservationApi()
                                    : false,
                              ),
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
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
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
                                label: Text(
                                  widget.searchContext != null
                                      ? 'Available for your dates'
                                      : 'Available',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                backgroundColor: scheme.primaryContainer,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Room $roomNo'
                            '${surge ? ' · Includes demand pricing' : ''}'
                            '${widget.adminLocalBooking ? '' : ' · Tap for details'}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
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
                                child: const Text('View & book'),
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

  int _adminGridCrossAxisCount(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 900) return 6;
    if (width >= 600) return 5;
    if (width >= 400) return 4;
    return 3;
  }

  double _adminGridAspectRatio(BuildContext context) {
    return widget.adminLocalBooking ? 2.15 : 1.08;
  }

  Widget _buildCompactRoomsGrid(
    BuildContext context,
    List<dynamic> rooms,
    ColorScheme scheme,
  ) {
    final crossAxisCount = _adminGridCrossAxisCount(context);
    final dense = widget.adminLocalBooking;
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(dense ? 8 : 12, dense ? 4 : 8, dense ? 8 : 12, 2),
            sliver: SliverToBoxAdapter(
              child: Text(
                dense
                    ? '${rooms.length} available'
                    : '${rooms.length} available · tap a room to book',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(dense ? 8 : 12, 2, dense ? 8 : 12, dense ? 8 : 24),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: dense ? 5 : 8,
                crossAxisSpacing: dense ? 5 : 8,
                childAspectRatio: _adminGridAspectRatio(context),
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => _buildGridRoomTile(
                  context,
                  rooms[i] as Map<String, dynamic>,
                  scheme,
                ),
                childCount: rooms.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _availableBadge(ColorScheme scheme, {bool compact = false}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 5 : 6,
        vertical: compact ? 1 : 2,
      ),
      decoration: BoxDecoration(
        color: Colors.green.shade100,
        borderRadius: BorderRadius.circular(compact ? 6 : 8),
      ),
      child: Text(
        'Avail',
        style: TextStyle(
          fontSize: compact ? 8 : 9,
          fontWeight: FontWeight.w700,
          color: Colors.green.shade800,
        ),
      ),
    );
  }

  void _onGridRoomTap(Map<String, dynamic> room) {
    if (widget.adminLocalBooking) {
      _bookRoom(room, reserve: false);
      return;
    }
    _bookRoom(room, reserve: false);
  }

  Widget _buildGridRoomTile(
    BuildContext context,
    Map<String, dynamic> r,
    ColorScheme scheme,
  ) {
    final roomNo = '${r['room_number'] ?? ''}'.trim();
    final displayName = (r['display_name'] ?? '').toString().trim();
    final priceLabel = HourlyBilling.priceLabel(r);
    final hasSubtitle =
        displayName.isNotEmpty && displayName != roomNo;
    final dense = widget.adminLocalBooking;

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(dense ? 10 : 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _booking ? null : () => _onGridRoomTap(r),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: dense ? 6 : 10,
            vertical: dense ? 4 : 10,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      roomNo.isNotEmpty ? roomNo : '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            fontSize: dense ? 11 : null,
                          ),
                    ),
                  ),
                  if (!widget.adminLocalBooking)
                    _availableBadge(scheme, compact: dense),
                ],
              ),
              if (hasSubtitle) ...[
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontSize: dense ? 9 : 10,
                      ),
                ),
              ],
              Text(
                priceLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: dense ? 9 : 10,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLandscapeRooms(
    BuildContext context,
    List<dynamic> rooms,
    ColorScheme scheme,
  ) {
    final fromSearch = _fromCustomerSearch;
    final search = widget.adminLocalBooking ? null : widget.searchContext;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.categoryName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                          ),
                    ),
                    if (search != null)
                      Text(
                        '${search.checkInIso} → ${search.checkOutIso}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                  ],
                ),
              ),
              if (rooms.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 2),
                  child: Text(
                    '${rooms.length} available',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
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
                  if (_noImages) {
                    return _buildGridRoomTile(context, r, scheme);
                  }
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
