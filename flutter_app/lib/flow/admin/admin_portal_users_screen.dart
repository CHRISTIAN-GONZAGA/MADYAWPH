import 'package:dio/dio.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';
import 'package:flutter/material.dart';

import '../../../dio_client.dart';
import '../../../widgets/app_input.dart';
import '../../../widgets/app_scaffold.dart';
import '../../../widgets/app_state_views.dart';

/// Create and manage front desk (and admin, for super admin) portal accounts.
class AdminPortalUsersScreen extends StatefulWidget {
  const AdminPortalUsersScreen({
    super.key,
    required this.canManageAdmins,
  });

  /// Super admin can create/remove administrators and front desk accounts.
  final bool canManageAdmins;

  @override
  State<AdminPortalUsersScreen> createState() => _AdminPortalUsersScreenState();
}

class _AdminPortalUsersScreenState extends State<AdminPortalUsersScreen> {
  List<Map<String, dynamic>> _users = const [];
  bool _loading = true;
  bool _busy = false;
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
      final res =
          await portalDio().get<Map<String, dynamic>>('/admin/portal-users');
      if (!mounted) return;
      setState(() {
        _users = (res.data?['data'] as List?)
                ?.whereType<Map>()
                .map((m) => Map<String, dynamic>.from(m))
                .toList() ??
            const [];
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = dioErrorMessage(e);
        _loading = false;
      });
    }
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'frontdesk':
        return 'Front desk';
      case 'super_admin':
        return 'Super admin';
      case 'admin':
        return 'Administrator';
      case 'staff':
        return 'Staff';
      default:
        return role.isEmpty ? '—' : role;
    }
  }

  bool _canDelete(Map<String, dynamic> user) {
    final role = (user['role'] ?? '').toString();
    if (role == 'super_admin') return false;
    if (widget.canManageAdmins) {
      return role == 'admin' || role == 'frontdesk' || role == 'staff';
    }
    return role == 'frontdesk' || role == 'staff';
  }

  Future<void> _addUser() async {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    var role = widget.canManageAdmins ? 'frontdesk' : 'frontdesk';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(
            widget.canManageAdmins
                ? 'Add portal account'
                : 'Add front desk account',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.canManageAdmins) ...[
                  DropdownButtonFormField<String>(
                    value: role,
                    decoration: const InputDecoration(
                      labelText: 'Account type',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'frontdesk',
                        child: Text('Front desk'),
                      ),
                      DropdownMenuItem(
                        value: 'admin',
                        child: Text('Administrator'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) setLocal(() => role = v);
                    },
                  ),
                  const SizedBox(height: 10),
                ],
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Username *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Email (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                AppInput(
                  controller: passCtrl,
                  label: 'Password *',
                  obscureText: true,
                ),
                const SizedBox(height: 10),
                AppInput(
                  controller: confirmCtrl,
                  label: 'Confirm password *',
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
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (passCtrl.text != confirmCtrl.text) {
      if (!mounted) return;
      showAppMessage(context, 'Passwords do not match.');
      return;
    }

    setState(() => _busy = true);
    try {
      await portalDio().post('/admin/portal-users', data: {
        'name': nameCtrl.text.trim(),
        if (emailCtrl.text.trim().isNotEmpty) 'email': emailCtrl.text.trim(),
        'password': passCtrl.text,
        'role': role,
      });
      if (!mounted) return;
      showAppMessage(context, 'Account created.');
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    final id = (user['id'] ?? '').toString();
    final name = (user['name'] ?? 'User').toString();
    if (id.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove account?'),
        content: Text(
          'Delete "$name"? They will lose access immediately.',
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

    setState(() => _busy = true);
    try {
      await portalDio().delete('/admin/portal-users/$id');
      if (!mounted) return;
      showAppMessage(context, 'Account removed.');
      await _load();
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
      appBar: AppBar(
        title: Text(
          widget.canManageAdmins
              ? 'Portal accounts'
              : 'Front desk accounts',
        ),
        actions: [
          IconButton(
            onPressed: _loading || _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _addUser,
        icon: const Icon(Icons.person_add_outlined),
        label: Text(widget.canManageAdmins ? 'Add account' : 'Add front desk'),
      ),
      body: _loading
          ? const AppLoadingView()
          : _error != null
              ? AppErrorView(message: _error!, onRetry: _load)
              : _users.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No accounts yet. Tap Add to create one.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                      itemCount: _users.length,
                      itemBuilder: (context, i) {
                        final u = _users[i];
                        final role = (u['role'] ?? '').toString();
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            leading: Icon(
                              role == 'frontdesk'
                                  ? Icons.badge_outlined
                                  : role == 'staff'
                                      ? Icons.engineering_outlined
                                      : Icons.admin_panel_settings_outlined,
                            ),
                            title: Text((u['name'] ?? '').toString()),
                            subtitle: Text(
                              '${_roleLabel(role)} · ${u['email'] ?? ''}',
                            ),
                            trailing: _canDelete(u)
                                ? IconButton(
                                    tooltip: 'Remove',
                                    onPressed: _busy
                                        ? null
                                        : () => _deleteUser(u),
                                    icon: const Icon(Icons.delete_outline),
                                  )
                                : null,
                          ),
                        );
                      },
                    ),
    );
  }
}
