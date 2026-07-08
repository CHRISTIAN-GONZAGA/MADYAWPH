import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';

import '../../dio_client.dart';
import '../../widgets/app_input.dart';
import '../../widgets/app_scaffold.dart';

/// Manage owner / admin Gmail addresses for portal and status notifications.
class AdminNotificationEmailsScreen extends StatefulWidget {
  const AdminNotificationEmailsScreen({super.key});

  @override
  State<AdminNotificationEmailsScreen> createState() =>
      _AdminNotificationEmailsScreenState();
}

class _AdminNotificationEmailsScreenState
    extends State<AdminNotificationEmailsScreen> {
  final _ownerEmailCtrl = TextEditingController();
  final _myEmailCtrl = TextEditingController();
  final _adminEmailCtrl = TextEditingController();

  bool _loading = true;
  bool _busy = false;
  bool _canEditAdminEmail = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ownerEmailCtrl.dispose();
    _myEmailCtrl.dispose();
    _adminEmailCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await portalDio().get<Map<String, dynamic>>(
        '/admin/hotel/notification-emails',
      );
      if (!mounted) return;
      final data = res.data ?? const {};
      _ownerEmailCtrl.text = (data['owner_email'] ?? '').toString();
      _myEmailCtrl.text = (data['my_email'] ?? '').toString();
      _adminEmailCtrl.text = (data['admin_email'] ?? '').toString();
      setState(() {
        _canEditAdminEmail = data['can_edit_admin_email'] == true;
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = dioErrorMessage(e);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (_busy) return;

    final owner = _ownerEmailCtrl.text.trim().toLowerCase();
    final myEmail = _myEmailCtrl.text.trim().toLowerCase();
    final adminEmail = _adminEmailCtrl.text.trim().toLowerCase();

    if (owner.isEmpty || !owner.contains('@')) {
      showAppMessage(context, 'Enter a valid owner Gmail address.', isError: true);
      return;
    }
    if (myEmail.isEmpty || !myEmail.contains('@')) {
      showAppMessage(context, 'Enter a valid email for your account.', isError: true);
      return;
    }
    if (_canEditAdminEmail &&
        (adminEmail.isEmpty || !adminEmail.contains('@'))) {
      showAppMessage(context, 'Enter a valid administrator Gmail address.', isError: true);
      return;
    }

    setState(() => _busy = true);
    try {
      final payload = <String, dynamic>{
        'owner_email': owner,
        'my_email': myEmail,
      };
      if (_canEditAdminEmail) {
        payload['admin_email'] = adminEmail;
      }
      final res = await portalDio().patch<Map<String, dynamic>>(
        '/admin/hotel/notification-emails',
        data: payload,
      );
      if (!mounted) return;
      final data = res.data ?? const {};
      _ownerEmailCtrl.text = (data['owner_email'] ?? owner).toString();
      _myEmailCtrl.text = (data['my_email'] ?? myEmail).toString();
      _adminEmailCtrl.text = (data['admin_email'] ?? adminEmail).toString();
      showAppMessage(
        context,
        'Notification emails saved. Guest check-in and room status alerts will use these addresses.',
      );
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

    return AppScaffold(
      appBar: AppBar(
        title: const Text('Notification emails'),
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
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Gmail addresses for hotel notifications',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Owner Gmail receives alerts when a guest signs in through the guest portal QR code and room password. Admin and super admin addresses also receive room status notifications.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 20),
                    AppInput(
                      controller: _ownerEmailCtrl,
                      label: 'Owner Gmail',
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 12),
                    AppInput(
                      controller: _myEmailCtrl,
                      label: _canEditAdminEmail
                          ? 'Your Gmail (super admin)'
                          : 'Your Gmail (admin)',
                      keyboardType: TextInputType.emailAddress,
                    ),
                    if (_canEditAdminEmail) ...[
                      const SizedBox(height: 12),
                      AppInput(
                        controller: _adminEmailCtrl,
                        label: 'Administrator Gmail',
                        keyboardType: TextInputType.emailAddress,
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _busy ? null : _save,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.mark_email_read_outlined),
                      label: Text(_busy ? 'Saving…' : 'Save notification emails'),
                    ),
                  ],
                ),
    );
  }
}
