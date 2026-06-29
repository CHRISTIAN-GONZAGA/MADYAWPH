import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../dio_client.dart';
import '../admin_dashboard_models.dart';
import '../widgets/admin_room_navigation.dart';
import '../widgets/stay_receipt_dialog.dart';

class CheckoutSection extends StatefulWidget {
  const CheckoutSection({
    super.key,
    required this.rooms,
  });

  final List<Map<String, dynamic>> rooms;

  @override
  State<CheckoutSection> createState() => _CheckoutSectionState();
}

class _CheckoutSectionState extends State<CheckoutSection> {
  List<dynamic> _history = const [];
  bool _loadingHistory = true;
  String? _historyError;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loadingHistory = true;
      _historyError = null;
    });
    try {
      final res =
          await portalDio().get<Map<String, dynamic>>('/admin/guest-history');
      if (!mounted) return;
      setState(() {
        _history = (res.data?['data'] as List<dynamic>?) ?? const [];
        _loadingHistory = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _historyError = dioErrorMessage(e);
        _loadingHistory = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _historyError = '$e';
        _loadingHistory = false;
      });
    }
  }

  List<Map<String, dynamic>> get _soonRooms {
    return widget.rooms.where(AdminDashboardModels.isCheckoutSoon).toList();
  }

  Future<void> _openReceiptPdf(Map<String, dynamic> row) async {
    final id = (row['id'] ?? '').toString();
    if (id.isEmpty) return;
    if (!mounted) return;
    await showStayReceiptDialog(
      context,
      receipt: {
        'booking_id': id,
        'booking_reference': row['booking_reference'],
        'guest_name': row['guest_name'],
        'room_number': row['room_number'],
        'check_in_date': row['check_in_date'],
        'check_out_date': row['check_out_date'],
        'subtotal': row['total_amount'],
        'lines': const [],
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final grouped = AdminDashboardModels.groupByCategory(_soonRooms);
    final keys = grouped.keys.toList()..sort();
    final collectibles = AdminDashboardModels.collectiblesForRooms(_soonRooms);

    return RefreshIndicator(
      onRefresh: _loadHistory,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TOTAL COLLECTIBLES',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        Text(
                          '₱${collectibles.toStringAsFixed(2)}',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          'Due within 30 min or in 40-min grace after checkout',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.payments_outlined, size: 40),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Checkout queue',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          Text(
            'Guests stay up to ${AdminDashboardModels.checkoutGraceMinutes} minutes past checkout before auto check-out.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          if (keys.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No guests due for checkout right now.'),
              ),
            )
          else
            ...keys.map((cat) {
              final list = grouped[cat]!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      cat,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  ...list.map((r) => _CheckoutRoomCard(room: r)),
                ],
              );
            }),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  'After checkout — guest log',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              IconButton(
                onPressed: _loadHistory,
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh guest log',
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_loadingHistory)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_historyError != null)
            Card(
              child: ListTile(
                title: const Text('Could not load guest log'),
                subtitle: Text(_historyError!),
                trailing: TextButton(onPressed: _loadHistory, child: const Text('Retry')),
              ),
            )
          else if (_history.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('No completed stays yet.'),
              ),
            )
          else
            ..._history.take(30).map((raw) {
              final m = raw as Map<String, dynamic>;
              final guest = (m['guest_name'] ?? 'Guest').toString();
              final roomNo = (m['room_number'] ?? '').toString();
              final ref = (m['booking_reference'] ?? '').toString();
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(guest),
                  subtitle: Text(
                    [
                      if (roomNo.isNotEmpty) 'Room $roomNo',
                      if (ref.isNotEmpty) ref,
                      (m['checked_out_display'] ?? '').toString(),
                    ].where((s) => s.isNotEmpty).join(' · '),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    tooltip: 'Print receipt',
                    onPressed: () => _openReceiptPdf(m),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _CheckoutRoomCard extends StatelessWidget {
  const _CheckoutRoomCard({required this.room});
  final Map<String, dynamic> room;

  @override
  Widget build(BuildContext context) {
    final mins = AdminDashboardModels.minutesUntilCheckout(room);
    final inGrace = AdminDashboardModels.isCheckoutInGracePeriod(room);
    final guest = (room['current_guest_name'] ?? '').toString();
    final co = AdminDashboardModels.checkoutDateTime(room);
    final coLabel = co != null
        ? '${co.hour > 12 ? co.hour - 12 : (co.hour == 0 ? 12 : co.hour)}:${co.minute.toString().padLeft(2, '0')} ${co.hour >= 12 ? 'PM' : 'AM'}'
        : '—';
    final remainingLabel = mins == null
        ? '—'
        : inGrace
            ? '${mins.abs()} min past checkout (grace)'
            : mins < 0
                ? '${mins.abs()} min overdue'
                : '$mins min remaining';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: inGrace ? Colors.orange.shade50 : null,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: inGrace ? Colors.orange.shade700 : null,
          child: Text((room['room_number'] ?? '?').toString()),
        ),
        title: Text('Room ${room['room_number']}'),
        subtitle: Text(
          'Guest: ${guest.isEmpty ? '—' : guest}\n'
          'Checkout: $coLabel · $remainingLabel',
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          AdminRoomNavigation.openDetailById(
            AdminDashboardModels.roomIdOf(room),
            snackContext: context,
          );
        },
      ),
    );
  }
}
