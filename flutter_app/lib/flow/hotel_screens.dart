import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../auth_storage.dart';
import 'hotel_how_to.dart';
import '../dio_client.dart';
import '../ui/app_visual.dart';
import '../widgets/app_scaffold.dart';
import 'dashboards.dart';
import 'flow_state.dart';

// --- Hotel gate (sign-in + create hotel) ---

class HotelGateScreen extends StatefulWidget {
  const HotelGateScreen({super.key});

  @override
  State<HotelGateScreen> createState() => _HotelGateScreenState();
}

class _HotelGateScreenState extends State<HotelGateScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await publicDio().post<Map<String, dynamic>>(
        '/hotel/access',
        data: {
          'username': _user.text.trim(),
          'password': _pass.text,
        },
      );
      final hid = res.data?['hotel_id'] as String?;
      final hname = res.data?['hotel_name'] as String? ?? 'Hotel';
      if (hid == null || hid.isEmpty) {
        setState(() {
          _error = 'Unexpected response.';
          _busy = false;
        });
        return;
      }
      await AuthStorage.setHotelContext(id: hid, name: hname);
      await AuthStorage.clearPortalAuth();
      await AuthStorage.clearGuestAuth();
      if (!mounted) return;
      hotelSessionNotifier.value = HotelSession(hotelId: hid, hotelName: hname);
    } on DioException catch (e) {
      setState(() {
        _error = dioErrorMessage(e);
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  Future<void> _openRegister() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const HotelRegisterScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppScaffold(
      appBar: AppBar(
        title: const Text('MADYAWPH · Hotel access'),
        actions: [
          TextButton.icon(
            onPressed: () => HotelHowToGuide.show(context),
            icon: const Icon(Icons.help_outline, size: 20),
            label: const Text('How to'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                  Text(
                    'MADYAWPH',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Hotel operations hub — sign in to manage rooms, staff, guests, and bookings.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Material(
                    elevation: 2,
                    shadowColor: Colors.black26,
                    borderRadius: BorderRadius.circular(20),
                    color: theme.colorScheme.surfaceContainerHigh,
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _user,
                            decoration: const InputDecoration(
                              labelText: 'Hotel username',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _pass,
                            decoration: const InputDecoration(
                              labelText: 'Password',
                              prefixIcon: Icon(Icons.lock_outline),
                            ),
                            obscureText: true,
                            onSubmitted: (_) => _busy ? null : _submit(),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            Text(
                              _error!,
                              style:
                                  TextStyle(color: theme.colorScheme.error),
                            ),
                          ],
                          const SizedBox(height: 22),
                          FilledButton(
                            onPressed: _busy ? null : _submit,
                            child: _busy
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Text('Continue'),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _openRegister,
                            icon: const Icon(Icons.add_business_outlined),
                            label: const Text('Register new hotel'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    );
  }
}

class HotelRegisterScreen extends StatefulWidget {
  const HotelRegisterScreen({super.key});

  @override
  State<HotelRegisterScreen> createState() => _HotelRegisterScreenState();
}

class _HotelRegisterScreenState extends State<HotelRegisterScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();
  final _hotelName = TextEditingController();
  final _location = TextEditingController();
  final _contact = TextEditingController();
  final _adminEmail = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _password2.dispose();
    _hotelName.dispose();
    _location.dispose();
    _contact.dispose();
    _adminEmail.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await publicDio().post<Map<String, dynamic>>(
        '/hotel/register',
        data: {
          'username': _username.text.trim(),
          'password': _password.text,
          'password_confirmation': _password2.text,
          'hotel_name': _hotelName.text.trim(),
          'location': _location.text.trim(),
          'contact_number': _contact.text.trim(),
          'admin_email': _adminEmail.text.trim(),
        },
      );
      final hid = res.data?['hotel_id'] as String?;
      final token = res.data?['token'] as String?;
      if (hid == null || token == null || token.isEmpty) {
        setState(() {
          _error = 'Unexpected response.';
          _busy = false;
        });
        return;
      }
      final name = _hotelName.text.trim();
      await AuthStorage.setHotelContext(id: hid, name: name);
      await AuthStorage.setPortalAuth(token: token, role: 'admin');
      await AuthStorage.clearGuestAuth();
      if (!mounted) return;
      final sms = res.data?['sms'] as Map<String, dynamic>?;
      final smsSent = sms?['sent'] == true;
      final verificationCode =
          (res.data?['verification_code'] ?? '').toString();
      if (!smsSent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              verificationCode.isNotEmpty
                  ? 'SMS not delivered. Verification code: $verificationCode (also in the next screen).'
                  : 'SMS not delivered. Check server SEMAPHORE_API_KEY or Semaphore dashboard.',
            ),
            duration: const Duration(seconds: 8),
          ),
        );
      }
      await showHotelRegistrationCredentialsDialog(
        context,
        hotelName: name,
        portalAccounts: res.data?['portal_accounts'] as Map<String, dynamic>?,
        sms: sms,
        verificationCode:
            verificationCode.isNotEmpty ? verificationCode : null,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      hotelSessionNotifier.value = HotelSession(hotelId: hid, hotelName: name);
    } on DioException catch (e) {
      setState(() {
        _error = dioErrorMessage(e);
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppBar(title: const Text('Create hotel')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(
            controller: _hotelName,
            decoration: const InputDecoration(labelText: 'Hotel name', border: OutlineInputBorder()),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _location,
            decoration: const InputDecoration(labelText: 'Location', border: OutlineInputBorder()),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _contact,
            decoration: const InputDecoration(labelText: 'Contact number (SMS)', border: OutlineInputBorder()),
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _adminEmail,
            decoration: const InputDecoration(labelText: 'Admin email', border: OutlineInputBorder()),
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          TextField(
            controller: _username,
            decoration: const InputDecoration(
              labelText: 'Hotel username (property login)',
              border: OutlineInputBorder(),
            ),
            autocorrect: false,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
            obscureText: true,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password2,
            decoration: const InputDecoration(labelText: 'Confirm password', border: OutlineInputBorder()),
            obscureText: true,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Create hotel & go to menu'),
          ),
        ],
      ),
    );
  }
}

// --- Role menu ---

class RoleMenuScreen extends StatelessWidget {
  const RoleMenuScreen({super.key, required this.session});

  final HotelSession session;

  Future<void> _switchHotel(BuildContext context) async {
    await AuthStorage.clearAll();
    hotelSessionNotifier.value = null;
  }

  Future<void> _openAdmin(BuildContext context) async {
    final token = await AuthStorage.portalToken();
    final role = await AuthStorage.portalRole();
    if (!context.mounted) return;
    if (token != null && (role == 'admin' || role == 'super_admin')) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => AdminDashboardScreen(
            isSuperAdmin: role == 'super_admin',
          ),
        ),
      );
      return;
    }
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const PortalLoginScreen(role: 'admin'),
      ),
    );
    if (ok == true && context.mounted) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const AdminDashboardScreen()),
      );
    }
  }

  Future<void> _openSuperAdmin(BuildContext context) async {
    final token = await AuthStorage.portalToken();
    final role = await AuthStorage.portalRole();
    if (!context.mounted) return;
    if (token != null && role == 'super_admin') {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const AdminDashboardScreen(isSuperAdmin: true),
        ),
      );
      return;
    }
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const PortalLoginScreen(role: 'super_admin'),
      ),
    );
    if (ok == true && context.mounted) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const AdminDashboardScreen(isSuperAdmin: true),
        ),
      );
    }
  }

  Future<void> _openStaff(BuildContext context) async {
    final token = await AuthStorage.portalToken();
    final role = await AuthStorage.portalRole();
    if (!context.mounted) return;
    if (token != null && role == 'staff') {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const StaffDashboardScreen()),
      );
      return;
    }
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const PortalLoginScreen(role: 'staff'),
      ),
    );
    if (ok == true && context.mounted) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const StaffDashboardScreen()),
      );
    }
  }

  Future<void> _openCustomer(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CustomerDashboardScreen(hotelId: session.hotelId),
      ),
    );
  }

  Future<void> _openGuest(BuildContext context) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => GuestRoomLoginScreen(hotelId: session.hotelId),
      ),
    );
    if (ok == true && context.mounted) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const GuestDashboardScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppScaffold(
      appBar: AppBar(
        title: const Text('MADYAWPH'),
        actions: [
          TextButton(
            onPressed: () => _switchHotel(context),
            child: const Text('Switch hotel'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(session.hotelName, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'Choose how you want to use the app.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          _RoleCard(
            icon: Icons.admin_panel_settings_outlined,
            title: 'Administrator',
            subtitle: 'Day-to-day ops — rooms, bookings, reports',
            color: theme.colorScheme.primaryContainer,
            onTap: () => _openAdmin(context),
          ),
          const SizedBox(height: 12),
          _RoleCard(
            icon: Icons.shield_outlined,
            title: 'Super admin',
            subtitle: 'Hotel owner — manage admins & property login',
            color: theme.colorScheme.errorContainer,
            onTap: () => _openSuperAdmin(context),
          ),
          const SizedBox(height: 12),
          _RoleCard(
            icon: Icons.support_agent_outlined,
            title: 'Staff',
            subtitle: 'Tasks, rooms, guest messages',
            color: theme.colorScheme.secondaryContainer,
            onTap: () => _openStaff(context),
          ),
          const SizedBox(height: 12),
          _RoleCard(
            icon: Icons.storefront_outlined,
            title: 'Public customer',
            subtitle: 'Browse categories and rooms (booking)',
            color: theme.colorScheme.tertiaryContainer,
            onTap: () => _openCustomer(context),
          ),
          const SizedBox(height: 12),
          _RoleCard(
            icon: Icons.hotel_class_outlined,
            title: 'Guest',
            subtitle: 'In-house guest — room number & room password',
            color: theme.colorScheme.surfaceContainerHighest,
            onTap: () => _openGuest(context),
          ),
        ],
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visual = AppVisual.of(context);
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: visual.radiusLg,
        boxShadow: visual.cardShadow,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: ClipRRect(
        borderRadius: visual.radiusLg,
        child: Material(
          color: color,
          child: InkWell(
            onTap: onTap,
            splashColor: scheme.primary.withValues(alpha: 0.12),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Hero(
                    tag: 'role_$title',
                    child: Icon(icon, size: 40),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(subtitle,
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: scheme.outline),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PortalLoginScreen extends StatefulWidget {
  const PortalLoginScreen({super.key, required this.role});

  final String role;

  @override
  State<PortalLoginScreen> createState() => _PortalLoginScreenState();
}

class _PortalLoginScreenState extends State<PortalLoginScreen> {
  final _id = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _id.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final hotelId = await AuthStorage.hotelId();
    if (hotelId == null || hotelId.isEmpty) {
      setState(() => _error = 'Hotel session missing. Use Switch hotel and sign in again.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final trimmed = _id.text.trim();
      final body = <String, dynamic>{
        'role': widget.role,
        'password': _pass.text,
        'hotel_id': hotelId,
      };
      if (trimmed.contains('@')) {
        body['email'] = trimmed;
      } else {
        body['username'] = trimmed;
      }
      final res = await publicDio().post<Map<String, dynamic>>('/auth/portal-login', data: body);
      final token = res.data?['token'] as String?;
      if (token == null || token.isEmpty) {
        setState(() {
          _error = 'No token returned.';
          _busy = false;
        });
        return;
      }
      final serverRole = res.data?['role'] as String?;
      await AuthStorage.setPortalAuth(
        token: token,
        role: (serverRole != null && serverRole.isNotEmpty) ? serverRole : widget.role,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on DioException catch (e) {
      setState(() {
        _error = dioErrorMessage(e);
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = switch (widget.role) {
      'super_admin' => 'Super administrator',
      'admin' => 'Administrator',
      _ => 'Staff',
    };
    return AppScaffold(
      appBar: AppBar(title: Text('$label sign-in')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Use your $label account (name or email) and password for this hotel.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _id,
            decoration: const InputDecoration(
              labelText: 'Username or email',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pass,
            decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
            obscureText: true,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Sign in'),
          ),
        ],
      ),
    );
  }
}

class GuestRoomLoginScreen extends StatefulWidget {
  const GuestRoomLoginScreen({super.key, required this.hotelId});

  final String hotelId;

  @override
  State<GuestRoomLoginScreen> createState() => _GuestRoomLoginScreenState();
}

class _GuestRoomLoginScreenState extends State<GuestRoomLoginScreen> {
  final _room = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _room.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pwd = _password.text.trim();
    if (pwd.length != 4) {
      setState(() => _error = 'Room password must be exactly 4 characters.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await publicDio().post<Map<String, dynamic>>(
        '/guest/login',
        data: {
          'hotel_id': widget.hotelId,
          'room': _room.text.trim(),
          'password': pwd,
        },
      );
      final token = res.data?['guest_token'] as String?;
      if (token == null || token.isEmpty) {
        setState(() {
          _error = 'No guest_token in response.';
          _busy = false;
        });
        return;
      }
      await AuthStorage.setGuestToken(token);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on DioException catch (e) {
      setState(() {
        _error = dioErrorMessage(e);
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppBar(title: const Text('Guest sign-in')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(
            controller: _room,
            decoration: const InputDecoration(labelText: 'Room number', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            maxLength: 4,
            decoration: const InputDecoration(
              labelText: 'Room password (4 characters)',
              border: OutlineInputBorder(),
              counterText: '',
              helperText: 'Exactly 4 letters or numbers (e.g. 1234, a1b2)',
            ),
            obscureText: true,
            autocorrect: false,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Continue'),
          ),
        ],
      ),
    );
  }
}
