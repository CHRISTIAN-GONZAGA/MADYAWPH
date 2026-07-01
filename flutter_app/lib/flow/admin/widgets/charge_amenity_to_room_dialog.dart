import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final dialogCtx = resolveNoticeContext(context);
  if (dialogCtx == null) {
    return false;
  }

  final itemId = (menuItem['id'] ?? menuItem['_id'] ?? '').toString();
  final name = (menuItem['name'] ?? 'Item').toString();
  final unitPrice = (menuItem['price'] as num?)?.toDouble() ?? 0.0;

  if (itemId.isEmpty || unitPrice <= 0) {
    await _showChargeDiagnosticDialog(
      dialogCtx,
      title: 'Cannot charge product',
      isError: true,
      summary: 'This product has no price set or is missing an ID.',
      details: 'Product: $name\n'
          'ID: ${itemId.isEmpty ? '(empty)' : itemId}\n'
          'Price: $unitPrice',
    );
    return false;
  }

  _LoadingHandle? loading;
  try {
    loading = _showLoadingDialog(dialogCtx, 'Loading in-house rooms…');

    final loadResult = await _loadChargeableRooms(rooms);
    loading.close();
    loading = null;

    if (!dialogCtx.mounted) return false;

    if (loadResult.rooms.isEmpty) {
      await _showChargeDiagnosticDialog(
        dialogCtx,
        title: 'No rooms to charge',
        isError: true,
        summary: loadResult.apiError != null
            ? 'Could not load in-house rooms from the server.'
            : 'No checked-in guests with an active booking were found.',
        details: loadResult.diagnosticReport(),
      );
      return false;
    }

    final sorted = AdminDashboardModels.sortRoomsByNumber(loadResult.rooms);

    final picked = await showDialog<Map<String, dynamic>>(
      context: dialogCtx,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (ctx) => _InHouseRoomPickerDialog(
        productName: name,
        unitPrice: unitPrice,
        rooms: sorted,
      ),
    );
    if (picked == null || !dialogCtx.mounted) return false;

    final quantity = (picked['_quantity'] as int?) ?? 1;
    final room = Map<String, dynamic>.from(picked)..remove('_quantity');

    final roomId = AdminDashboardModels.roomIdOf(room);
    final booking = room['latest_booking'] as Map?;
    final bookingId =
        (booking?['id'] ?? booking?['_id'] ?? '').toString().trim();
    final roomNo = (room['room_number'] ?? '—').toString();
    final guest = AdminDashboardModels.guestName(room);
    final lineTotal = unitPrice * quantity;

    final confirmed = await showDialog<bool>(
      context: dialogCtx,
      useRootNavigator: true,
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
    if (confirmed != true || !dialogCtx.mounted) return false;

    if (roomId.isEmpty || bookingId.isEmpty) {
      await _showChargeDiagnosticDialog(
        dialogCtx,
        title: 'Missing booking',
        isError: true,
        summary: 'This room has no active booking ID on record.',
        details: 'Room: $roomNo\n'
            'Room ID: ${roomId.isEmpty ? '(empty)' : roomId}\n'
            'Booking ID: ${bookingId.isEmpty ? '(empty)' : bookingId}\n\n'
            'Pull to refresh the dashboard, then try again.',
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
      if (!dialogCtx.mounted) return false;
      await showAppMessage(
        dialogCtx,
        'Charged $name × $quantity to room $roomNo.',
      );
      return true;
    } on DioException catch (e) {
      if (!dialogCtx.mounted) return false;
      await _showChargeDiagnosticDialog(
        dialogCtx,
        title: 'Charge failed',
        isError: true,
        summary: dioErrorMessage(e),
        details: _formatDioDiagnostics(e, endpoint: 'POST /billing/charges'),
      );
      return false;
    }
  } catch (e, st) {
    loading?.close();
    if (!dialogCtx.mounted) return false;
    await _showChargeDiagnosticDialog(
      dialogCtx,
      title: 'Charge to room error',
      isError: true,
      summary: e.toString(),
      details: '$st',
    );
    return false;
  } finally {
    loading?.close();
  }
}

class _ChargeableRoomsLoadResult {
  const _ChargeableRoomsLoadResult({
    required this.rooms,
    this.apiError,
    this.apiStatusCode,
    this.apiRawCount = 0,
    this.dashboardTotal = 0,
    this.dashboardCheckedIn = 0,
    this.dashboardWithBooking = 0,
    this.unexpectedError,
  });

  final List<Map<String, dynamic>> rooms;
  final String? apiError;
  final int? apiStatusCode;
  final int apiRawCount;
  final int dashboardTotal;
  final int dashboardCheckedIn;
  final int dashboardWithBooking;
  final String? unexpectedError;

  String diagnosticReport() {
    final buf = StringBuffer()
      ..writeln('Product charge room lookup')
      ..writeln('—' * 32)
      ..writeln('Dashboard cache:')
      ..writeln('  • Total rooms: $dashboardTotal')
      ..writeln('  • Checked in: $dashboardCheckedIn')
      ..writeln('  • With booking ID: $dashboardWithBooking')
      ..writeln()
      ..writeln('API GET /admin/amenity-chargeable-rooms:');

    if (unexpectedError != null) {
      buf.writeln('  • Unexpected: $unexpectedError');
    } else if (apiError != null) {
      buf.writeln('  • Failed: $apiError');
      if (apiStatusCode != null) {
        buf.writeln('  • HTTP status: $apiStatusCode');
      }
    } else {
      buf.writeln('  • OK — raw rooms returned: $apiRawCount');
    }

    buf
      ..writeln()
      ..writeln('Chargeable after merge: ${rooms.length}');

    if (rooms.isEmpty) {
      buf
        ..writeln()
        ..writeln('Tip: check the guest in from the Bookings tab first,')
        ..writeln('then pull to refresh and try again.');
    }

    return buf.toString();
  }
}

Future<_ChargeableRoomsLoadResult> _loadChargeableRooms(
  List<Map<String, dynamic>> dashboardRooms,
) async {
  final merged = <String, Map<String, dynamic>>{};
  var dashboardCheckedIn = 0;
  var dashboardWithBooking = 0;

  for (final room in dashboardRooms) {
    if (AdminDashboardModels.statusOf(room) == 'checked_in') {
      dashboardCheckedIn++;
    }
    if (AdminDashboardModels.isAmenityChargeable(room)) {
      dashboardWithBooking++;
    }
  }

  void addFromDashboard(List<Map<String, dynamic>> list) {
    for (final room in AdminDashboardModels.amenityChargeableRooms(list)) {
      final id = AdminDashboardModels.roomIdOf(room);
      if (id.isNotEmpty) merged[id] = room;
    }
  }

  addFromDashboard(dashboardRooms);

  String? apiError;
  int? apiStatusCode;
  var apiRawCount = 0;
  String? unexpectedError;

  try {
    final res = await portalDioWithLongTimeout()
        .get<Map<String, dynamic>>('/admin/amenity-chargeable-rooms');
    apiStatusCode = res.statusCode;
    final rawList =
        AdminDashboardModels.parseRoomMaps(res.data?['rooms'] as List<dynamic>?);
    apiRawCount = rawList.length;

    for (final room in rawList) {
      final id = AdminDashboardModels.roomIdOf(room);
      if (id.isEmpty) continue;
      final booking = room['latest_booking'];
      if (booking is! Map) continue;
      final bookingId =
          (booking['id'] ?? booking['_id'] ?? '').toString().trim();
      if (bookingId.isEmpty) continue;
      merged[id] = {
        ...room,
        'status': 'checked_in',
        'id': id,
      };
    }
  } on DioException catch (e) {
    apiError = dioErrorMessage(e);
    apiStatusCode = e.response?.statusCode;
    final extra = _formatDioDiagnostics(
      e,
      endpoint: 'GET /admin/amenity-chargeable-rooms',
    );
    apiError = '$apiError\n\n$extra';
  } catch (e) {
    unexpectedError = e.toString();
  }

  return _ChargeableRoomsLoadResult(
    rooms: merged.values.toList(),
    apiError: apiError,
    apiStatusCode: apiStatusCode,
    apiRawCount: apiRawCount,
    dashboardTotal: dashboardRooms.length,
    dashboardCheckedIn: dashboardCheckedIn,
    dashboardWithBooking: dashboardWithBooking,
    unexpectedError: unexpectedError,
  );
}

String _formatDioDiagnostics(DioException e, {required String endpoint}) {
  final buf = StringBuffer()
    ..writeln('Endpoint: $endpoint')
    ..writeln('Type: ${e.type.name}');

  final code = e.response?.statusCode;
  if (code != null) {
    buf.writeln('HTTP: $code');
  }

  final data = e.response?.data;
  if (data != null) {
    try {
      final encoded = data is String ? data : jsonEncode(data);
      final trimmed =
          encoded.length > 800 ? '${encoded.substring(0, 800)}…' : encoded;
      buf.writeln('Response: $trimmed');
    } catch (_) {
      buf.writeln('Response: $data');
    }
  } else if (e.message != null) {
    buf.writeln('Message: ${e.message}');
  }

  return buf.toString();
}

Future<void> _showChargeDiagnosticDialog(
  BuildContext context, {
  required String title,
  required String summary,
  required String details,
  bool isError = false,
}) {
  return showDialog<void>(
    context: context,
    useRootNavigator: true,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.info_outline,
              color: isError ? scheme.error : scheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(title)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  summary,
                  style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Diagnostics',
                  style: Theme.of(ctx).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    details,
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          height: 1.35,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: '$title\n\n$summary\n\n$details'));
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('Copied diagnostics')),
              );
            },
            child: const Text('Copy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      );
    },
  );
}

class _LoadingHandle {
  _LoadingHandle(this._close);
  final VoidCallback _close;
  void close() => _close();
}

_LoadingHandle _showLoadingDialog(BuildContext context, String message) {
  showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    ),
  );
  return _LoadingHandle(() {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  });
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
    final listHeight =
        (widget.rooms.length * 72.0 + 140).clamp(200.0, 420.0).toDouble();

    return AlertDialog(
      title: const Text('Charge to room'),
      content: SizedBox(
        width: double.maxFinite,
        height: listHeight,
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
              child: widget.rooms.isEmpty
                  ? const Center(child: Text('No rooms loaded.'))
                  : ListView.separated(
                      itemCount: widget.rooms.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final room = widget.rooms[i];
                        final roomNo =
                            (room['room_number'] ?? '—').toString();
                        final guest = AdminDashboardModels.guestName(room);
                        final category =
                            AdminDashboardModels.categoryLabel(room);

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
                              if (category.isNotEmpty &&
                                  category != 'Uncategorized')
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
                  onPressed: _quantity > 1
                      ? () => setState(() => _quantity--)
                      : null,
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
