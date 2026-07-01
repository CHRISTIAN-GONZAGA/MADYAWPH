import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';

import '../../../dio_client.dart';
import '../admin_dashboard_models.dart';

/// Charges an amenity menu item to a checked-in room (updates booking bill / receipt).
Future<bool> showChargeAmenityToRoomDialog({
  required BuildContext context,
  required Map<String, dynamic> menuItem,
  required List<Map<String, dynamic>> rooms,
  List<Map<String, dynamic>> categories = const [],
}) async {
  final itemId = (menuItem['id'] ?? menuItem['_id'] ?? '').toString();
  final name = (menuItem['name'] ?? 'Item').toString();
  final unitPrice = (menuItem['price'] as num?)?.toDouble() ?? 0.0;
  if (itemId.isEmpty || unitPrice <= 0) {
    showAppMessage(context, 'This product has no price set.');
    return false;
  }

  if (!context.mounted) return false;

  final chargeable = await _loadChargeableRooms(context, rooms);
  if (!context.mounted) return false;

  if (chargeable.isEmpty) {
    showAppMessage(
      context,
      'No in-house guests right now. Check a guest in from the Bookings tab, then try again.',
    );
    return false;
  }

  final sorted = AdminDashboardModels.sortRoomsByNumber(chargeable);

  final picked = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (ctx) => _InHouseRoomPickerDialog(
      productName: name,
      unitPrice: unitPrice,
      rooms: sorted,
    ),
  );
  if (picked == null || !context.mounted) return false;

  final quantity = (picked['_quantity'] as int?) ?? 1;
  final room = Map<String, dynamic>.from(picked)..remove('_quantity');

  final roomId = AdminDashboardModels.roomIdOf(room);
  final booking = room['latest_booking'] as Map?;
  final bookingId = (booking?['id'] ?? booking?['_id'] ?? '').toString().trim();
  final roomNo = (room['room_number'] ?? '—').toString();
  final guest = AdminDashboardModels.guestName(room);
  final lineTotal = unitPrice * quantity;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Confirm charge'),
      content: Text(
        'Add $name × $quantity to room $roomNo'
        '${guest != '—' ? ' ($guest)' : ''}?\n\n'
        'Total: ₱${lineTotal.toStringAsFixed(2)}',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Charge to room'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  if (roomId.isEmpty || bookingId.isEmpty) {
    showAppMessage(
      context,
      'No active booking for this room. Pull to refresh the dashboard and try again.',
    );
    return false;
  }

  try {
    await portalDio().post('/billing/charges', data: {
      'booking_id': bookingId,
      'room_id': roomId,
      'type': 'amenity',
      'label': 'Amenity: $name',
      'amount': unitPrice,
      'quantity': quantity,
      'is_manual': false,
    });
    if (!context.mounted) return false;
    showAppMessage(
      context,
      'Charged $name × $quantity to room $roomNo.',
    );
    return true;
  } on DioException catch (e) {
    if (!context.mounted) return false;
    showAppMessage(context, dioErrorMessage(e), isError: true);
    return false;
  }
}

Future<List<Map<String, dynamic>>> _loadChargeableRooms(
  BuildContext context,
  List<Map<String, dynamic>> dashboardRooms,
) async {
  final merged = <String, Map<String, dynamic>>{};

  void addRooms(List<Map<String, dynamic>> list) {
    for (final room in AdminDashboardModels.amenityChargeableRooms(list)) {
      final id = AdminDashboardModels.roomIdOf(room);
      if (id.isNotEmpty) {
        merged[id] = room;
      }
    }
  }

  addRooms(dashboardRooms);

  try {
    final res = await portalDioWithLongTimeout()
        .get<Map<String, dynamic>>('/admin/amenity-chargeable-rooms');
    addRooms(
      AdminDashboardModels.parseRoomMaps(res.data?['rooms'] as List<dynamic>?),
    );
  } on DioException catch (e) {
    if (merged.isEmpty && context.mounted) {
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  return merged.values.toList();
}

class _InHouseRoomPickerDialog extends StatefulWidget {
  const _InHouseRoomPickerDialog({
    required this.productName,
    required this.unitPrice,
    required this.rooms,
  });

  final String productName;
  final double unitPrice;
  final List<Map<String, dynamic>> rooms;

  @override
  State<_InHouseRoomPickerDialog> createState() =>
      _InHouseRoomPickerDialogState();
}

class _InHouseRoomPickerDialogState extends State<_InHouseRoomPickerDialog> {
  var _quantity = 1;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Charge to room'),
      content: SizedBox(
        width: double.maxFinite,
        height: (widget.rooms.length * 72.0 + 140).clamp(180, 420),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.productName} · ₱${widget.unitPrice.toStringAsFixed(2)} each',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'In-house guests (${widget.rooms.length})',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: widget.rooms.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final room = widget.rooms[i];
                  final roomNo = (room['room_number'] ?? '—').toString();
                  final guest = AdminDashboardModels.guestName(room);
                  final category = AdminDashboardModels.categoryLabel(room);

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: Colors.green.shade600,
                      child: Text(
                        roomNo,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    title: Text('Room $roomNo'),
                    subtitle: Text(
                      [
                        if (guest != '—') guest,
                        if (category.isNotEmpty && category != 'Uncategorized')
                          category,
                      ].join(' · '),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(
                      context,
                      {...room, '_quantity': _quantity},
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Quantity'),
                const Spacer(),
                IconButton(
                  onPressed:
                      _quantity > 1 ? () => setState(() => _quantity--) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text(
                  '$_quantity',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                IconButton(
                  onPressed: () => setState(() => _quantity++),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            Text(
              'Line total: ₱${(widget.unitPrice * _quantity).toStringAsFixed(2)}',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
