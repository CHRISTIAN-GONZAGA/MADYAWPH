import 'package:dio/dio.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';
import 'package:flutter/material.dart';

import '../dio_client.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/app_input.dart';
import '../widgets/app_state_views.dart';

/// List and add hotel staff (maintenance, reception, etc.).
class AdminStaffScreen extends StatefulWidget {
  const AdminStaffScreen({super.key});

  @override
  State<AdminStaffScreen> createState() => _AdminStaffScreenState();
}

class _AdminStaffScreenState extends State<AdminStaffScreen> {
  List<dynamic> _rows = const [];
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
      final res = await portalDio().get<Map<String, dynamic>>('/staff');
      final data = res.data?['data'];
      setState(() {
        _rows = data is List ? data : (res.data is List ? res.data as List : const []);
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

  Future<void> _addStaff() async {
    final nameCtrl = TextEditingController();
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final customRoleCtrl = TextEditingController();
    var role = 'receptionist';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Add staff member'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppInput(controller: nameCtrl, label: 'Display name'),
                const SizedBox(height: 8),
                AppInput(controller: userCtrl, label: 'Login username'),
                const SizedBox(height: 8),
                AppInput(
                  controller: passCtrl,
                  label: 'Password',
                  obscureText: true,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: role,
                  decoration: const InputDecoration(
                    labelText: 'Role',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'janitor', child: Text('Janitor')),
                    DropdownMenuItem(
                      value: 'receptionist',
                      child: Text('Receptionist'),
                    ),
                    DropdownMenuItem(
                      value: 'maintenance',
                      child: Text('Maintenance'),
                    ),
                    DropdownMenuItem(value: 'manager', child: Text('Manager')),
                    DropdownMenuItem(
                      value: '_custom',
                      child: Text('Custom…'),
                    ),
                  ],
                  onChanged: (v) => setLocal(() => role = v ?? role),
                ),
                if (role == '_custom') ...[
                  const SizedBox(height: 8),
                  AppInput(
                    controller: customRoleCtrl,
                    label: 'Custom role title',
                    hint: 'e.g. Housekeeping Lead, Chef',
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (role == '_custom' &&
                    customRoleCtrl.text.trim().isEmpty) {
                  showAppMessage(
                    ctx,
                    'Enter a custom role title.',
                    isError: true,
                  );
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final roleValue = role == '_custom'
        ? customRoleCtrl.text.trim()
        : role;
    if (roleValue.isEmpty) return;

    try {
      await portalDio().post('/staff', data: {
        'name': nameCtrl.text.trim(),
        'username': userCtrl.text.trim(),
        'password': passCtrl.text,
        'role': roleValue,
      });
      if (!mounted) return;
      showAppMessage(context, 'Staff account created.');
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    } finally {
      nameCtrl.dispose();
      userCtrl.dispose();
      passCtrl.dispose();
      customRoleCtrl.dispose();
    }
  }

  Future<void> _deleteStaff(Map<String, dynamic> staff) async {
    final id = (staff['id'] ?? '').toString();
    final name = (staff['name'] ?? 'Staff').toString();
    if (id.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove staff account?'),
        content: Text(
          'Delete "$name"? Their login will be removed and open tasks will be unassigned.',
        ),
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

    try {
      await portalDio().delete('/staff/$id');
      if (!mounted) return;
      showAppMessage(context, 'Staff account removed.');
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppBar(
        title: const Text('Staff'),
        actions: [
          IconButton(
            onPressed: _addStaff,
            icon: const Icon(Icons.person_add_outlined),
            tooltip: 'Add staff',
          ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return appScrollableLoading(onRefresh: _load);
    }
    if (_error != null) {
      return appScrollableError(message: _error!, onRetry: _load, onRefresh: _load);
    }
    if (_rows.isEmpty) {
      return appScrollableEmpty(
        message: 'No staff yet. Tap Add staff to create an account.',
        onRefresh: _load,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _rows.length,
        itemBuilder: (context, i) {
          final s = _rows[i] as Map<String, dynamic>;
          final role = (s['role'] ?? '').toString();
          final score = s['performance_score'] ?? 0;
          final done = s['tasks_completed'] ?? 0;
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                child: Text(
                  ((s['name'] ?? '?').toString().isNotEmpty
                          ? (s['name'] as String)[0]
                          : '?')
                      .toUpperCase(),
                ),
              ),
              title: Text((s['name'] ?? '').toString()),
              subtitle: Text(
                '${role.isEmpty ? 'Staff' : role} · Tasks done: $done · Completion: $score%',
              ),
              trailing: IconButton(
                tooltip: 'Delete staff',
                onPressed: () => _deleteStaff(s),
                icon: const Icon(Icons.delete_outline),
              ),
            ),
          );
        },
      ),
    );
  }
}
