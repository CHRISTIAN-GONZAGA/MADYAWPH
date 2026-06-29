import 'package:dio/dio.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';
import 'package:flutter/material.dart';

import '../../../dio_client.dart';
import '../admin_dashboard_models.dart';

/// Charges an amenity menu item to a checked-in room (updates booking bill / receipt).
Future<bool> showChargeAmenityToRoomDialog({
  required BuildContext context,
  required Map<String, dynamic> menuItem,
  required List<Map<String, dynamic>> rooms,
}) async {
  final itemId = (menuItem['id'] ?? menuItem['_id'] ?? '').toString();
  final name = (menuItem['name'] ?? 'Item').toString();
  final unitPrice = (menuItem['price'] as num?)?.toDouble() ?? 0.0;
  if (itemId.isEmpty || unitPrice <= 0) {
    showAppMessage(context, 'This product has no price set.');
    return false;
  }

  final checkedIn = AdminDashboardModels.sortRoomsByNumber(
    rooms.where((r) => AdminDashboardModels.statusOf(r) == 'checked_in').toList(),
  );
  if (checkedIn.isEmpty) {
    showAppMessage(context, 'No checked-in rooms to charge.');
    return false;
  }

  Map<String, dynamic>? selectedRoom = checkedIn.length == 1 ? checkedIn.first : null;
  var quantity = 1;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final lineTotal = unitPrice * quantity;
        return AlertDialog(
          title: const Text('Charge to room'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  name,
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                Text(
                  '₱${unitPrice.toStringAsFixed(2)} each',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<Map<String, dynamic>>(
                  value: selectedRoom,
                  decoration: const InputDecoration(
                    labelText: 'Room',
                    border: OutlineInputBorder(),
                  ),
                  items: checkedIn
                      .map(
                        (room) => DropdownMenuItem(
                          value: room,
                          child: Text(
                            'Room ${room['room_number']} — '
                            '${AdminDashboardModels.guestName(room)}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setLocal(() => selectedRoom = value),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Quantity'),
                    const Spacer(),
                    IconButton(
                      onPressed: quantity > 1
                          ? () => setLocal(() => quantity--)
                          : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text(
                      '$quantity',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    IconButton(
                      onPressed: () => setLocal(() => quantity++),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
                Text(
                  'Total: ₱${lineTotal.toStringAsFixed(2)}',
                  style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selectedRoom == null ? null : () => Navigator.pop(ctx, true),
              child: const Text('Charge'),
            ),
          ],
        );
      },
    ),
  );

  if (confirmed != true || selectedRoom == null || !context.mounted) {
    return false;
  }

  final room = selectedRoom!;
  final roomId = AdminDashboardModels.roomIdOf(room);
  final booking = room['latest_booking'] as Map?;
  final bookingId = (booking?['id'] ?? '').toString().trim();
  if (roomId.isEmpty || bookingId.isEmpty) {
    showAppMessage(context, 'No active booking for this room. Refresh and try again.');
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
    showAppMessage(context, 'Charged $name × $quantity to room ${room['room_number']}.',);
    return true;
  } on DioException catch (e) {
    if (!context.mounted) return false;
    showAppMessage(context, dioErrorMessage(e), isError: true);
    return false;
  }
}
