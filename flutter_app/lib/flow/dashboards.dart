import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth_storage.dart';
import '../dio_client.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_input.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/app_state_views.dart';
import 'admin_rooms.dart';
import 'admin_categories.dart';
import 'admin_chat.dart';
import 'admin_bookings.dart';
import 'admin_reports.dart';
import 'customer_tools.dart';
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
      final data = res.data ?? {};
      final redirectUrl = (data['redirect_url'] ?? '').toString();
      if (redirectUrl.isNotEmpty && mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Complete PayMongo Payment'),
            content: SelectableText(
              'Open this URL in your browser to complete payment:\n\n$redirectUrl',
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: redirectUrl));
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Checkout URL copied.')),
                  );
                },
                child: const Text('Copy URL'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }

      return {
        'message': (data['message'] ?? 'Recharge request sent.').toString(),
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
            title: 'Bookings operations',
            subtitle: 'Handle booking and reservation requests',
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
            subtitle: 'Top up hotel credits via PayMongo wallet',
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
            title: 'Guest chat inbox',
            subtitle: 'Receive and reply to guest messages',
            icon: Icons.forum_outlined,
            onTap: () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                    builder: (_) => const AdminChatInboxScreen()),
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

  Future<void> _showUpdateTaskStatusDialog() async {
    final idCtrl = TextEditingController();
    String status = 'in-progress';
    final payload = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Update Task Status'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: idCtrl,
                decoration: const InputDecoration(
                  labelText: 'Task ID',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: status,
                items: const [
                  DropdownMenuItem(value: 'pending', child: Text('pending')),
                  DropdownMenuItem(
                      value: 'in-progress', child: Text('in-progress')),
                  DropdownMenuItem(
                      value: 'completed', child: Text('completed')),
                ],
                onChanged: (v) => setLocal(() => status = v ?? 'in-progress'),
                decoration: const InputDecoration(
                  labelText: 'Status',
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
                'taskId': idCtrl.text.trim(),
                'status': status,
              }),
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
    final taskId = payload?['taskId'] ?? '';
    final statusPicked = payload?['status'] ?? '';
    if (taskId.isEmpty || statusPicked.isEmpty) return;

    await _runAction('Update task', () async {
      await portalDio()
          .put('/tasks/$taskId/status', data: {'status': statusPicked});
      return {'message': 'Task updated to $statusPicked.'};
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppBar(
        title: const Text('Staff dashboard'),
        actions: [
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
            subtitle: 'Fetch assigned tasks from API',
            icon: Icons.assignment_ind_outlined,
            onTap: () => _runAction('Load assigned tasks', () async {
              final res =
                  await portalDio().get<List<dynamic>>('/tasks/assigned-to-me');
              return {
                'message': 'Loaded ${(res.data ?? []).length} assigned tasks.'
              };
            }),
          ),
          AppActionTile(
            title: 'Update task status',
            subtitle: 'Mark task pending, in-progress, or completed',
            icon: Icons.checklist_rtl_outlined,
            onTap: _showUpdateTaskStatusDialog,
          ),
          AppActionTile(
            title: 'Room operations',
            subtitle: 'View all and available rooms',
            icon: Icons.hotel_outlined,
            onTap: () => _runAction('Load rooms', () async {
              final all = await portalDio().get('/rooms');
              final avail = await portalDio().get('/rooms/available');
              return {
                'message':
                    'Loaded ${(all.data as Map?)?['total'] ?? 'rooms'} rooms and ${(avail.data as List?)?.length ?? 0} available.',
              };
            }),
          ),
          AppActionTile(
            title: 'Reports & analytics',
            subtitle: 'Charts for revenue and operations',
            icon: Icons.insights_outlined,
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const AdminReportsScreen(),
              ),
            ),
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

  Future<void> _sendChatLine() async {
    final text = _chatInput.text.trim();
    if (text.isEmpty || _chatSending) return;
    setState(() => _chatSending = true);
    try {
      await guestDio().post('/guest/chat/messages', data: {'message': text});
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
                                final body =
                                    (m['message'] ?? '').toString().trim();
                                final guestSide = _isGuestMessage(m);
                                final bubbleColor = guestSide
                                    ? scheme.surfaceContainerHighest
                                    : scheme.primaryContainer;
                                final align = guestSide
                                    ? Alignment.centerLeft
                                    : Alignment.centerRight;
                                final sentRaw = m['sent_at'] ?? m['sentAt'];
                                final sent = _formatSentAt(sentRaw);
                                return Align(
                                  alignment: align,
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                                    constraints: const BoxConstraints(
                                        maxWidth: 300),
                                    decoration: BoxDecoration(
                                      color: bubbleColor,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (!guestSide)
                                          Text(
                                            'Hotel',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                  color: scheme
                                                      .onPrimaryContainer,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                        if (guestSide)
                                          Text(
                                            'You',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                        const SizedBox(height: 4),
                                        SelectableText(body),
                                        if (sent.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            sent,
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                  color: scheme
                                                      .onSurfaceVariant,
                                                ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
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
                            onPressed:
                                _chatSending ? null : () => _sendChatLine(),
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

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SizedBox(
            height: 180,
            child: PageView.builder(
              itemCount: placeholders.length,
              itemBuilder: (context, i) {
                final url = placeholders[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.network(
                      url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        alignment: Alignment.center,
                        child: const Icon(Icons.image_outlined),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Text(hotelName, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'Choose a category to see available rooms.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          ...categories.map((c) {
            final m = c as Map<String, dynamic>;
            final id = '${m['id']}';
            final name = '${m['name']}';
            final imageUrl = '${m['image_url'] ?? ''}';
            return Card(
              child: ListTile(
                leading: imageUrl.isEmpty
                    ? const Icon(Icons.category_outlined)
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          imageUrl,
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.broken_image_outlined),
                        ),
                      ),
                title: Text(name),
                subtitle: Text('${m['description'] ?? ''}'),
                trailing: const Icon(Icons.chevron_right),
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

  Future<void> _bookRoom(Map<String, dynamic> room) async {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final checkInCtrl = TextEditingController();
    final checkOutCtrl = TextEditingController();
    final pricePerNight = (room['price_per_night'] as num?)?.toDouble() ?? 0;
    DateTime? checkInDate;
    DateTime? checkOutDate;

    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          final nights = (checkInDate != null && checkOutDate != null)
              ? checkOutDate!.difference(checkInDate!).inDays
              : 0;
          final safeNights = nights > 0 ? nights : 0;
          final estTotal = safeNights * pricePerNight;

          Future<void> pickCheckIn() async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              firstDate: DateTime(now.year, now.month, now.day),
              lastDate: now.add(const Duration(days: 365)),
              initialDate: checkInDate ?? now,
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

          final clock = DateTime.now();
          final today = DateTime(clock.year, clock.month, clock.day);
          final startDay = checkInDate != null
              ? DateTime(
                  checkInDate!.year,
                  checkInDate!.month,
                  checkInDate!.day,
                )
              : today;
          final futureReservation = startDay.isAfter(today);

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
            title: const Text('Book room'),
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
                  AppInput(
                    controller: checkInCtrl,
                    label: 'Check-in date',
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
                      futureReservation
                          ? 'Reservation: check-in is on a future date — room stays reserved until then.'
                          : 'Duration: $safeNights night${safeNights == 1 ? '' : 's'}\nEstimated charge: ₱${estTotal.toStringAsFixed(2)}',
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
                label: futureReservation ? 'Reserve' : 'Book now',
                onPressed: () => Navigator.of(context).pop({
                  'room_id': (room['id'] ?? '').toString(),
                  'guest_name': nameCtrl.text.trim(),
                  'guest_email': emailCtrl.text.trim(),
                  'guest_phone': phoneCtrl.text.trim(),
                  'check_in': checkInCtrl.text.trim(),
                  'check_out': checkOutCtrl.text.trim(),
                }),
              ),
            ],
          );
        },
      ),
    );
    if (payload == null || _booking) return;
    setState(() => _booking = true);
    try {
      final checkInStr = payload['check_in']?.toString() ?? '';
      final parsedIn = DateTime.tryParse(checkInStr);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final startDay = parsedIn != null
          ? DateTime(parsedIn.year, parsedIn.month, parsedIn.day)
          : today;
      final path = startDay.isAfter(today)
          ? '/customer/reservations'
          : '/customer/bookings';

      final res = await publicDio().post<Map<String, dynamic>>(
        path,
        data: {
          'hotel_id': widget.hotelId,
          ...payload,
        },
      );
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
            path.endsWith('reservations')
                ? 'Reservation held: ${ref.isEmpty ? 'reference generated' : ref}'
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
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: rooms.length,
        itemBuilder: (context, i) {
          final r = rooms[i] as Map<String, dynamic>;
          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(10),
              onTap: () => _bookRoom(r),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: () => _bookRoom(r),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        (r['image_url'] ?? '').toString(),
                        height: 130,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          height: 130,
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          alignment: Alignment.center,
                          child: const Icon(Icons.bed_outlined),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('${r['display_name'] ?? r['room_number']}'),
                ],
              ),
              subtitle: Text(
                'Room ${r['room_number']} · ${r['status']} · ₱${r['price_per_night']}'
                '${r['base_price_per_night'] != null && r['base_price_per_night'] != r['price_per_night'] ? ' (surge applied)' : ''}',
              ),
            ),
          );
        },
      ),
    );
  }
}
