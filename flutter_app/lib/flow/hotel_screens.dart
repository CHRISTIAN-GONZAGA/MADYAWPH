import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../auth_storage.dart';
import 'hotel_how_to.dart';
import '../dio_client.dart';
import '../ui/app_visual.dart';
import '../locale_controller.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/language_picker_button.dart';
import 'dashboards.dart';
import 'flow_state.dart';

// --- Choose hotel (by city/region) → role menu ---

class ChooseHotelScreen extends StatefulWidget {
  const ChooseHotelScreen({super.key});

  @override
  State<ChooseHotelScreen> createState() => _ChooseHotelScreenState();
}

class _ChooseHotelScreenState extends State<ChooseHotelScreen> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _regions = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await publicDio().get<Map<String, dynamic>>('/hotels');
      final regions =
          (res.data?['regions'] as List<dynamic>?)?.whereType<Map>().map(
                (m) => Map<String, dynamic>.from(m),
              ).toList() ??
              const [];
      if (!mounted) return;
      setState(() {
        _regions = regions;
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

  String get _query => _search.text.trim().toLowerCase();

  List<Map<String, dynamic>> get _filteredRegions {
    if (_query.isEmpty) return _regions;
    final out = <Map<String, dynamic>>[];
    for (final region in _regions) {
      final name = (region['region'] ?? '').toString();
      final hotels = (region['hotels'] as List<dynamic>?) ?? const [];
      final matched = hotels.whereType<Map>().where((h) {
        final hotelName = (h['name'] ?? '').toString().toLowerCase();
        final loc = (h['location'] ?? '').toString().toLowerCase();
        final city = (h['city'] ?? name).toString().toLowerCase();
        return name.toLowerCase().contains(_query) ||
            hotelName.contains(_query) ||
            loc.contains(_query) ||
            city.contains(_query);
      }).map((h) => Map<String, dynamic>.from(h)).toList();
      if (matched.isNotEmpty) {
        out.add({'region': name, 'hotels': matched});
      }
    }
    return out;
  }

  Future<void> _selectHotel(Map<String, dynamic> hotel) async {
    final hid = (hotel['id'] ?? '').toString();
    final hname = (hotel['name'] ?? 'Hotel').toString();
    if (hid.isEmpty) return;
    await AuthStorage.setHotelContext(id: hid, name: hname);
    await AuthStorage.clearPortalAuth();
    await AuthStorage.clearGuestAuth();
    if (!mounted) return;
    hotelSessionNotifier.value = HotelSession(hotelId: hid, hotelName: hname);
  }

  Future<void> _openRegister() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const HotelRegisterScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final regions = _filteredRegions;

    return AppScaffold(
      appBar: AppBar(
        title: Text('${context.tr('app_title')} · ${context.tr('choose_hotel')}'),
        actions: [
          const LanguagePickerButton(),
          TextButton.icon(
            onPressed: () => HotelHowToGuide.show(context),
            icon: const Icon(Icons.help_outline, size: 20),
            label: Text(context.tr('how_to')),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.tr('select_property'),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.tr('choose_hotel_hint'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: context.tr('search_hotels'),
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: theme.colorScheme.error),
                                ),
                                const SizedBox(height: 16),
                                FilledButton(
                                  onPressed: _load,
                                  child: Text(context.tr('retry')),
                                ),
                              ],
                            ),
                          ),
                        )
                      : regions.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  _query.isEmpty
                                      ? context.tr('no_hotels')
                                      : context.tr('no_search_results'),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _load,
                              child: ListView.builder(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                                itemCount: regions.length,
                                itemBuilder: (context, i) {
                                  final block = regions[i];
                                  final region =
                                      (block['region'] ?? 'Other').toString();
                                  final hotels =
                                      (block['hotels'] as List<dynamic>?) ??
                                          const [];
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          top: 12,
                                          bottom: 8,
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.location_city_outlined,
                                              size: 20,
                                              color: theme.colorScheme.primary,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              region,
                                              style: theme
                                                  .textTheme.titleMedium
                                                  ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              '${hotels.length}',
                                              style: theme
                                                  .textTheme.labelLarge
                                                  ?.copyWith(
                                                color: theme.colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      ...hotels.whereType<Map>().map((raw) {
                                        final hotel =
                                            Map<String, dynamic>.from(raw);
                                        final loc =
                                            (hotel['location'] ?? '')
                                                .toString();
                                        return Card(
                                          margin: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          clipBehavior: Clip.antiAlias,
                                          child: ListTile(
                                            leading: CircleAvatar(
                                              backgroundColor: theme
                                                  .colorScheme
                                                  .primaryContainer,
                                              child: Icon(
                                                Icons.apartment_outlined,
                                                color: theme
                                                    .colorScheme.primary,
                                              ),
                                            ),
                                            title: Text(
                                              (hotel['name'] ?? 'Hotel')
                                                  .toString(),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            subtitle: loc.isEmpty
                                                ? null
                                                : Text(loc),
                                            trailing: const Icon(
                                              Icons.chevron_right,
                                            ),
                                            onTap: () => _selectHotel(hotel),
                                          ),
                                        );
                                      }),
                                    ],
                                  );
                                },
                              ),
                            ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openRegister,
        icon: const Icon(Icons.add_business_outlined),
        label: Text(context.tr('register_hotel')),
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
  final _city = TextEditingController();
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
    _city.dispose();
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
          'city': _city.text.trim().isNotEmpty
              ? _city.text.trim()
              : _location.text.trim(),
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
            controller: _city,
            decoration: const InputDecoration(
              labelText: 'City / region (e.g. Butuan)',
              border: OutlineInputBorder(),
              helperText: 'Used to group hotels on the choose-hotel screen',
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _location,
            decoration: const InputDecoration(
              labelText: 'Full address or area',
              border: OutlineInputBorder(),
            ),
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
              labelText: 'Owner username (internal)',
              border: OutlineInputBorder(),
              helperText: 'For super admin sign-in; not used on the hotel picker',
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
        title: Text(context.tr('app_title')),
        actions: [
          const LanguagePickerButton(),
          TextButton(
            onPressed: () => _switchHotel(context),
            child: Text(context.tr('switch_hotel')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(session.hotelName, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            context.tr('choose_role_hint'),
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          _RoleCard(
            icon: Icons.admin_panel_settings_outlined,
            title: context.tr('administrator'),
            subtitle: context.tr('administrator_sub'),
            color: theme.colorScheme.primaryContainer,
            onTap: () => _openAdmin(context),
          ),
          const SizedBox(height: 12),
          _RoleCard(
            icon: Icons.shield_outlined,
            title: context.tr('super_admin'),
            subtitle: context.tr('super_admin_sub'),
            color: theme.colorScheme.errorContainer,
            onTap: () => _openSuperAdmin(context),
          ),
          const SizedBox(height: 12),
          _RoleCard(
            icon: Icons.support_agent_outlined,
            title: context.tr('staff'),
            subtitle: context.tr('staff_sub'),
            color: theme.colorScheme.secondaryContainer,
            onTap: () => _openStaff(context),
          ),
          const SizedBox(height: 12),
          _RoleCard(
            icon: Icons.storefront_outlined,
            title: context.tr('public_customer'),
            subtitle: context.tr('public_customer_sub'),
            color: theme.colorScheme.tertiaryContainer,
            onTap: () => _openCustomer(context),
          ),
          const SizedBox(height: 12),
          _RoleCard(
            icon: Icons.hotel_class_outlined,
            title: context.tr('guest'),
            subtitle: context.tr('guest_sub'),
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
      setState(() => _error = context.tr('select_hotel_first'));
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
