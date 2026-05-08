import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth_storage.dart';
import '../dio_client.dart';
import 'admin_rooms.dart';
import 'admin_categories.dart';
import 'admin_chat.dart';
import 'admin_bookings.dart';
import 'customer_tools.dart';
import '../widgets/theme_fab.dart';

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

  Future<void> _showRoomPasswordLookup() async {
    final ctrl = TextEditingController();
    final bookingId = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Get Room Password'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Booking ID',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(ctrl.text.trim()),
            child: const Text('Fetch'),
          ),
        ],
      ),
    );
    if (bookingId == null || bookingId.isEmpty) return;

    await _runAction('Fetch room password', () async {
      final res = await portalDio().get<Map<String, dynamic>>(
          '/admin/bookings/$bookingId/room-password');
      final d = res.data ?? {};
      final password = d['room_access_password']?.toString() ?? '';
      if (!mounted) return d;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Room Access Password'),
          content: SelectableText(
            password.isEmpty
                ? 'No active password found.'
                : 'Booking ${d['booking_reference'] ?? ''}\nRoom ${d['room_number'] ?? ''}\nPassword: $password',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'))
          ],
        ),
      );
      return d;
    });
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
      builder: (context) => AlertDialog(
        title: const Text('Add amenity menu item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: typeCtrl,
                decoration: const InputDecoration(labelText: 'Type')),
            TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Name')),
            TextField(
                controller: priceCtrl,
                decoration: const InputDecoration(labelText: 'Price')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
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
    );
    if (payload == null) return;

    await _runAction('Amenity menu', () async {
      await portalDio().post('/admin/amenity-menu', data: payload);
      return {'message': 'Amenity menu item created.'};
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
      floatingActionButton: const ThemeFab(),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
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
              _AdminMetricCard(
                  label: 'Rooms',
                  value: '${rooms.length}',
                  icon: Icons.meeting_room_outlined),
              _AdminMetricCard(
                  label: 'Tasks',
                  value: '${tasks.length}',
                  icon: Icons.task_alt_outlined),
              _AdminMetricCard(
                  label: 'Staff',
                  value: '${staff.length}',
                  icon: Icons.groups_outlined),
              _AdminMetricCard(
                  label: 'Credit',
                  value: balance,
                  icon: Icons.account_balance_wallet_outlined),
              _AdminMetricCard(
                  label: 'Reservations',
                  value: '${reservations.length}',
                  icon: Icons.event_note_outlined),
              _AdminMetricCard(
                  label: 'Activity Logs',
                  value: '${activity.length}',
                  icon: Icons.timeline_outlined),
            ],
          ),
          const SizedBox(height: 20),
          Text('Management', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _AdminActionTile(
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
          _AdminActionTile(
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
          _AdminActionTile(
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
          _AdminActionTile(
            title: 'Recharge credits',
            subtitle: 'Top up hotel credits via PayMongo wallet',
            icon: Icons.account_balance_wallet_outlined,
            onTap: _showRechargeDialog,
          ),
          _AdminActionTile(
            title: 'Reports and activity logs',
            subtitle: 'Access sales, occupancy, and logs',
            icon: Icons.assessment_outlined,
            onTap: () => _runAction('Load reports', () async {
              final sales = await portalDio().get('/reports/sales');
              final occ = await portalDio().get('/reports/room-occupancy');
              final logs = await portalDio().get('/activity-logs');
              final salesCount = (sales.data is List)
                  ? (sales.data as List).length
                  : ((sales.data as Map?)?['data'] as List?)?.length ?? 0;
              final occRate = (occ.data as Map?)?['occupancy_rate'] ?? 'ok';
              return {
                'message':
                    'Reports loaded (sales rows: $salesCount, occupancy: $occRate%, logs: ${(logs.data as Map?)?['total'] ?? 'ok'}).',
              };
            }),
          ),
          _AdminActionTile(
            title: 'Theme and personalization',
            subtitle: 'View/reset theme and tune pricing',
            icon: Icons.palette_outlined,
            onTap: () => _runAction('Reset personal theme', () async {
              await portalDio().delete('/admin/theme/reset');
              return {'message': 'Personal theme reset.'};
            }),
          ),
          _AdminActionTile(
            title: 'Surge pricing settings',
            subtitle: 'Auto-markup when occupancy exceeds threshold',
            icon: Icons.trending_up_outlined,
            onTap: _showSurgePricingDialog,
          ),
          _AdminActionTile(
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
          _AdminActionTile(
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
          _AdminActionTile(
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

class _AdminMetricCard extends StatelessWidget {
  const _AdminMetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.labelMedium),
                  Text(value, style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminActionTile extends StatelessWidget {
  const _AdminActionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
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
    return Scaffold(
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
    if (_loading) return const Center(child: CircularProgressIndicator());
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
              _AdminMetricCard(
                  label: 'Tasks',
                  value: '${tasks.length}',
                  icon: Icons.task_outlined),
              _AdminMetricCard(
                  label: 'Guest msgs',
                  value: '${msgs.length}',
                  icon: Icons.chat_outlined),
              _AdminMetricCard(
                  label: 'Rooms',
                  value: '${rooms.length}',
                  icon: Icons.meeting_room_outlined),
              _AdminMetricCard(
                  label: 'Role', value: 'Staff', icon: Icons.badge_outlined),
            ],
          ),
          const SizedBox(height: 16),
          _AdminActionTile(
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
          _AdminActionTile(
            title: 'Update task status',
            subtitle: 'Mark task pending, in-progress, or completed',
            icon: Icons.checklist_rtl_outlined,
            onTap: _showUpdateTaskStatusDialog,
          ),
          _AdminActionTile(
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
          _AdminActionTile(
            title: 'Bookings and activity',
            subtitle: 'Load bookings and activity logs',
            icon: Icons.history_outlined,
            onTap: () => _runAction('Load operations data', () async {
              final bookings =
                  await portalDio().get<Map<String, dynamic>>('/bookings');
              final logs =
                  await portalDio().get<Map<String, dynamic>>('/activity-logs');
              return {
                'message':
                    'Bookings: ${(bookings.data?['total'] ?? 0)} | Logs: ${(logs.data?['total'] ?? 0)}',
              };
            }),
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
          await guestDio().get<Map<String, dynamic>>('/guest/dashboard');
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
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Request Amenity'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedId,
                items: items.map((item) {
                  final id = (item['id'] ?? '').toString();
                  final name = (item['amenityName'] ?? '').toString();
                  final type = (item['amenityType'] ?? '').toString();
                  final price = (item['price'] ?? 0).toString();
                  return DropdownMenuItem(
                    value: id,
                    child: Text('$name ($type) - ₱$price'),
                  );
                }).toList(),
                onChanged: (v) => setLocal(() => selectedId = v ?? selectedId),
                decoration: const InputDecoration(labelText: 'Menu item'),
              ),
              TextField(
                  controller: qtyCtrl,
                  decoration: const InputDecoration(labelText: 'Quantity')),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.of(context).pop({
                'amenityItemId': selectedId,
                'quantity': int.tryParse(qtyCtrl.text.trim()) ?? 1,
              }),
              child: const Text('Send'),
            ),
          ],
        ),
      ),
    );
    if (payload == null) return;

    await _runGuestAction('Amenity request', () async {
      await guestDio().post('/guest/amenities/claim', data: payload);
      return {'message': 'Amenity request submitted and added to charges.'};
    });
  }

  Future<void> _sendGuestMessage() async {
    final ctrl = TextEditingController();
    final message = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Message Staff'),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Message',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(ctrl.text.trim()),
              child: const Text('Send')),
        ],
      ),
    );
    if (message == null || message.isEmpty) return;
    await _runGuestAction('Guest message', () async {
      await guestDio().post('/guest/chat/messages', data: {'message': message});
      return {'message': 'Message sent to hotel staff.'};
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
                value: rating,
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Guest dashboard'),
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
    if (_loading) return const Center(child: CircularProgressIndicator());
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

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
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
              _AdminMetricCard(
                  label: 'Amenity claims',
                  value: '${claims.length}',
                  icon: Icons.local_mall_outlined),
              _AdminMetricCard(
                  label: 'Review prompt',
                  value: (room?['showReviewPrompt'] == true) ? 'Yes' : 'No',
                  icon: Icons.reviews_outlined),
            ],
          ),
          const SizedBox(height: 16),
          _AdminActionTile(
            title: 'Request amenity',
            subtitle: 'Submit a housekeeping/amenity claim',
            icon: Icons.room_service_outlined,
            onTap: _claimAmenity,
          ),
          _AdminActionTile(
            title: 'Message hotel staff',
            subtitle: 'Send an in-house message',
            icon: Icons.chat_bubble_outline,
            onTap: _sendGuestMessage,
          ),
          _AdminActionTile(
            title: 'Extend stay',
            subtitle: 'Request extra nights with updated billing',
            icon: Icons.calendar_month_outlined,
            onTap: _extendStay,
          ),
          _AdminActionTile(
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
    return Scaffold(
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
    if (_loading) return const Center(child: CircularProgressIndicator());
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

    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          final checkIn = DateTime.tryParse(checkInCtrl.text.trim());
          final checkOut = DateTime.tryParse(checkOutCtrl.text.trim());
          final nights = (checkIn != null && checkOut != null)
              ? checkOut.difference(checkIn).inDays
              : 0;
          final safeNights = nights > 0 ? nights : 0;
          final estTotal = safeNights * pricePerNight;
          return AlertDialog(
            title: const Text('Book room'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Full name'),
                  ),
                  TextField(
                    controller: emailCtrl,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  TextField(
                    controller: phoneCtrl,
                    decoration: const InputDecoration(labelText: 'Phone'),
                  ),
                  TextField(
                    controller: checkInCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Check-in (YYYY-MM-DD)'),
                    onChanged: (_) => setLocal(() {}),
                  ),
                  TextField(
                    controller: checkOutCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Check-out (YYYY-MM-DD)'),
                    onChanged: (_) => setLocal(() {}),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Duration: $safeNights night${safeNights == 1 ? '' : 's'}\nEstimated charge: ₱${estTotal.toStringAsFixed(2)}',
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
              FilledButton(
                onPressed: () => Navigator.of(context).pop({
                  'room_id': (room['id'] ?? '').toString(),
                  'guest_name': nameCtrl.text.trim(),
                  'guest_email': emailCtrl.text.trim(),
                  'guest_phone': phoneCtrl.text.trim(),
                  'check_in': checkInCtrl.text.trim(),
                  'check_out': checkOutCtrl.text.trim(),
                }),
                child: const Text('Book now'),
              ),
            ],
          );
        },
      ),
    );
    if (payload == null || _booking) return;
    setState(() => _booking = true);
    try {
      final res = await publicDio().post<Map<String, dynamic>>(
        '/customer/bookings',
        data: {
          'hotel_id': widget.hotelId,
          ...payload,
        },
      );
      if (!mounted) return;
      final booking = res.data?['booking'] as Map<String, dynamic>?;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Booking submitted: ${(booking?['booking_reference'] ?? 'Reference generated')}'),
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
    return Scaffold(
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
    if (_loading) return const Center(child: CircularProgressIndicator());
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
