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
  final Set<String> _expandedRoles = {};

  static const _roleOrder = [
    'admin',
    'frontdesk',
    'staff',
    'super_admin',
  ];

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
      final users = (res.data?['data'] as List?)
              ?.whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList() ??
          const [];
      setState(() {
        _users = users;
        _loading = false;
        if (_expandedRoles.isEmpty && users.isNotEmpty) {
          final grouped = _groupedUsers(users);
          if (grouped.isNotEmpty) {
            _expandedRoles.add(grouped.keys.first);
          }
        }
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = dioErrorMessage(e);
        _loading = false;
      });
    }
  }

  Map<String, List<Map<String, dynamic>>> _groupedUsers(
    List<Map<String, dynamic>> users,
  ) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final u in users) {
      final role = (u['role'] ?? 'other').toString();
      grouped.putIfAbsent(role, () => []).add(u);
    }
    final ordered = <String, List<Map<String, dynamic>>>{};
    for (final role in _roleOrder) {
      final list = grouped.remove(role);
      if (list != null && list.isNotEmpty) ordered[role] = list;
    }
    for (final entry in grouped.entries) {
      if (entry.value.isNotEmpty) ordered[entry.key] = entry.value;
    }
    return ordered;
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

  IconData _roleIcon(String role) {
    switch (role) {
      case 'frontdesk':
        return Icons.badge_outlined;
      case 'staff':
        return Icons.engineering_outlined;
      case 'super_admin':
        return Icons.shield_outlined;
      default:
        return Icons.admin_panel_settings_outlined;
    }
  }

  bool _canManage(Map<String, dynamic> user) {
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
    var role = 'frontdesk';
    var submitting = false;
    var created = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          Future<void> submit() async {
            if (submitting) return;
            String? validationError;
            if (nameCtrl.text.trim().isEmpty) {
              validationError = 'Username is required.';
            } else if (passCtrl.text.isEmpty) {
              validationError = 'Password is required.';
            } else if (passCtrl.text != confirmCtrl.text) {
              validationError = 'Passwords do not match.';
            }
            if (validationError != null) {
              await showAppMessage(
                ctx,
                validationError,
                isError: true,
                confirmLabel: 'Try again',
              );
              return;
            }
            setLocal(() => submitting = true);
            try {
              await portalDio().post('/admin/portal-users', data: {
                'name': nameCtrl.text.trim(),
                if (emailCtrl.text.trim().isNotEmpty)
                  'email': emailCtrl.text.trim(),
                'password': passCtrl.text,
                'role': role,
              });
              created = true;
              if (ctx.mounted) Navigator.pop(ctx);
            } on DioException catch (e) {
              if (!ctx.mounted) return;
              setLocal(() => submitting = false);
              await showAppMessage(
                ctx,
                dioErrorMessage(e),
                isError: true,
                confirmLabel: 'Try again',
              );
            }
          }

          return AlertDialog(
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
                      onChanged: submitting
                          ? null
                          : (v) {
                              if (v != null) setLocal(() => role = v);
                            },
                    ),
                    const SizedBox(height: 10),
                  ],
                  TextField(
                    controller: nameCtrl,
                    enabled: !submitting,
                    decoration: const InputDecoration(
                      labelText: 'Username *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: emailCtrl,
                    enabled: !submitting,
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
                onPressed: submitting ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: submitting ? null : submit,
                child: submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create'),
              ),
            ],
          );
        },
      ),
    );

    nameCtrl.dispose();
    emailCtrl.dispose();
    passCtrl.dispose();
    confirmCtrl.dispose();
    if (!created || !mounted) return;
    showAppMessage(context, 'Account created.');
    await _load();
  }

  Future<void> _editUser(Map<String, dynamic> user) async {
    final id = (user['id'] ?? '').toString();
    if (id.isEmpty || !_canManage(user)) return;

    final nameCtrl =
        TextEditingController(text: (user['name'] ?? '').toString());
    final emailRaw = (user['email'] ?? '').toString();
    final emailCtrl = TextEditingController(
      text: emailRaw.endsWith('@hotel.local') ? '' : emailRaw,
    );
    final passCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    var submitting = false;
    var saved = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          Future<void> submit() async {
            if (submitting) return;
            String? validationError;
            if (nameCtrl.text.trim().isEmpty) {
              validationError = 'Username is required.';
            } else if (passCtrl.text.isNotEmpty &&
                passCtrl.text != confirmCtrl.text) {
              validationError = 'Passwords do not match.';
            } else if (passCtrl.text.isNotEmpty && passCtrl.text.length < 6) {
              validationError = 'Password must be at least 6 characters.';
            }
            if (validationError != null) {
              await showAppMessage(
                ctx,
                validationError,
                isError: true,
                confirmLabel: 'Try again',
              );
              return;
            }
            setLocal(() => submitting = true);
            try {
              await portalDio().put('/admin/portal-users/$id', data: {
                'name': nameCtrl.text.trim(),
                'email': emailCtrl.text.trim(),
                if (passCtrl.text.isNotEmpty) ...{
                  'password': passCtrl.text,
                  'password_confirmation': confirmCtrl.text,
                },
              });
              saved = true;
              if (ctx.mounted) Navigator.pop(ctx);
            } on DioException catch (e) {
              if (!ctx.mounted) return;
              setLocal(() => submitting = false);
              await showAppMessage(
                ctx,
                dioErrorMessage(e),
                isError: true,
                confirmLabel: 'Try again',
              );
            }
          }

          return AlertDialog(
            title: Text(
              'Edit ${_roleLabel((user['role'] ?? '').toString()).toLowerCase()}',
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _roleLabel((user['role'] ?? '').toString()),
                    style: Theme.of(ctx).textTheme.labelLarge?.copyWith(
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    enabled: !submitting,
                    decoration: const InputDecoration(
                      labelText: 'Username *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: emailCtrl,
                    enabled: !submitting,
                    decoration: const InputDecoration(
                      labelText: 'Email (optional)',
                      border: OutlineInputBorder(),
                      helperText: 'Leave blank to keep a system email.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Reset password (optional)',
                    style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Leave blank to keep the current password. Changing it signs them out.',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 10),
                  AppInput(
                    controller: passCtrl,
                    label: 'New password',
                    obscureText: true,
                  ),
                  const SizedBox(height: 10),
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
                onPressed: submitting ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: submitting ? null : submit,
                child: submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ],
          );
        },
      ),
    );

    nameCtrl.dispose();
    emailCtrl.dispose();
    passCtrl.dispose();
    confirmCtrl.dispose();
    if (!saved || !mounted) return;
    showAppMessage(context, 'Account updated.');
    await _load();
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
    final scheme = Theme.of(context).colorScheme;
    final grouped = _groupedUsers(_users);

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
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                      children: [
                        Text(
                          'Tap a role to view accounts. Edit to change username, email, or password.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 12),
                        ...grouped.entries.map((entry) {
                          final role = entry.key;
                          final list = entry.value;
                          final expanded = _expandedRoles.contains(role);
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            clipBehavior: Clip.antiAlias,
                            child: ExpansionTile(
                              key: PageStorageKey<String>('portal-role-$role'),
                              initiallyExpanded: expanded,
                              onExpansionChanged: (open) {
                                setState(() {
                                  if (open) {
                                    _expandedRoles.add(role);
                                  } else {
                                    _expandedRoles.remove(role);
                                  }
                                });
                              },
                              leading: Icon(_roleIcon(role)),
                              title: Text(
                                _roleLabel(role),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Text(
                                '${list.length} account${list.length == 1 ? '' : 's'}',
                              ),
                              children: [
                                const Divider(height: 1),
                                ...list.map((u) {
                                  final email = (u['email'] ?? '').toString();
                                  final canManage = _canManage(u);
                                  return ListTile(
                                    title: Text((u['name'] ?? '').toString()),
                                    subtitle: Text(
                                      email.isEmpty ? 'No email' : email,
                                    ),
                                    trailing: canManage
                                        ? Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                tooltip: 'Edit account',
                                                onPressed: _busy
                                                    ? null
                                                    : () => _editUser(u),
                                                icon: const Icon(
                                                  Icons.edit_outlined,
                                                ),
                                              ),
                                              IconButton(
                                                tooltip: 'Remove',
                                                onPressed: _busy
                                                    ? null
                                                    : () => _deleteUser(u),
                                                icon: const Icon(
                                                  Icons.delete_outline,
                                                ),
                                              ),
                                            ],
                                          )
                                        : Chip(
                                            label: const Text('Protected'),
                                            visualDensity:
                                                VisualDensity.compact,
                                            backgroundColor:
                                                scheme.surfaceContainerHighest,
                                          ),
                                    onTap: canManage && !_busy
                                        ? () => _editUser(u)
                                        : null,
                                  );
                                }),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
    );
  }
}
