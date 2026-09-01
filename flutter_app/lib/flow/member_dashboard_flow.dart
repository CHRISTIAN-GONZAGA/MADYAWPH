import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../auth_storage.dart';
import '../utils/money_format.dart';
import '../widgets/guest_online_payment.dart';
import 'customer_booking_status_screen.dart';
import '../dio_client.dart';
import '../widgets/app_scaffold.dart';
import 'public_hotel_search_screen.dart';

/// Logged-in member home: account first, then bookings, then browse.
class MemberDashboardScreen extends StatefulWidget {
  const MemberDashboardScreen({super.key, this.initialMember});

  final Map<String, dynamic>? initialMember;

  @override
  State<MemberDashboardScreen> createState() => _MemberDashboardScreenState();
}

class _MemberDashboardScreenState extends State<MemberDashboardScreen> {
  /// 0 = Account, 1 = Bookings, 2 = Browse
  int _tab = 0;
  Map<String, dynamic>? _member;
  List<Map<String, dynamic>> _activeBookings = [];
  List<Map<String, dynamic>> _completedStays = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _member = widget.initialMember;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _member == null;
      _error = null;
    });
    try {
      final res = await memberDio().get<Map<String, dynamic>>('/member/dashboard');
      if (!mounted) return;
      final data = res.data?['member'];
      final member = data is Map
          ? Map<String, dynamic>.from(data)
          : _member;
      final rawActive = res.data?['active_bookings'];
      final active = rawActive is List
          ? rawActive
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];
      final rawCompleted = res.data?['completed_stays'];
      final completed = rawCompleted is List
          ? rawCompleted
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];
      if (member != null) {
        await AuthStorage.setMemberProfile(
          shidId: (member['member_shid_id'] ?? '').toString(),
          fullName: (member['full_name'] ?? '').toString(),
          discountPercent:
              (member['member_discount_percent'] as num?)?.toDouble() ?? 0,
        );
      }
      if (!mounted) return;
      setState(() {
        _member = member;
        _activeBookings = active;
        _completedStays = completed;
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      if (e.response?.statusCode == 401) {
        await AuthStorage.clearMemberAuth();
        if (!mounted) return;
        Navigator.of(context).popUntil((r) => r.isFirst);
        return;
      }
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

  Future<void> _logout() async {
    try {
      await memberDio().post<Map<String, dynamic>>('/member/logout');
    } catch (_) {}
    await AuthStorage.clearMemberAuth();
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _requestDeletion() async {
    final pending = _member?['deletion_requested'] == true;
    if (pending) {
      showAppMessage(
        context,
        'A deletion request is already waiting for MADYAW to confirm.',
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This sends a request to MADYAW. Your membership stays active until central admin confirms. Then you will not be able to sign in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send request'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await memberDio().post<Map<String, dynamic>>('/member/request-deletion');
      if (!mounted) return;
      showAppMessage(
        context,
        'Deletion request sent. MADYAW will confirm before your account is removed.',
      );
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  String get _title {
    switch (_tab) {
      case 1:
        return 'My bookings';
      case 2:
        return 'Browse stays';
      default:
        return 'My account';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          IconButton(
            tooltip: 'Log out',
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          _AccountPanel(
            loading: _loading,
            error: _error,
            member: _member,
            activeBookingCount: _activeBookings.length,
            onRetry: _load,
            onOpenBookings: () => setState(() => _tab = 1),
            onRequestDeletion: _requestDeletion,
          ),
          _BookingsPanel(
            loading: _loading,
            error: _error,
            activeBookings: _activeBookings,
            completedStays: _completedStays,
            onRetry: _load,
            onBrowse: () => setState(() => _tab = 2),
          ),
          const PublicHotelSearchScreen(
            embeddedInMemberDashboard: true,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: Transform.scale(
              scale: 1.18,
              child: const Icon(Icons.person, size: 26),
            ),
            label: 'Account',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: _activeBookings.isNotEmpty,
              label: Text('${_activeBookings.length}'),
              child: const Icon(Icons.hotel_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: _activeBookings.isNotEmpty,
              label: Text('${_activeBookings.length}'),
              child: Transform.scale(
                scale: 1.18,
                child: const Icon(Icons.hotel, size: 26),
              ),
            ),
            label: 'Bookings',
          ),
          NavigationDestination(
            icon: const Icon(Icons.travel_explore_outlined),
            selectedIcon: Transform.scale(
              scale: 1.18,
              child: const Icon(Icons.travel_explore, size: 26),
            ),
            label: 'Browse',
          ),
        ],
      ),
    );
  }
}

class _AccountPanel extends StatelessWidget {
  const _AccountPanel({
    required this.loading,
    required this.error,
    required this.member,
    required this.activeBookingCount,
    required this.onRetry,
    required this.onOpenBookings,
    required this.onRequestDeletion,
  });

  final bool loading;
  final String? error;
  final Map<String, dynamic>? member;
  final int activeBookingCount;
  final Future<void> Function() onRetry;
  final VoidCallback onOpenBookings;
  final VoidCallback onRequestDeletion;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && member == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final m = member ?? const <String, dynamic>{};
    final name = (m['full_name'] ?? '').toString();
    final username = (m['username'] ?? '').toString();
    final shid = (m['member_shid_id'] ?? '').toString();
    final qr = (m['member_qr_payload'] ?? '').toString();
    final email = (m['email'] ?? '').toString();
    final phone = (m['phone'] ?? '').toString();
    final validUntil =
        _formatValidUntil((m['member_valid_until'] ?? '').toString());

    return RefreshIndicator(
      onRefresh: onRetry,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final qrSize = (constraints.maxWidth - 88).clamp(150.0, 220.0);
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            // Extra bottom inset so account details clear the nav bar.
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: 0.22),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome back',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: scheme.onPrimaryContainer
                                .withValues(alpha: 0.75),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      name.isEmpty ? 'Member' : name,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: scheme.onPrimaryContainer,
                          ),
                    ),
                    if (username.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '@$username',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: scheme.onPrimaryContainer
                                  .withValues(alpha: 0.8),
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _PointsWalletCard(member: m),
              if (activeBookingCount > 0) ...[
                const SizedBox(height: 14),
                Material(
                  color: scheme.secondaryContainer.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    onTap: onOpenBookings,
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                      child: Row(
                        children: [
                          Icon(Icons.hotel, color: scheme.onSecondaryContainer),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '$activeBookingCount active booking'
                              '${activeBookingCount == 1 ? '' : 's'}',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: scheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                          Text(
                            'View',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: scheme.onSecondaryContainer,
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: scheme.onSecondaryContainer,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.7),
                  ),
                ),
                child: Text(
                  () {
                    final earnPct =
                        ((m['points_earn_percent'] as num?)?.toDouble() ?? 0);
                    final bookings =
                        ((m['member_bookings_count'] as num?)?.toDouble() ?? 0)
                            .round();
                    if (earnPct > 0) {
                      return 'Earn ${earnPct.toStringAsFixed(earnPct % 1 == 0 ? 0 : 1)}% of each stay’s price as points. '
                          'You have $bookings linked booking${bookings == 1 ? '' : 's'}.';
                    }
                    return 'Points are credited from your stays. '
                        'You have $bookings linked booking${bookings == 1 ? '' : 's'}.';
                  }(),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Membership ID',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: SelectableText(
                        shid.isEmpty ? '—' : shid,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                            ),
                      ),
                    ),
                    if (shid.isNotEmpty)
                      IconButton(
                        tooltip: 'Copy membership ID',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: shid));
                          showAppMessage(context, 'Membership ID copied.');
                        },
                        icon: const Icon(Icons.copy_outlined),
                      ),
                  ],
                ),
              ),
              if (validUntil.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Valid until $validUntil',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
              const SizedBox(height: 24),
              Text(
                'Your member QR',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Show this QR at the front desk when you pay so they can apply your member discount.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.35,
                    ),
              ),
              const SizedBox(height: 16),
              if (qr.isNotEmpty)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: scheme.outlineVariant),
                      boxShadow: [
                        BoxShadow(
                          color: scheme.shadow.withValues(alpha: 0.06),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: QrImageView(
                      data: qr,
                      size: qrSize,
                      backgroundColor: Colors.white,
                    ),
                  ),
                )
              else
                Text(
                  'QR is not available yet.',
                  style: TextStyle(color: scheme.error),
                ),
              const SizedBox(height: 28),
              Text(
                'Account information',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.7),
                  ),
                ),
                child: Column(
                  children: [
                    if (email.isNotEmpty)
                      _DetailRow(label: 'Email', value: email),
                    if (phone.isNotEmpty)
                      _DetailRow(label: 'Phone', value: phone),
                    if (username.isNotEmpty)
                      _DetailRow(label: 'Username', value: username),
                    if (email.isEmpty && phone.isEmpty && username.isEmpty)
                      Text(
                        'No contact details on file.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (m['deletion_requested'] == true)
                Text(
                  'A deletion request is waiting for MADYAW to confirm. You can still use the app until then.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                )
              else
                OutlinedButton.icon(
                  onPressed: onRequestDeletion,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete account'),
                ),
            ],
          );
        },
      ),
    );
  }

  String _formatValidUntil(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    return '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
  }
}

class _BookingsPanel extends StatelessWidget {
  const _BookingsPanel({
    required this.loading,
    required this.error,
    required this.activeBookings,
    required this.completedStays,
    required this.onRetry,
    required this.onBrowse,
  });

  final bool loading;
  final String? error;
  final List<Map<String, dynamic>> activeBookings;
  final List<Map<String, dynamic>> completedStays;
  final Future<void> Function() onRetry;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (loading && activeBookings.isEmpty && completedStays.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && activeBookings.isEmpty && completedStays.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRetry,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
        children: [
          Text(
            'Active bookings',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Upcoming and in-progress stays linked to your membership.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.35,
                ),
          ),
          const SizedBox(height: 14),
          if (activeBookings.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No active bookings yet.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Browse hotels and book while signed in as a member.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: onBrowse,
                    icon: const Icon(Icons.travel_explore, size: 18),
                    label: const Text('Browse hotels'),
                  ),
                ],
              ),
            )
          else
            ...activeBookings.map((b) => _ActiveBookingCard(booking: b)),
          const SizedBox(height: 28),
          Text(
            'Completed stays',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Past stays linked to your membership after hotel checkout.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.35,
                ),
          ),
          const SizedBox(height: 14),
          if (completedStays.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Text(
                'No completed stays yet. Walk-in and online stays appear here after checkout when your QR was scanned.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.4,
                    ),
              ),
            )
          else
            ...completedStays.map((stay) => _CompletedStayCard(stay: stay)),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompletedStayCard extends StatelessWidget {
  const _CompletedStayCard({required this.stay});

  final Map<String, dynamic> stay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hotel = (stay['hotel_name'] ?? '').toString();
    final room = (stay['room_number'] ?? '').toString();
    final roomName = (stay['room_display_name'] ?? '').toString();
    final checkIn = (stay['check_in_date'] ?? '').toString();
    final checkOut = (stay['check_out_date'] ?? '').toString();
    final payLabel =
        (stay['payment_method_label'] ?? 'Cash at hotel').toString();
    final amountPaid = (stay['amount_paid'] as num?)?.toDouble() ?? 0;
    final total = (stay['total_amount'] as num?)?.toDouble() ?? 0;
    final ref = (stay['reference'] ?? '').toString();
    final source = (stay['booking_source'] ?? '').toString();
    final sourceLabel = source == 'admin-walk-in' ? 'Walk-in' : 'Online';

    final roomLine = room.isNotEmpty
        ? 'Room $room${roomName.isNotEmpty ? ' · $roomName' : ''}'
        : (roomName.isNotEmpty ? roomName : 'Room');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hotel.isEmpty ? 'Hotel' : hotel,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 4),
            Text(roomLine),
            if (checkIn.isNotEmpty || checkOut.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                checkIn.isNotEmpty && checkOut.isNotEmpty
                    ? '$checkIn → $checkOut'
                    : (checkIn.isNotEmpty ? checkIn : checkOut),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Paid: ${formatMoney(amountPaid)} via $payLabel'
              '${total > 0 ? ' · Total ${formatMoney(total)}' : ''}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              [
                sourceLabel,
                if (ref.isNotEmpty) ref,
              ].where((s) => s.isNotEmpty).join(' · '),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveBookingCard extends StatefulWidget {
  const _ActiveBookingCard({required this.booking});

  final Map<String, dynamic> booking;

  @override
  State<_ActiveBookingCard> createState() => _ActiveBookingCardState();
}

class _ActiveBookingCardState extends State<_ActiveBookingCard> {
  Map<String, dynamic> get booking => widget.booking;

  double get _amountDue {
    final deposit = (booking['deposit_required'] as num?)?.toDouble();
    if (deposit != null && deposit > 0) return deposit;
    final paid = (booking['amount_paid'] as num?)?.toDouble() ?? 0;
    final total = (booking['total_amount'] as num?)?.toDouble() ?? 0;
    return (total - paid).clamp(0, double.infinity);
  }

  Future<void> _openStatusScreen() async {
    final hotelId = (booking['hotel_id'] ?? '').toString();
    final ref = (booking['reference'] ?? '').toString();
    if (hotelId.isEmpty || ref.isEmpty) return;
    final contact = await AuthStorage.customerGuestContact();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CustomerBookingStatusScreen(
          hotelId: hotelId,
          hotelName: (booking['hotel_name'] ?? 'Hotel').toString(),
          reference: ref,
          guestEmail: contact?.email ?? '',
          guestPhone: contact?.phone ?? '',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hotel = (booking['hotel_name'] ?? '').toString();
    final room = (booking['room_number'] ?? '').toString();
    final roomName = (booking['room_display_name'] ?? '').toString();
    final checkIn = (booking['check_in_date'] ?? '').toString();
    final checkOut = (booking['check_out_date'] ?? '').toString();
    final payLabel =
        (booking['payment_method_label'] ?? 'Cash at hotel').toString();
    final amountPaid = (booking['amount_paid'] as num?)?.toDouble() ?? 0;
    final total = (booking['total_amount'] as num?)?.toDouble() ?? 0;
    final status = (booking['status'] ?? '').toString();
    final kind = (booking['kind'] ?? 'booking').toString();
    final ref = (booking['reference'] ?? '').toString();
    final needsPay = booking['needs_online_payment'] == true;

    final roomLine = room.isNotEmpty
        ? 'Room $room${roomName.isNotEmpty ? ' · $roomName' : ''}'
        : (roomName.isNotEmpty ? roomName : 'Room TBA');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: needsPay ? scheme.primary : scheme.outlineVariant,
          width: needsPay ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hotel.isEmpty ? 'Hotel' : hotel,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 4),
            Text(roomLine),
            if (checkIn.isNotEmpty || checkOut.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                checkIn.isNotEmpty && checkOut.isNotEmpty
                    ? '$checkIn → $checkOut'
                    : (checkIn.isNotEmpty ? checkIn : checkOut),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
            const SizedBox(height: 8),
            if (needsPay) ...[
              GuestOnlinePaymentPendingCard(
                hotelId: (booking['hotel_id'] ?? '').toString(),
                reference: ref,
                reservation: booking,
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _openStatusScreen,
                child: const Text('View booking status'),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              needsPay
                  ? 'Due now: ${formatMoney(_amountDue)} · Stay total ${formatMoney(total)}'
                  : 'Paid: ${formatMoney(amountPaid)} via $payLabel'
                      '${total > 0 ? ' · Total ${formatMoney(total)}' : ''}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              [
                if (status.isNotEmpty) status.replaceAll('_', ' '),
                if (kind == 'reservation') 'awaiting hotel approval',
                if (ref.isNotEmpty) ref,
              ].where((s) => s.isNotEmpty).join(' · '),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PointsWalletCard extends StatelessWidget {
  const _PointsWalletCard({required this.member});

  final Map<String, dynamic> member;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final points = (member['points_balance'] as num?)?.toInt() ?? 0;
    final pesos = (member['points_balance_pesos'] as num?)?.toDouble() ?? 0;
    final earnPercent =
        (member['points_earn_percent'] as num?)?.toDouble() ?? 0;
    final perPeso = (member['points_per_peso'] as num?)?.toDouble() ?? 10;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Points wallet',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '$points pts',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          Text(
            '≈ ₱${pesos.toStringAsFixed(2)} toward hotel stays',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 10),
          Text(
            earnPercent > 0
                ? 'Earn ${earnPercent.toStringAsFixed(earnPercent % 1 == 0 ? 0 : 1)}% of each stay’s price as points '
                    '(${perPeso.toStringAsFixed(perPeso % 1 == 0 ? 0 : 1)} pts = ₱1). '
                    'Hotels can redeem points from your QR at payment.'
                : 'Points are credited from your stays '
                    '(${perPeso.toStringAsFixed(perPeso % 1 == 0 ? 0 : 1)} pts = ₱1). '
                    'Hotels can redeem points from your QR at payment.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                ),
          ),
        ],
      ),
    );
  }
}
