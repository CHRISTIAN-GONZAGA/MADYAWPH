import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../auth_storage.dart';
import '../dio_client.dart';
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
    return Scaffold(
      appBar: AppBar(title: const Text('Hotel sign-in')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Sign in with your hotel gate account. After that you can open admin, staff, customer, or guest flows.',
            style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _user,
            decoration: const InputDecoration(
              labelText: 'Hotel username',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
            autocorrect: false,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pass,
            decoration: const InputDecoration(
              labelText: 'Password',
              border: OutlineInputBorder(),
            ),
            obscureText: true,
            onSubmitted: (_) => _busy ? null : _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
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
                : const Text('Continue to menu'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _openRegister,
            icon: const Icon(Icons.add_business_outlined),
            label: const Text('Create new hotel'),
          ),
        ],
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
    return Scaffold(
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
            decoration: const InputDecoration(labelText: 'Admin username (unique)', border: OutlineInputBorder()),
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
    if (token != null && role == 'admin') {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const AdminDashboardScreen()),
      );
      return;
    }
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => PortalLoginScreen(role: 'admin'),
      ),
    );
    if (ok == true && context.mounted) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const AdminDashboardScreen()),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gloretto'),
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
            subtitle: 'Hotel admin dashboard, credits, rooms',
            color: theme.colorScheme.primaryContainer,
            onTap: () => _openAdmin(context),
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
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(icon, size: 40),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
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
    final label = widget.role == 'admin' ? 'Administrator' : 'Staff';
    return Scaffold(
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
          'password': _password.text,
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
    return Scaffold(
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
            decoration: const InputDecoration(labelText: 'Room password', border: OutlineInputBorder()),
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
                : const Text('Continue'),
          ),
        ],
      ),
    );
  }
}
