import 'package:flutter/material.dart';

import '../admin_dashboard_models.dart';
import '../../admin_rooms.dart';

class CheckoutSection extends StatelessWidget {
  const CheckoutSection({
    super.key,
    required this.rooms,
  });

  final List<Map<String, dynamic>> rooms;

  List<Map<String, dynamic>> get _soonRooms {
    return rooms.where(AdminDashboardModels.isCheckoutSoon).toList();
  }

  @override
  Widget build(BuildContext context) {
    final grouped = AdminDashboardModels.groupByCategory(_soonRooms);
    final keys = grouped.keys.toList()..sort();
    final collectibles = AdminDashboardModels.collectiblesForRooms(_soonRooms);

    return ListView(
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
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      Text(
                        'Expected from checkouts within 30 minutes',
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
          'Approaching checkout (≤ 30 min)',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        if (keys.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No guests checking out in the next 30 minutes.'),
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
      ],
    );
  }
}

class _CheckoutRoomCard extends StatelessWidget {
  const _CheckoutRoomCard({required this.room});
  final Map<String, dynamic> room;

  @override
  Widget build(BuildContext context) {
    final mins = AdminDashboardModels.minutesUntilCheckout(room);
    final guest = (room['current_guest_name'] ?? '').toString();
    final co = AdminDashboardModels.checkoutDateTime(room);
    final coLabel = co != null
        ? '${co.hour > 12 ? co.hour - 12 : (co.hour == 0 ? 12 : co.hour)}:${co.minute.toString().padLeft(2, '0')} ${co.hour >= 12 ? 'PM' : 'AM'}'
        : '—';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          child: Text((room['room_number'] ?? '?').toString()),
        ),
        title: Text('Room ${room['room_number']}'),
        subtitle: Text(
          'Guest: ${guest.isEmpty ? '—' : guest}\n'
          'Checkout: $coLabel · Remaining: ${mins ?? '—'} mins',
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.receipt_long_outlined),
        onTap: () {
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => AdminRoomDetailScreen(
                roomId: (room['id'] ?? '').toString(),
              ),
            ),
          );
        },
      ),
    );
  }
}
