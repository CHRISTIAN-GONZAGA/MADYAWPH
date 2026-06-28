import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../auth_storage.dart';
import '../../../dio_client.dart';
import '../../../widgets/app_input.dart';
import '../../../widgets/chat_attachment.dart';
import '../admin_portal_users_screen.dart';

/// Super-admin control panel: manage lower-level admin accounts.
class SuperAdminControlSection extends StatefulWidget {
  const SuperAdminControlSection({
    super.key,
    required this.onOpenAccountSettings,
  });

  final VoidCallback onOpenAccountSettings;

  @override
  State<SuperAdminControlSection> createState() =>
      _SuperAdminControlSectionState();
}

class _SuperAdminControlSectionState extends State<SuperAdminControlSection> {
  List<dynamic> _users = const [];
  bool _loading = true;
  bool _busy = false;
  String? _pickerBannerUrl;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _loadPickerBanner() async {
    try {
      final res = await portalDio()
          .get<Map<String, dynamic>>('/admin/hotel/picker-banner');
      if (!mounted) return;
      setState(() {
        _pickerBannerUrl = (res.data?['banner_url'] ?? '').toString().trim();
      });
    } on DioException {
      // Non-blocking; banner card stays empty until upload.
    }
  }

  Future<void> _uploadPickerBanner() async {
    final image = await ChatAttachment.pickRoomImageFromGallery(context);
    if (image == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final form = await ChatAttachment.formWithImage(
        fields: const <String, dynamic>{},
        file: image,
      );
      final res = await portalDio().post<Map<String, dynamic>>(
        '/admin/hotel/picker-banner',
        data: form,
        options: Options(
          contentType: 'multipart/form-data',
          headers: {Headers.acceptHeader: 'application/json'},
        ),
      );
      await AuthStorage.clearHotelsDirectoryCache();
      if (!mounted) return;
      setState(() {
        _pickerBannerUrl =
            (res.data?['banner_url'] ?? '').toString().trim();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Property banner updated. It will appear on the hotel picker.',
          ),
        ),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(dioErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res =
          await portalDio().get<Map<String, dynamic>>('/admin/portal-users');
      if (!mounted) return;
      setState(() {
        _users = (res.data?['data'] as List?) ?? const [];
        _loading = false;
      });
      await _loadPickerBanner();
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(dioErrorMessage(e))));
    }
  }

  Future<void> _addAdmin() async {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    var role = 'admin';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Add portal account'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: role,
                  decoration: const InputDecoration(
                    labelText: 'Account type',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'admin',
                      child: Text('Administrator'),
                    ),
                    DropdownMenuItem(
                      value: 'frontdesk',
                      child: Text('Front desk'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setLocal(() => role = v);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Username (login name)',
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
                  label: 'Password',
                  obscureText: true,
                ),
                const SizedBox(height: 10),
                AppInput(
                  controller: confirmCtrl,
                  label: 'Confirm password',
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match.')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${role == 'frontdesk' ? 'Front desk' : 'Administrator'} account created.')),
      );
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(dioErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteAdmin(String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove administrator?'),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Administrator removed.')),
      );
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(dioErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final admins = _users.whereType<Map<String, dynamic>>().toList();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        Row(
          children: [
            Icon(Icons.admin_panel_settings, color: scheme.primary, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Admin control panel',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Manage administrators and front desk portal accounts. Operational staff (maintenance, etc.) stay under Setup → Staff management.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        Card(
          color: scheme.primaryContainer.withValues(alpha: 0.35),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Your super-admin account',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  'Change your password or manage portal administrators.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: widget.onOpenAccountSettings,
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('Account settings'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Property picker banner',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Shown when guests choose your hotel on the Select property screen.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 16 / 5,
                    child: _pickerBannerUrl != null &&
                            _pickerBannerUrl!.isNotEmpty
                        ? Image.network(
                            ChatAttachment.resolveMediaUrl(_pickerBannerUrl!),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => ColoredBox(
                              color: scheme.surfaceContainerHighest,
                              child: Icon(Icons.image_outlined,
                                  size: 48, color: scheme.outline),
                            ),
                          )
                        : ColoredBox(
                            color: scheme.surfaceContainerHighest,
                            child: Center(
                              child: Icon(Icons.add_photo_alternate_outlined,
                                  size: 48, color: scheme.outline),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _uploadPickerBanner,
                  icon: const Icon(Icons.upload_outlined),
                  label: Text(
                    _pickerBannerUrl != null && _pickerBannerUrl!.isNotEmpty
                        ? 'Change banner image'
                        : 'Add banner image',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                'Portal accounts (${admins.length})',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            FilledButton.icon(
              onPressed: _busy ? null : _addAdmin,
              icon: const Icon(Icons.person_add_alt_1, size: 18),
              label: const Text('Add account'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminPortalUsersScreen(
                      canManageAdmins: true,
                    ),
                  ),
                ).then((_) => _load());
              },
              child: const Text('Manage all'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_loading)
          const Center(child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(),
          ))
        else if (admins.isEmpty)
          const Text('No administrator accounts found.')
        else
          ...admins.map((u) {
            final role = (u['role'] ?? '').toString();
            final id = (u['id'] ?? '').toString();
            final name = (u['name'] ?? '').toString();
            final email = (u['email'] ?? '').toString();
            final isSuper = role == 'super_admin';
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: isSuper
                      ? scheme.tertiaryContainer
                      : scheme.secondaryContainer,
                  child: Icon(
                    isSuper ? Icons.shield_outlined : Icons.badge_outlined,
                    color: isSuper
                        ? scheme.onTertiaryContainer
                        : scheme.onSecondaryContainer,
                  ),
                ),
                title: Text(name),
                subtitle: Text(
                  [
                    role.replaceAll('_', ' ').toUpperCase(),
                    if (email.isNotEmpty) email,
                  ].join('\n'),
                ),
                isThreeLine: true,
                trailing: isSuper
                    ? Chip(
                        label: const Text('You'),
                        backgroundColor: scheme.tertiaryContainer,
                      )
                    : (role == 'admin' || role == 'frontdesk')
                        ? IconButton(
                            tooltip: 'Remove account',
                            onPressed:
                                _busy ? null : () => _deleteAdmin(id, name),
                            icon: const Icon(Icons.delete_outline),
                          )
                        : null,
              ),
            );
          }),
      ],
    );
  }
}
