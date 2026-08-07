import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';

import '../dio_client.dart';
import '../widgets/app_input.dart';
import '../widgets/app_scaffold.dart';

enum ForgotPasswordMode { hotel, member }

/// OTP password reset for hotel portal accounts or MADYAW members.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({
    super.key,
    required this.mode,
    this.initialUsername = '',
    this.hotelId,
    this.role,
  });

  final ForgotPasswordMode mode;
  final String initialUsername;
  final String? hotelId;
  final String? role;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final TextEditingController _usernameCtrl;
  final _codeCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _busy = false;
  bool _codeSent = false;
  String? _emailMasked;

  @override
  void initState() {
    super.initState();
    _usernameCtrl = TextEditingController(text: widget.initialUsername);
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _codeCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  bool get _isHotel => widget.mode == ForgotPasswordMode.hotel;

  String get _sendPath =>
      _isHotel ? '/auth/forgot/send' : '/member/forgot/send';

  String get _resetPath =>
      _isHotel ? '/auth/forgot/reset' : '/member/forgot/reset';

  Future<void> _sendCode() async {
    final username = _usernameCtrl.text.trim();
    if (username.isEmpty) {
      showAppMessage(context, 'Enter your username.', isError: true);
      return;
    }
    if (_isHotel && (widget.hotelId ?? '').trim().isEmpty) {
      showAppMessage(
        context,
        'Sign in to your property first, then try again.',
        isError: true,
      );
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final data = <String, dynamic>{'username': username};
      if (_isHotel) {
        data['hotel_id'] = widget.hotelId;
        final role = (widget.role ?? '').trim();
        if (role.isNotEmpty && role != 'public_customer') {
          data['role'] = role;
        }
      }
      final res = await publicDio().post<Map<String, dynamic>>(
        _sendPath,
        data: data,
      );
      if (!mounted) return;
      final masked = (res.data?['email_masked'] ?? '').toString();
      final message = (res.data?['message'] ?? 'Reset code sent.').toString();
      setState(() {
        _codeSent = true;
        _emailMasked = masked.isEmpty ? null : masked;
      });
      showAppMessage(context, message);
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

  Future<void> _resetPassword() async {
    final username = _usernameCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    final password = _passwordCtrl.text;
    final confirm = _confirmCtrl.text;

    if (username.isEmpty) {
      showAppMessage(context, 'Enter your username.', isError: true);
      return;
    }
    if (code.length != 6) {
      showAppMessage(context, 'Enter the 6-digit code from your email.', isError: true);
      return;
    }
    final minLen = _isHotel ? 8 : 6;
    if (password.length < minLen) {
      showAppMessage(
        context,
        'Password must be at least $minLen characters.',
        isError: true,
      );
      return;
    }
    if (password != confirm) {
      showAppMessage(context, 'Passwords do not match.', isError: true);
      return;
    }
    if (_isHotel && (widget.hotelId ?? '').trim().isEmpty) {
      showAppMessage(
        context,
        'Sign in to your property first, then try again.',
        isError: true,
      );
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final data = <String, dynamic>{
        'username': username,
        'code': code,
        'new_password': password,
        'new_password_confirmation': confirm,
      };
      if (_isHotel) {
        data['hotel_id'] = widget.hotelId;
      }
      final res = await publicDio().post<Map<String, dynamic>>(
        _resetPath,
        data: data,
      );
      if (!mounted) return;
      final message =
          (res.data?['message'] ?? 'Password updated. You may now sign in.')
              .toString();
      await showAppMessage(
        context,
        message,
        title: 'Success',
        confirmLabel: 'Back to login',
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
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
    final title = _isHotel ? 'Reset hotel password' : 'Reset member password';
    final blurb = _isHotel
        ? 'We will email a reset code to this hotel’s super admin contact. '
            'Enter the username for the account you want to unlock.'
        : 'We will email a reset code to the address on your membership.';

    return AppScaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            blurb,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.35,
                ),
          ),
          const SizedBox(height: 20),
          AppInput(
            controller: _usernameCtrl,
            label: 'Username',
            textInputAction: TextInputAction.next,
            autocorrect: false,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _sendCode,
            child: _busy && !_codeSent
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_codeSent ? 'Resend code' : 'Send reset code'),
          ),
          if (_emailMasked != null) ...[
            const SizedBox(height: 10),
            Text(
              'Code sent to $_emailMasked',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
          if (_codeSent) ...[
            const SizedBox(height: 24),
            TextField(
              controller: _codeCtrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '6-digit code',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            AppPasswordField(
              controller: _passwordCtrl,
              labelText: 'New password',
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            AppPasswordField(
              controller: _confirmCtrl,
              labelText: 'Confirm new password',
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _resetPassword,
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Update password'),
            ),
          ],
        ],
      ),
    );
  }
}
