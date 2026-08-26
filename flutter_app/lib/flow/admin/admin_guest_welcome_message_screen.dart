import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';

import '../../dio_client.dart';
import '../../widgets/app_input.dart';

/// Hotel admin: custom greeting emailed (Resend) when a guest is checked in.
class AdminGuestWelcomeMessageScreen extends StatefulWidget {
  const AdminGuestWelcomeMessageScreen({super.key});

  @override
  State<AdminGuestWelcomeMessageScreen> createState() =>
      _AdminGuestWelcomeMessageScreenState();
}

class _AdminGuestWelcomeMessageScreenState
    extends State<AdminGuestWelcomeMessageScreen> {
  final _ctrl = TextEditingController();
  String _defaultMessage = 'Please enjoy your stay!';
  bool _loading = true;
  bool _saving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await portalDio()
          .get<Map<String, dynamic>>('/admin/settings/guest-welcome-message');
      if (!mounted) return;
      final data = res.data ?? const {};
      setState(() {
        _ctrl.text = (data['guest_welcome_message'] ?? '').toString();
        final fallback =
            (data['guest_welcome_message_default'] ?? '').toString().trim();
        if (fallback.isNotEmpty) _defaultMessage = fallback;
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await portalDio().patch<Map<String, dynamic>>(
        '/admin/settings/guest-welcome-message',
        data: {'guest_welcome_message': _ctrl.text.trim()},
      );
      if (!mounted) return;
      setState(() => _saving = false);
      showAppMessage(
        context,
        'Welcome email updated. Guests receive this on check-in '
        '(walk-in and online).',
      );
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Guest welcome email')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'This greeting is emailed to the guest when they are checked in, '
                  'whether they booked at the desk or online (member and non-member). '
                  'Room number and access password are always included.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                AppInput(
                  controller: _ctrl,
                  label: 'Welcome message',
                  hint: _defaultMessage,
                  maxLines: 8,
                  maxLength: 2000,
                ),
                const SizedBox(height: 8),
                Text(
                  'Leave blank to use the default: “$_defaultMessage”\n'
                  'Optional placeholders: {guest_name}, {hotel_name}, {room_number}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving…' : 'Save welcome message'),
                ),
              ],
            ),
    );
  }
}
