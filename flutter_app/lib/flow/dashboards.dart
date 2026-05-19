import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../auth_storage.dart';
import '../dio_client.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_input.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/app_state_views.dart';
import '../widgets/dashboard_clock.dart';
import 'admin_rooms.dart';
import 'admin_categories.dart';
import 'admin_chat.dart';
import 'admin_bookings.dart';
import 'admin_reports.dart';
import 'admin_staff.dart';
import 'customer_tools.dart';
import '../widgets/chat_attachment.dart';
import '../widgets/payment_redirect.dart';
import 'guest_list_history.dart';
// --- Admin ---

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;
  bool _busyAction = false;

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
          await portalDio().get<Map<String, dynamic>>('/admin/dashboard');
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

  Future<void> _signOut() async {
    await AuthStorage.clearPortalAuth();
    if (mounted) Navigator.of(context).pop();
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
      await _load();
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
    final amountCtrl = TextEditingController(text: '100');
    String method = 'gcash';
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Recharge Credits'),
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
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: method,
                items: const [
                  DropdownMenuItem(value: 'gcash', child: Text('GCash')),
                  DropdownMenuItem(value: 'paymaya', child: Text('PayMaya')),
                ],
                onChanged: (v) => setLocal(() => method = v ?? method),
                decoration: const InputDecoration(
                  labelText: 'Wallet',
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
                'amount': double.tryParse(amountCtrl.text.trim()) ?? 0,
                'method': method,
              }),
              child: const Text('Recharge'),
            ),
          ],
        ),
      ),
    );
    if (payload == null) return;

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
    return AppScaffold(
      appBar: AppBar(
        title: const Text('Admin dashboard'),
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
    final d = _data!;
    final auth = d['auth'] as Map<String, dynamic>?;
    final user = auth?['user'] as Map<String, dynamic>?;
    final hotelName = user?['hotelName'] ?? user?['hotel_name'] ?? 'Hotel';
    final rooms = d['rooms'] as List<dynamic>? ?? [];
    final tasks = d['tasks'] as List<dynamic>? ?? [];
    final staff = d['staff'] as List<dynamic>? ?? [];
    final reservations = d['reservations'] as List<dynamic>? ?? [];
    final claims = d['amenityClaims'] as List<dynamic>? ?? [];
    final activity = d['activityLogs'] as List<dynamic>? ?? [];
    final chats = d['guestMessages'] as List<dynamic>? ?? [];
    final credits = d['credits'] as Map<String, dynamic>?;
    final balance =
        credits != null ? '${credits['currentCredits'] ?? ''}' : '—';

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(hotelName, style: Theme.of(context).textTheme.headlineSmall),
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
                  label: 'Rooms',
                  value: '${rooms.length}',
                  icon: Icons.meeting_room_outlined),
              AppMetricCard(
                  label: 'Tasks',
                  value: '${tasks.length}',
                  icon: Icons.task_alt_outlined),
              AppMetricCard(
                  label: 'Staff',
                  value: '${staff.length}',
                  icon: Icons.groups_outlined),
              AppMetricCard(
                  label: 'Credit',
                  value: balance,
                  icon: Icons.account_balance_wallet_outlined),
              AppMetricCard(
                  label: 'Reservations',
                  value: '${reservations.length}',
                  icon: Icons.event_note_outlined),
              AppMetricCard(
                  label: 'Logged events',
                  value: '${activity.length}',
                  icon: Icons.timeline_outlined),
            ],
          ),
          const SizedBox(height: 20),
          Text('Management', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          AppActionTile(
            title: 'Room summary',
            subtitle:
                'Booked, available, maintenance, checked-in with guest names',
            icon: Icons.summarize_outlined,
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => AdminRoomSummaryScreen(
                  rooms: rooms.cast<Map<String, dynamic>>(),
                ),
              ),
            ),
          ),
          AppActionTile(
            title: 'Rooms & status management',
            subtitle: 'Passwords, booking details, add fees',
            icon: Icons.hotel_outlined,
            onTap: () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                    builder: (_) => const AdminRoomsScreen()),
              );
              await _load();
            },
          ),
          AppActionTile(
            title: 'Reservation requests',
            subtitle: 'Approve or reject customer holds; auto-books on arrival date',
            icon: Icons.book_online_outlined,
            onTap: () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                    builder: (_) => const AdminBookingsScreen()),
              );
              await _load();
            },
          ),
          AppActionTile(
            title: 'Guest list history',
            subtitle: 'Completed stays after checkout clears the room',
            icon: Icons.history_edu_outlined,
            onTap: () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const GuestListHistoryScreen(),
                ),
              );
            },
          ),
          AppActionTile(
            title: 'Billing and checkout reminders',
            subtitle: 'Process due reminders and billing visibility',
            icon: Icons.receipt_long_outlined,
            onTap: () => _runAction('Process reminders', () async {
              final res = await portalDio()
                  .post<Map<String, dynamic>>('/checkouts/process-reminders');
              return {
                'message': 'Processed ${res.data?['processed'] ?? 0} reminders.'
              };
            }),
          ),
          AppActionTile(
            title: 'Recharge credits',
            subtitle: 'Top up via GCash or PayMaya (opens payment page)',
            icon: Icons.account_balance_wallet_outlined,
            onTap: _showRechargeDialog,
          ),
          AppActionTile(
            title: 'Reports & analytics',
            subtitle: 'Revenue, bookings, occupancy by day / week / month / year',
            icon: Icons.insights_outlined,
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const AdminReportsScreen(),
              ),
            ),
          ),
          AppActionTile(
            title: 'Theme and personalization',
            subtitle: 'View/reset theme and tune pricing',
            icon: Icons.palette_outlined,
            onTap: () => _runAction('Reset personal theme', () async {
              await portalDio().delete('/admin/theme/reset');
              return {'message': 'Personal theme reset.'};
            }),
          ),
          AppActionTile(
            title: 'Surge pricing settings',
            subtitle: 'Auto-markup when occupancy exceeds threshold',
            icon: Icons.trending_up_outlined,
            onTap: _showSurgePricingDialog,
          ),
          AppActionTile(
            title: 'Staff management',
            subtitle: 'Add staff accounts and view performance',
            icon: Icons.groups_outlined,
            onTap: () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                    builder: (_) => const AdminStaffScreen()),
              );
              await _load();
            },
          ),
          AppActionTile(
            title: 'Room categories',
            subtitle: 'Create categories and organize rooms',
            icon: Icons.category_outlined,
            onTap: () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                    builder: (_) => const AdminCategoriesScreen()),
              );
              await _load();
            },
          ),
          AppActionTile(
            title: 'Chat',
            subtitle: 'Guest and staff messages in separate inboxes',
            icon: Icons.forum_outlined,
            onTap: () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                    builder: (_) => const AdminChatHubScreen()),
              );
              await _load();
            },
          ),
          AppActionTile(
            title: 'Amenity menu',
            subtitle: 'Add paid amenity and breakfast options',
            icon: Icons.restaurant_menu_outlined,
            onTap: _manageAmenityMenu,
          ),
          AppActionTile(
            title: 'Activity logs',
            subtitle: 'View all tracked admin/staff activities',
            icon: Icons.list_alt_outlined,
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const AdminActivityLogsScreen(),
              ),
            ),
          ),
          AppActionTile(
            title: 'Account & hotel login',
            subtitle: 'Change admin username/password; update hotel gate (signs everyone out)',
            icon: Icons.lock_outline,
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const AdminAccountSettingsScreen(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Live feed: ${claims.length} amenity claims, ${chats.length} guest messages, ${tasks.length} tasks.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_busyAction) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(),
          ],
        ],
      ),
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
    return AppScaffold(
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
                final roomId = (room['id'] ?? room['_id'] ?? '').toString();
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
                            Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    AdminRoomDetailScreen(roomId: roomId),
                              ),
                            );
                          },
                  ),
                );
              },
            ),
    );
  }
}

class AdminActivityLogsScreen extends StatefulWidget {
  const AdminActivityLogsScreen({super.key});

  @override
  State<AdminActivityLogsScreen> createState() => _AdminActivityLogsScreenState();
}

class _AdminActivityLogsScreenState extends State<AdminActivityLogsScreen> {
  List<dynamic> _logs = const [];
  bool _loading = true;
  String? _error;

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
      final res = await portalDio().get<Map<String, dynamic>>('/activity-logs');
      final data = (res.data?['data'] as List<dynamic>?) ?? const [];
      setState(() {
        _logs = data;
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
    return AppScaffold(
      appBar: AppBar(
        title: const Text('Activity logs'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: _loading
          ? const AppLoadingView()
          : _error != null
              ? AppErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _logs.length,
                    itemBuilder: (context, i) {
                      final log = _logs[i] as Map<String, dynamic>;
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.event_note_outlined),
                          title: Text((log['action'] ?? '').toString()),
                          subtitle: Text(
                            'By: ${(log['user_name'] ?? 'System').toString()}',
                          ),
                        ),
                      );
                    },
                  ),
                ),
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
  bool _busyAction = false;

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
    if (newCtrl.text.isNotEmpty && newCtrl.text != confirmCtrl.text) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Staff profile updated.')),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dioErrorMessage(e))),
      );
    }
  }

  Future<void> _signOut() async {
    await AuthStorage.clearPortalAuth();
    if (mounted) Navigator.of(context).pop();
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
      await _load();
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

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
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
              AppMetricCard(
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
          if (_busyAction) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(),
          ],
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
          await guestDio().get<Map<String, dynamic>>('/guest/chat/messages');
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

  String _formatSentAt(Object? raw) {
    final s = raw?.toString() ?? '';
    if (s.isEmpty) return '';
    final dt = DateTime.tryParse(s);
    if (dt != null) {
      final l = dt.toLocal();
      return '${l.month}/${l.day} ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
    }
    return s.length > 24 ? '${s.substring(0, 22)}…' : s;
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
    final ctrl = TextEditingController(text: '1');
    final nights = await showDialog<int>(
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
    if (nights == null || nights < 1) return;
    await _runGuestAction('Extend stay', () async {
      final res = await guestDio().post<Map<String, dynamic>>(
          '/guest/extend-stay',
          data: {'nights': nights});
      return {
        'message':
            'Extended stay. New checkout: ${res.data?['new_checkout_date'] ?? '-'}, additional fee: ${res.data?['extension_fee'] ?? '-'}',
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
                  subtitle: 'Request extra nights with updated billing',
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
  final _hotelCurrentPass = TextEditingController();
  final _hotelUserCtrl = TextEditingController();
  final _hotelNewPass = TextEditingController();
  final _hotelNewPass2 = TextEditingController();
  bool _busy = false;
  bool _isSuperAdmin = false;
  List<dynamic> _portalUsers = const [];

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
    if (isSuper) await _loadPortalUsers();
  }

  Future<void> _loadPortalUsers() async {
    try {
      final res =
          await portalDio().get<Map<String, dynamic>>('/admin/portal-users');
      if (mounted) {
        setState(() {
          _portalUsers = (res.data?['data'] as List<dynamic>?) ?? const [];
        });
      }
    } catch (_) {}
  }

  Future<void> _deleteAdmin(String userId, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove admin?'),
        content: Text('Delete portal account "$name"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await portalDio().delete('/admin/portal-users/$userId');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Admin account removed.')),
      );
      await _loadPortalUsers();
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
  void dispose() {
    _nameCtrl.dispose();
    _adminCurrentPass.dispose();
    _adminNewPass.dispose();
    _adminNewPass2.dispose();
    _hotelCurrentPass.dispose();
    _hotelUserCtrl.dispose();
    _hotelNewPass.dispose();
    _hotelNewPass2.dispose();
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

  Future<void> _saveHotelAccess() async {
    if (_busy) return;
    if (_hotelUserCtrl.text.trim().isEmpty ||
        _hotelCurrentPass.text.isEmpty ||
        _hotelNewPass.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fill hotel username, current password, and new password.'),
        ),
      );
      return;
    }
    if (_hotelNewPass.text != _hotelNewPass2.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('New hotel passwords do not match.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await portalDio().put<Map<String, dynamic>>(
        '/admin/hotel/access',
        data: {
          'current_password': _hotelCurrentPass.text,
          'access_username': _hotelUserCtrl.text.trim(),
          'access_password': _hotelNewPass.text,
          'access_password_confirmation': _hotelNewPass2.text,
        },
      );
      if (!mounted) return;
      final revoked = res.data?['session_revoked'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            revoked
                ? 'Hotel login updated. Please sign in again with your admin account.'
                : 'Hotel login updated.',
          ),
        ),
      );
      if (revoked) {
        await AuthStorage.clearPortalAuth();
        if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      }
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
      appBar: AppBar(title: const Text('Account & hotel login')),
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
            Text(
              'Portal administrators',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Super admin can remove regular admin accounts. Staff accounts are managed under Staff management.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            ..._portalUsers.map((raw) {
              final u = raw as Map<String, dynamic>;
              final role = (u['role'] ?? '').toString();
              final id = (u['id'] ?? '').toString();
              final name = (u['name'] ?? '').toString();
              final isSuper = role == 'super_admin';
              return Card(
                child: ListTile(
                  title: Text(name),
                  subtitle: Text(role.replaceAll('_', ' ')),
                  trailing: isSuper
                      ? const Text('You')
                      : IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: _busy ? null : () => _deleteAdmin(id, name),
                        ),
                ),
              );
            }),
          ],
          if (_isSuperAdmin) const SizedBox(height: 28),
          if (_isSuperAdmin) ...[
          Text(
            'Hotel gate password',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'This is the property login guests use before choosing admin/staff. '
            'After a change, every admin and staff member must log in again.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          AppInput(
            controller: _hotelUserCtrl,
            label: 'Hotel username',
          ),
          const SizedBox(height: 8),
          AppInput(
            controller: _hotelCurrentPass,
            label: 'Current hotel password',
            obscureText: true,
          ),
          const SizedBox(height: 8),
          AppInput(
            controller: _hotelNewPass,
            label: 'New hotel password',
            obscureText: true,
          ),
          const SizedBox(height: 8),
          AppInput(
            controller: _hotelNewPass2,
            label: 'Confirm new hotel password',
            obscureText: true,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _saveHotelAccess,
            child: const Text('Update hotel login'),
          ),
          ],
        ],
      ),
    );
  }
}

// --- Public customer ---

class CustomerDashboardScreen extends StatefulWidget {
  const CustomerDashboardScreen({super.key, required this.hotelId});

  final String hotelId;

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
      final res = await publicDio().get<Map<String, dynamic>>(
        '/customer/categories',
        queryParameters: {'hotel_id': widget.hotelId},
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
    return AppScaffold(
      appBar: AppBar(
        title: const Text('Book a stay'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          IconButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => CustomerToolsScreen(hotelId: widget.hotelId),
              ),
            ),
            icon: const Icon(Icons.manage_search_outlined),
            tooltip: 'Track booking / OTP',
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
    final hotel = _categoriesRes?['hotel'] as Map<String, dynamic>?;
    final hotelName = hotel?['name'] ?? 'Hotel';
    final categories = (_categoriesRes?['categories'] as List<dynamic>?) ?? [];
    final placeholders = [
      'https://picsum.photos/seed/hero-1/1200/600',
      'https://picsum.photos/seed/hero-2/1200/600',
      'https://picsum.photos/seed/hero-3/1200/600',
    ];

    final scheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          SizedBox(
            height: 200,
            child: PageView.builder(
              itemCount: placeholders.length,
              itemBuilder: (context, i) {
                final url = placeholders[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          url,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: scheme.surfaceContainerHighest,
                            alignment: Alignment.center,
                            child: const Icon(Icons.image_outlined, size: 48),
                          ),
                        ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.05),
                                Colors.black.withValues(alpha: 0.55),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 16,
                          child: Text(
                            hotelName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  shadows: const [
                                    Shadow(
                                      blurRadius: 8,
                                      color: Colors.black45,
                                    ),
                                  ],
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Text(
            'Find your room',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Browse categories, compare rates, and book in a few taps.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 20),
          ...categories.map((c) {
            final m = c as Map<String, dynamic>;
            final id = '${m['id']}';
            final name = '${m['name']}';
            final imageUrl =
                ChatAttachment.resolveMediaUrl('${m['image_url'] ?? ''}');
            final desc = '${m['description'] ?? ''}'.trim();
            final available = (m['available_rooms'] as num?)?.toInt() ?? 0;
            final availLabel = available == 1
                ? '1 room available'
                : '$available rooms available';
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => CustomerRoomsScreen(
                          hotelId: widget.hotelId,
                          categoryId: id,
                          categoryName: name,
                        ),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (imageUrl.isEmpty)
                          CircleAvatar(
                            radius: 32,
                            backgroundColor:
                                scheme.primaryContainer.withValues(alpha: 0.6),
                            child: Icon(
                              Icons.category_outlined,
                              color: scheme.onPrimaryContainer,
                            ),
                          )
                        else
                          NetworkMediaImage(
                            url: imageUrl,
                            width: 64,
                            height: 64,
                            borderRadius: BorderRadius.circular(14),
                            error: SizedBox(
                              width: 64,
                              height: 64,
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: scheme.outline,
                              ),
                            ),
                          ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
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
                                const SizedBox(height: 4),
                                Text(
                                  desc,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
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
                                    'See rooms & prices',
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
              ),
            );
          }),
        ],
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
  });

  final String hotelId;
  final String categoryId;
  final String categoryName;

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
      final res = await publicDio().get<Map<String, dynamic>>(
        '/customer/categories/${widget.categoryId}/rooms',
        queryParameters: {'hotel_id': widget.hotelId},
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

  Future<void> _bookRoom(
    Map<String, dynamic> room, {
    required bool reserve,
  }) async {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final checkInCtrl = TextEditingController();
    final checkOutCtrl = TextEditingController();
    final pricePerNight = (room['price_per_night'] as num?)?.toDouble() ?? 0;
    DateTime? checkInDate;
    DateTime? checkOutDate;
    var discountType = 'none';
    XFile? discountIdFile;

    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          final nights = (checkInDate != null && checkOutDate != null)
              ? checkOutDate!.difference(checkInDate!).inDays
              : 0;
          final safeNights = nights > 0 ? nights : 0;
          final estTotal = safeNights * pricePerNight;
          final discountPct = switch (discountType) {
            'pwd' => 20.0,
            'senior' => 20.0,
            _ => 0.0,
          };
          final estAfterDiscount =
              estTotal * (1 - (discountPct / 100));

          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final firstCheckIn =
              reserve ? today.add(const Duration(days: 1)) : today;

          Future<void> pickCheckIn() async {
            final picked = await showDatePicker(
              context: context,
              firstDate: firstCheckIn,
              lastDate: today.add(const Duration(days: 365)),
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
            if (checkInDate == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Select check-in first.')),
              );
              return;
            }
            final picked = await showDatePicker(
              context: context,
              firstDate: checkInDate!.add(const Duration(days: 1)),
              lastDate: checkInDate!.add(const Duration(days: 365)),
              initialDate: checkOutDate ??
                  checkInDate!.add(const Duration(days: 1)),
            );
            if (picked == null) return;
            checkOutDate = picked;
            checkOutCtrl.text = picked.toIso8601String().split('T').first;
            setLocal(() {});
          }

          return AlertDialog(
            title: Text(reserve ? 'Request reservation' : 'Book room'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppInput(
                    controller: nameCtrl,
                    label: 'Full name',
                  ),
                  const SizedBox(height: 8),
                  AppInput(
                    controller: emailCtrl,
                    label: 'Email',
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 8),
                  AppInput(
                    controller: phoneCtrl,
                    label: 'Phone',
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: discountType,
                    decoration: const InputDecoration(
                      labelText: 'Discount (optional)',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'none',
                        child: Text('No discount'),
                      ),
                      DropdownMenuItem(
                        value: 'pwd',
                        child: Text('PWD (20% off)'),
                      ),
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
                        if (file != null) {
                          setLocal(() => discountIdFile = file);
                        }
                      },
                      icon: const Icon(Icons.badge_outlined),
                      label: Text(
                        discountIdFile == null
                            ? 'Upload valid ID photo'
                            : 'ID photo attached — tap to replace',
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  AppInput(
                    controller: checkInCtrl,
                    label: reserve
                        ? 'Check-in (from tomorrow)'
                        : 'Check-in (today for walk-in)',
                    hint: 'Tap to open calendar',
                    readOnly: true,
                    onTap: pickCheckIn,
                    suffixIcon: const Icon(Icons.calendar_month_outlined),
                  ),
                  const SizedBox(height: 8),
                  AppInput(
                    controller: checkOutCtrl,
                    label: 'Check-out date',
                    hint: 'Tap to open calendar',
                    readOnly: true,
                    onTap: pickCheckOut,
                    suffixIcon: const Icon(Icons.calendar_month_outlined),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      reserve
                          ? 'The hotel will approve your dates. You will be notified when the stay is activated on check-in day.'
                          : 'Duration: $safeNights night${safeNights == 1 ? '' : 's'}\n'
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
                label: reserve ? 'Submit request' : 'Book now',
                onPressed: () {
                  if (discountType != 'none' && discountIdFile == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Upload a photo of your discount ID.'),
                      ),
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
                  });
                },
              ),
            ],
          );
        },
      ),
    );
    if (payload == null || _booking) return;
    setState(() => _booking = true);
    try {
      final path =
          reserve ? '/customer/reservations' : '/customer/bookings';
      final discount = (payload['discount_type'] ?? 'none').toString();
      final Map<String, dynamic> body = {
        'hotel_id': widget.hotelId,
        ...payload,
      };

      final Response<Map<String, dynamic>> res;
      if (discount != 'none' && discountIdFile != null) {
        body.remove('discount_type');
        final form = await ChatAttachment.formWithImage(
          fields: {
            ...body,
            'discount_type': discount,
          },
          file: discountIdFile!,
          fileField: 'discount_id_file',
        );
        res = await publicDio().post<Map<String, dynamic>>(path, data: form);
      } else {
        res = await publicDio().post<Map<String, dynamic>>(path, data: body);
      }
      if (!mounted) return;
      final booking = res.data?['booking'] as Map<String, dynamic>?;
      final reservation = res.data?['reservation'] as Map<String, dynamic>?;
      final ref = (booking?['booking_reference'] ??
              reservation?['external_reference'] ??
              '')
          .toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            reserve
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
    return AppScaffold(
      appBar: AppBar(
        title: Text(widget.categoryName),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh))
        ],
      ),
      body: _buildBody(),
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
    final rooms = (_data!['rooms'] as List<dynamic>?) ?? [];
    final scheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: rooms.length,
        itemBuilder: (context, i) {
          final r = rooms[i] as Map<String, dynamic>;
          final roomNo = '${r['room_number'] ?? ''}';
          final title = '${r['display_name'] ?? r['room_number']}';
          final status = '${r['status'] ?? ''}'.toLowerCase();
          final price = (r['price_per_night'] as num?)?.toDouble() ?? 0;
          final surge = r['base_price_per_night'] != null &&
              r['base_price_per_night'] != r['price_per_night'];
          final statusOpen = status == 'available' || status.isEmpty;
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
                                '₱${price.toStringAsFixed(0)} / night',
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
                              if (status.isNotEmpty)
                                Chip(
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  label: Text(
                                    statusOpen ? 'Open' : status.replaceAll('_', ' '),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  backgroundColor: statusOpen
                                      ? scheme.primaryContainer
                                      : scheme.secondaryContainer,
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
}
