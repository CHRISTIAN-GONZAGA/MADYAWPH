import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';

import '../auth_storage.dart';
import '../dio_client.dart';
import '../widgets/app_input.dart';
import '../widgets/app_scaffold.dart';
import 'member_dashboard_flow.dart';

/// Member sign-in (username + password set during membership application).
class MemberLoginScreen extends StatefulWidget {
  const MemberLoginScreen({
    super.key,
    this.initialUsername = '',
    this.autoPassword,
    this.popOnSuccess = false,
  });

  final String initialUsername;

  /// When set (e.g. right after approval), attempts login automatically.
  final String? autoPassword;

  /// When true, stores the session and pops with `true` instead of opening the dashboard.
  final bool popOnSuccess;

  @override
  State<MemberLoginScreen> createState() => _MemberLoginScreenState();
}

class _MemberLoginScreenState extends State<MemberLoginScreen> {
  late final TextEditingController _usernameCtrl;
  final _passwordCtrl = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _usernameCtrl = TextEditingController(text: widget.initialUsername);
    if ((widget.autoPassword ?? '').isNotEmpty) {
      _passwordCtrl.text = widget.autoPassword!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _submit();
      });
    }
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (username.isEmpty || password.isEmpty) {
      showAppMessage(context, 'Enter your username and password.', isError: true);
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final res = await publicDio().post<Map<String, dynamic>>(
        '/member/login',
        data: {
          'username': username,
          'password': password,
        },
      );
      final token = (res.data?['member_token'] ?? '').toString();
      if (token.isEmpty) {
        throw StateError('No member_token in response.');
      }
      await AuthStorage.setMemberSession(
        token: token,
        member: res.data?['member'] is Map
            ? Map<String, dynamic>.from(res.data!['member'] as Map)
            : const <String, dynamic>{},
      );
      if (!mounted) return;
      if (widget.popOnSuccess) {
        Navigator.of(context).pop(true);
        return;
      }
      await Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => MemberDashboardScreen(
            initialMember: res.data?['member'] is Map
                ? Map<String, dynamic>.from(res.data!['member'] as Map)
                : null,
          ),
        ),
        (route) => route.isFirst,
      );
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    } catch (e) {
      if (!mounted) return;
      showAppMessage(context, '$e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AppScaffold(
      appBar: AppBar(title: const Text('Member log-in')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'MADYAWPH Member',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Use the username and password you created when you applied for membership.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          AppInput(
            controller: _usernameCtrl,
            label: 'Username',
            textInputAction: TextInputAction.next,
            autocorrect: false,
          ),
          const SizedBox(height: 12),
          AppPasswordField(
            controller: _passwordCtrl,
            labelText: 'Password',
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Log in'),
          ),
        ],
      ),
    );
  }
}
