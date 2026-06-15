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
import 'dashboards.dart';
import 'flow_state.dart';
import 'hotel_property_login_screen.dart';
import 'owner_dashboard_screen.dart';

/// Role-based portal sign-in after property gate (System Access UI).
class SystemAccessScreen extends StatefulWidget {
  const SystemAccessScreen({super.key, required this.session});

  final HotelSession session;

  @override
  State<SystemAccessScreen> createState() => _SystemAccessScreenState();
}

class _SystemAccessScreenState extends State<SystemAccessScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();

  static const _navy = Color(0xFF1A2B4A);
  static const _gold = Color(0xFFD4A843);

  String? _role;
  bool _busy = false;
  String? _error;

  static const _roles = <String, String>{
    'admin': 'admin_frontdesk',
    'super_admin': 'super_admin',
    'staff': 'staff',
    'owner': 'hotel_owner',
    'public_customer': 'public_customer',
  };

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _isPublicCustomer => _role == 'public_customer';

  Future<void> _switchHotel() async {
    await AuthStorage.clearAll();
    hotelSessionNotifier.value = null;
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => const HotelPropertyLoginScreen(),
      ),
      (_) => false,
    );
  }

  Future<void> _openDashboard(Widget screen) async {
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }

  Future<bool> _tryResumeWithSavedToken(String expectedRole) async {
    final token = await AuthStorage.portalToken();
    final savedRole = await AuthStorage.portalRole();
    if (token == null || token.isEmpty || savedRole == null) return false;

    final savedHotelId = await AuthStorage.hotelId();
    if (savedHotelId == null ||
        savedHotelId.isEmpty ||
        savedHotelId != widget.session.hotelId) {
      await AuthStorage.clearPortalAuth();
      return false;
    }

    switch (expectedRole) {
      case 'admin':
        if (savedRole != 'admin' && savedRole != 'super_admin') return false;
        await _openDashboard(
          AdminDashboardScreen(isSuperAdmin: savedRole == 'super_admin'),
        );
        return true;
      case 'super_admin':
        if (savedRole != 'super_admin') return false;
        await _openDashboard(const AdminDashboardScreen(isSuperAdmin: true));
        return true;
      case 'staff':
        if (savedRole != 'staff') return false;
        await _openDashboard(const StaffDashboardScreen());
        return true;
      case 'owner':
        if (savedRole != 'owner' && savedRole != 'super_admin') return false;
        await _openDashboard(const OwnerDashboardScreen());
        return true;
      default:
        return false;
    }
  }

  Future<void> _submit() async {
    final role = _role;
    if (role == null || role.isEmpty) {
      setState(() => _error = context.tr('select_role_first'));
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      if (_isPublicCustomer) {
        await AuthStorage.clearPortalAuth();
        await AuthStorage.clearGuestAuth();
        HapticFeedback.lightImpact();
        if (!mounted) return;
        await _openDashboard(
          CustomerDashboardScreen(hotelId: widget.session.hotelId),
        );
        return;
      }

      if (await _tryResumeWithSavedToken(role)) return;

      final hotelId = widget.session.hotelId;
      final trimmed = _username.text.trim();
      final pass = _password.text;
      if (trimmed.isEmpty || pass.isEmpty) {
        setState(() {
          _error = context.tr('credentials_required');
          _busy = false;
        });
        return;
      }

      final body = <String, dynamic>{
        'role': role,
        'password': pass,
        'hotel_id': hotelId,
      };
      if (trimmed.contains('@')) {
        body['email'] = trimmed;
      } else {
        body['username'] = trimmed;
      }

      final res = await publicDio().post<Map<String, dynamic>>(
        '/auth/portal-login',
        data: body,
      );
      final token = res.data?['token'] as String?;
      if (token == null || token.isEmpty) {
        setState(() {
          _error = 'No token returned.';
          _busy = false;
        });
        return;
      }

      final serverRole = (res.data?['role'] as String?) ?? role;
      await AuthStorage.setPortalAuth(token: token, role: serverRole);
      await AuthStorage.clearGuestAuth();
      HapticFeedback.lightImpact();

      if (!mounted) return;
      switch (role) {
        case 'admin':
          await _openDashboard(
            AdminDashboardScreen(isSuperAdmin: serverRole == 'super_admin'),
          );
        case 'super_admin':
          await _openDashboard(
            const AdminDashboardScreen(isSuperAdmin: true),
          );
        case 'staff':
          await _openDashboard(const StaffDashboardScreen());
        case 'owner':
          await _openDashboard(const OwnerDashboardScreen());
      }
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
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visual = AppVisual.of(context);

    return AppScaffold(
      appBar: AppBar(
        title: Text(context.tr('system_access')),
        actions: [
          const LanguagePickerButton(),
          TextButton.icon(
            onPressed: _switchHotel,
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: Text(context.tr('switch_hotel')),
          ),
        ],
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
                      context.tr('system_access'),
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: _navy,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.tr('system_access_sub'),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: _navy.withValues(alpha: 0.65),
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.session.hotelName,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: _navy,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 24),
                    if (!_isPublicCustomer) ...[
                      Text(
                        context.tr('username'),
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
                          hintText: context.tr('username_or_email'),
                          prefixIcon:
                              const Icon(Icons.person_outline, size: 20),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: _gold, width: 2),
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
                          prefixIcon:
                              const Icon(Icons.lock_outline, size: 20),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: _gold, width: 2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                    ] else ...[
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: _navy.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Text(
                            context.tr('public_customer_no_login'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                    Text(
                      context.tr('select_role'),
                      style: TextStyle(
                        color: _navy,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _role,
                      hint: Text(context.tr('choose_department')),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _gold, width: 2),
                        ),
                      ),
                      items: _roles.entries
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(context.tr(e.value)),
                            ),
                          )
                          .toList(),
                      onChanged: _busy
                          ? null
                          : (v) => setState(() {
                                _role = v;
                                _error = null;
                              }),
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
                                  context.tr('secure_login'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(Icons.arrow_forward, size: 18),
                              ],
                            ),
                    ),
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
