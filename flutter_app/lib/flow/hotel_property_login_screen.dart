import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth_storage.dart';
import '../dio_client.dart';
import '../locale_controller.dart';
import '../ui/app_visual.dart';
import '../widgets/app_input.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/language_picker_button.dart';
import 'central_admin/central_admin_dashboard_screen.dart';
import 'flow_state.dart';
import 'system_access_screen.dart';

/// Property gate: hotel username + password only (no directory picker).
class HotelPropertyLoginScreen extends StatefulWidget {
  const HotelPropertyLoginScreen({super.key, this.onRegisterHotel});

  final VoidCallback? onRegisterHotel;

  @override
  State<HotelPropertyLoginScreen> createState() =>
      _HotelPropertyLoginScreenState();
}

class _HotelPropertyLoginScreenState extends State<HotelPropertyLoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  static const _navy = Color(0xFF1A2B4A);
  static const _gold = Color(0xFFD4A843);

  @override
  void initState() {
    super.initState();
    warmPublicApi();
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final user = _username.text.trim();
    final pass = _password.text;
    if (user.isEmpty || pass.isEmpty) {
      setState(() => _error = context.tr('property_login_required'));
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final res = await publicDio().post<Map<String, dynamic>>(
        '/hotel/access',
        data: {'username': user, 'password': pass},
      );

      if (res.data?['central_admin'] == true) {
        final login = await publicDio().post<Map<String, dynamic>>(
          '/auth/central-admin-login',
          data: {'username': user, 'password': pass},
        );
        final token = (login.data?['token'] ?? '').toString();
        if (token.isEmpty) {
          setState(() {
            _error = context.tr('property_login_failed');
            _busy = false;
          });
          return;
        }
        await AuthStorage.clearGuestAuth();
        await AuthStorage.setHotelContext(id: '', name: '');
        await AuthStorage.setPortalAuth(
          token: token,
          role: 'central_admin',
        );
        hotelSessionNotifier.value = null;
        if (!mounted) return;
        await Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(
            builder: (_) => const CentralAdminDashboardScreen(),
          ),
          (_) => false,
        );
        return;
      }

      final hid = (res.data?['hotel_id'] ?? '').toString();
      final name = (res.data?['hotel_name'] ?? 'Hotel').toString();
      if (hid.isEmpty) {
        setState(() {
          _error = context.tr('property_login_failed');
          _busy = false;
        });
        return;
      }

      HapticFeedback.lightImpact();
      await AuthStorage.setHotelContext(id: hid, name: name);

      final session = HotelSession(hotelId: hid, hotelName: name);
      hotelSessionNotifier.value = session;

      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => SystemAccessScreen(session: session),
        ),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = dioErrorMessage(e);
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  void _openRegister() {
    widget.onRegisterHotel?.call();
  }

  @override
  Widget build(BuildContext context) {
    final visual = AppVisual.of(context);

    return AppScaffold(
      appBar: AppBar(
        title: Text(context.tr('property_sign_in')),
        actions: const [LanguagePickerButton()],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: visual.radiusLg,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      context.tr('property_sign_in'),
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: _navy,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.tr('property_sign_in_sub'),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: _navy.withValues(alpha: 0.65),
                          ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      context.tr('property_username'),
                      style: TextStyle(
                        color: _navy,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _username,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        hintText: context.tr('property_username_hint'),
                        prefixIcon: const Icon(Icons.person_outline, size: 20),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _gold, width: 2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      context.tr('password'),
                      style: TextStyle(
                        color: _navy,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    AppPasswordField(
                      controller: _password,
                      labelText: '',
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        hintText: '••••••••',
                        prefixIcon: const Icon(Icons.lock_outline, size: 20),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _gold, width: 2),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: _navy,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  context.tr('continue_to_system_access'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(Icons.arrow_forward, size: 18),
                              ],
                            ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      context.tr('test_hotel_hint'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: _navy.withValues(alpha: 0.55),
                          ),
                    ),
                    if (widget.onRegisterHotel != null) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _openRegister,
                        child: Text(context.tr('register_hotel')),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
