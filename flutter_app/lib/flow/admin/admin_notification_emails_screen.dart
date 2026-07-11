import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';

import '../../dio_client.dart';
import '../../widgets/app_input.dart';
import '../../widgets/app_scaffold.dart';

/// Manage owner / admin / front desk Gmail addresses for notifications.
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
  final _frontdeskEmailCtrl = TextEditingController();

  bool _loading = true;
  bool _busy = false;
  bool _canEditAdminEmail = false;
  bool _canEditFrontdeskEmail = false;
  String? _error;
  String? _selectedFrontdeskUserId;
  List<Map<String, dynamic>> _frontdeskUsers = const [];

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
    _frontdeskEmailCtrl.dispose();
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
      _applyPayload(data);
      setState(() {
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

    void _applyPayload(Map<String, dynamic> data) {
    _ownerEmailCtrl.text = (data['owner_email'] ?? '').toString();
    _myEmailCtrl.text = (data['my_email'] ?? '').toString();
    _adminEmailCtrl.text = (data['admin_email'] ?? '').toString();
    _canEditAdminEmail = data['can_edit_admin_email'] == true;
    _canEditFrontdeskEmail = data['can_edit_frontdesk_email'] == true;
    _frontdeskUsers = ((data['frontdesk_users'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final selectedId = (data['frontdesk_user_id'] ?? '').toString();
    _selectedFrontdeskUserId = selectedId.isEmpty ? null : selectedId;
    if (_selectedFrontdeskUserId == null && _frontdeskUsers.isNotEmpty) {
      _selectedFrontdeskUserId = (_frontdeskUsers.first['id'] ?? '').toString();
    }
    var fdEmail = (data['frontdesk_email'] ?? '').toString();
    if (fdEmail.isEmpty && _selectedFrontdeskUserId != null) {
      for (final u in _frontdeskUsers) {
        if ((u['id'] ?? '').toString() == _selectedFrontdeskUserId) {
          fdEmail = (u['email'] ?? '').toString();
          break;
        }
      }
    }
    _frontdeskEmailCtrl.text = fdEmail;
  }

  void _onFrontdeskSelected(String? userId) {
    setState(() {
      _selectedFrontdeskUserId = userId;
      var email = '';
      for (final u in _frontdeskUsers) {
        if ((u['id'] ?? '').toString() == userId) {
          email = (u['email'] ?? '').toString();
          break;
        }
      }
      if (email.endsWith('@hotel.local') || email.endsWith('@super.local')) {
        _frontdeskEmailCtrl.text = '';
      } else {
        _frontdeskEmailCtrl.text = email;
      }
    });
  }

  Future<void> _save() async {
    if (_busy) return;

    final owner = _ownerEmailCtrl.text.trim().toLowerCase();
    final myEmail = _myEmailCtrl.text.trim().toLowerCase();
    final adminEmail = _adminEmailCtrl.text.trim().toLowerCase();
    final frontdeskEmail = _frontdeskEmailCtrl.text.trim().toLowerCase();

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
    if (_canEditFrontdeskEmail &&
        _frontdeskUsers.isNotEmpty &&
        (_selectedFrontdeskUserId == null ||
            _selectedFrontdeskUserId!.isEmpty)) {
      showAppMessage(context, 'Select a front desk account.', isError: true);
      return;
    }
    if (_canEditFrontdeskEmail &&
        _selectedFrontdeskUserId != null &&
        _selectedFrontdeskUserId!.isNotEmpty &&
        (frontdeskEmail.isEmpty || !frontdeskEmail.contains('@'))) {
      showAppMessage(
        context,
        'Enter a valid Gmail for the selected front desk account.',
        isError: true,
      );
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
      if (_canEditFrontdeskEmail &&
          _selectedFrontdeskUserId != null &&
          _selectedFrontdeskUserId!.isNotEmpty) {
        payload['frontdesk_user_id'] = _selectedFrontdeskUserId;
        payload['frontdesk_email'] = frontdeskEmail;
      }
      final res = await portalDio().patch<Map<String, dynamic>>(
        '/admin/hotel/notification-emails',
        data: payload,
      );
      if (!mounted) return;
      final data = res.data ?? const {};
      setState(() => _applyPayload(data));
      showAppMessage(
        context,
        'Notification emails saved. Check-in alerts and sales reports will use these addresses.',
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
                      'Owner Gmail receives guest portal login alerts and shift sales summaries. '
                      'Front desk Gmail (set by super admin) also receives Book-section check-in alerts.',
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
                    if (_canEditFrontdeskEmail) ...[
                      const SizedBox(height: 20),
                      Text(
                        'Front desk Gmail',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Choose which front desk account receives check-in alerts, then set their Gmail.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 12),
                      if (_frontdeskUsers.isEmpty)
                        Text(
                          'No front desk accounts yet. Create one under Staff / portal accounts first.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        )
                      else ...[
                        DropdownButtonFormField<String>(
                          value: _selectedFrontdeskUserId != null &&
                                  _frontdeskUsers.any((u) =>
                                      (u['id'] ?? '').toString() ==
                                      _selectedFrontdeskUserId)
                              ? _selectedFrontdeskUserId
                              : null,
                          decoration: const InputDecoration(
                            labelText: 'Front desk account',
                            border: OutlineInputBorder(),
                          ),
                          items: _frontdeskUsers.map((u) {
                            final id = (u['id'] ?? '').toString();
                            final name = (u['name'] ?? '').toString();
                            final email = (u['email'] ?? '').toString();
                            final label = name.isNotEmpty
                                ? (email.isNotEmpty ? '$name ($email)' : name)
                                : (email.isNotEmpty ? email : id);
                            return DropdownMenuItem<String>(
                              value: id,
                              child: Text(label, overflow: TextOverflow.ellipsis),
                            );
                          }).toList(),
                          onChanged: _busy ? null : _onFrontdeskSelected,
                        ),
                        const SizedBox(height: 12),
                        AppInput(
                          controller: _frontdeskEmailCtrl,
                          label: 'Front desk Gmail',
                          keyboardType: TextInputType.emailAddress,
                        ),
                      ],
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
