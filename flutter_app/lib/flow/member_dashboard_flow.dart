import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../auth_storage.dart';
import '../dio_client.dart';
import '../widgets/app_scaffold.dart';
import 'public_hotel_search_screen.dart';

/// Logged-in member home: browse hotels + membership QR / SHID.
class MemberDashboardScreen extends StatefulWidget {
  const MemberDashboardScreen({super.key, this.initialMember});

  final Map<String, dynamic>? initialMember;

  @override
  State<MemberDashboardScreen> createState() => _MemberDashboardScreenState();
}

class _MemberDashboardScreenState extends State<MemberDashboardScreen> {
  int _tab = 0;
  Map<String, dynamic>? _member;
  List<Map<String, dynamic>> _activeBookings = [];
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

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppBar(
        title: Text(_tab == 0 ? 'Browse stays' : 'My membership'),
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
          const PublicHotelSearchScreen(
            embeddedInMemberDashboard: true,
          ),
          _MembershipPanel(
            loading: _loading,
            error: _error,
            member: _member,
            activeBookings: _activeBookings,
            onRetry: _load,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.travel_explore_outlined),
            selectedIcon: Icon(Icons.travel_explore),
            label: 'Browse',
          ),
          NavigationDestination(
            icon: Icon(Icons.badge_outlined),
            selectedIcon: Icon(Icons.badge),
            label: 'Membership',
          ),
        ],
      ),
    );
  }
}

class _MembershipPanel extends StatelessWidget {
  const _MembershipPanel({
    required this.loading,
    required this.error,
    required this.member,
    required this.activeBookings,
    required this.onRetry,
  });

  final bool loading;
  final String? error;
  final Map<String, dynamic>? member;
  final List<Map<String, dynamic>> activeBookings;
  final Future<void> Function() onRetry;

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
    final discount = (m['member_discount_percent'] as num?)?.toDouble() ?? 0;
    final validUntil = _formatValidUntil((m['member_valid_until'] ?? '').toString());

    return RefreshIndicator(
      onRefresh: onRetry,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final qrSize = (constraints.maxWidth - 72).clamp(160.0, 240.0);
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Text(
                name.isEmpty ? 'Member' : name,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              if (username.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  '@$username',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
              const SizedBox(height: 16),
              _PointsWalletCard(member: m),
              const SizedBox(height: 20),
              _ActiveBookingsSection(bookings: activeBookings),
              const SizedBox(height: 20),
              if (discount > 0)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    () {
                      final every = ((m['member_discount_every_nth_booking']
                                  as num?)
                              ?.toDouble() ??
                          5)
                          .round();
                      final nextEligible =
                          m['next_booking_discount_eligible'] == true;
                      final bookings =
                          ((m['member_bookings_count'] as num?)?.toDouble() ?? 0)
                              .round();
                      return '${discount.toStringAsFixed(0)}% off every ${every}th booking '
                          '(not every stay). You have $bookings linked booking${bookings == 1 ? '' : 's'}; '
                          '${nextEligible ? 'your next booking gets the discount.' : 'your next booking is full price.'}';
                    }(),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                  ),
                ),
              const SizedBox(height: 20),
              Text(
                'Membership ID',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
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
              if (validUntil.isNotEmpty) ...[
                const SizedBox(height: 6),
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
                      fontWeight: FontWeight.w700,
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
                'Account details',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              if (email.isNotEmpty) _DetailRow(label: 'Email', value: email),
              if (phone.isNotEmpty) _DetailRow(label: 'Phone', value: phone),
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

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _ActiveBookingsSection extends StatelessWidget {
  const _ActiveBookingsSection({required this.bookings});

  final List<Map<String, dynamic>> bookings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Active',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'Your upcoming and in-progress stays linked to your membership.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 12),
        if (bookings.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Text(
              'No active bookings yet. Browse hotels and book while signed in as a member.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
            ),
          )
        else
          ...bookings.map((b) => _ActiveBookingCard(booking: b)),
      ],
    );
  }
}

class _ActiveBookingCard extends StatelessWidget {
  const _ActiveBookingCard({required this.booking});

  final Map<String, dynamic> booking;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hotel = (booking['hotel_name'] ?? '').toString();
    final room = (booking['room_number'] ?? '').toString();
    final roomName = (booking['room_display_name'] ?? '').toString();
    final checkIn = (booking['check_in_date'] ?? '').toString();
    final checkOut = (booking['check_out_date'] ?? '').toString();
    final payLabel = (booking['payment_method_label'] ?? 'Cash at hotel').toString();
    final amountPaid = (booking['amount_paid'] as num?)?.toDouble() ?? 0;
    final total = (booking['total_amount'] as num?)?.toDouble() ?? 0;
    final status = (booking['status'] ?? '').toString();
    final kind = (booking['kind'] ?? 'booking').toString();
    final ref = (booking['reference'] ?? '').toString();

    final roomLine = room.isNotEmpty
        ? 'Room $room${roomName.isNotEmpty ? ' · $roomName' : ''}'
        : (roomName.isNotEmpty ? roomName : 'Room TBA');

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
              'Paid: ₱${amountPaid.toStringAsFixed(2)} via $payLabel'
              '${total > 0 ? ' · Total ₱${total.toStringAsFixed(2)}' : ''}',
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
    final perCheckIn = (member['points_per_check_in'] as num?)?.toInt() ?? 1000;
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
            'Earn $perCheckIn points with every successful booking '
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
