import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../dio_client.dart';
import '../../utils/money_format.dart';
import '../../widgets/app_state_views.dart';
import '../../widgets/room_status_label.dart';
import 'admin_dashboard_models.dart';
import 'widgets/admin_opaque_scaffold.dart';
import 'widgets/stay_receipt_dialog.dart';

class AdminRoomDetailScreen extends StatefulWidget {
  const AdminRoomDetailScreen({
    super.key,
    required this.roomId,
    this.onClose,
    this.embedded = false,
    this.panelBodyOnly = false,
    this.initialRoomSnapshot,
  });

  final String roomId;
  final VoidCallback? onClose;
  /// Inside hotel-totals slide-up panel or modal sheet.
  final bool embedded;
  /// Renders only the scrollable body; parent supplies [Scaffold] + app bar.
  final bool panelBodyOnly;
  /// Dashboard list row shown immediately while room detail API loads.
  final Map<String, dynamic>? initialRoomSnapshot;

  @override
  State<AdminRoomDetailScreen> createState() => _AdminRoomDetailScreenState();
}

class _AdminRoomDetailScreenState extends State<AdminRoomDetailScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;
  bool _busy = false;
  bool _changingStatus = false;
  bool _checkingOut = false;
  bool _updatingPayment = false;
  bool _issuingRefund = false;
  late final String _roomId;

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static Map<String, dynamic>? _normalizePayload(dynamic raw) {
    if (raw is! Map) return null;
    final map = raw is Map<String, dynamic> ? raw : Map<String, dynamic>.from(raw);
    final nested = map['data'];
    if (nested is Map) {
      final inner =
          nested is Map<String, dynamic> ? nested : Map<String, dynamic>.from(nested);
      if (inner.containsKey('room')) return inner;
    }
    return map.containsKey('room') || map.containsKey('active_booking') ? map : map;
  }

  static Map<String, dynamic> _mergeRoomMaps(
    Map<String, dynamic>? prior,
    Map<String, dynamic> fresh,
  ) {
    final merged = <String, dynamic>{...?prior, ...fresh};
    if (prior != null) {
      final priorStatus = AdminDashboardModels.statusOf(prior);
      final freshStatus = AdminDashboardModels.statusOf(fresh);
      if (freshStatus.isEmpty && priorStatus.isNotEmpty) {
        merged['status'] = prior['status'];
      }
      final priorGuest =
          (prior['current_guest_name'] ?? '').toString().trim();
      final freshGuest =
          (fresh['current_guest_name'] ?? '').toString().trim();
      if (freshGuest.isEmpty && priorGuest.isNotEmpty) {
        merged['current_guest_name'] = prior['current_guest_name'];
      }
    }
    return merged;
  }

  void _applyRoomSnapshot(Map<String, dynamic> snap) {
    final priorRoom = _asMap(_data?['room']);
    final nextRoom = Map<String, dynamic>.from(snap);
    _data = {
      ...?_data,
      'room': _mergeRoomMaps(priorRoom, nextRoom),
    };
    _applyActiveBookingFallback();
  }

  void _applyActiveBookingFallback() {
    if (_asMap(_data?['active_booking']) != null) return;
    final snap = widget.initialRoomSnapshot;
    final fromSnap = _asMap(snap?['latest_booking']);
    if (fromSnap != null) {
      _data = {...?_data, 'active_booking': fromSnap};
      return;
    }
    final room = _asMap(_data?['room']);
    final fromRoom = _asMap(room?['latest_booking']);
    if (fromRoom != null) {
      _data = {...?_data, 'active_booking': fromRoom};
    }
  }

  List<dynamic> _chargesList() {
    final raw = _data?['booking_charges'];
    if (raw is List) return raw;
    return const [];
  }

  @override
  void initState() {
    super.initState();
    _roomId = AdminDashboardModels.normalizeRoomIdString(widget.roomId);
    final snap = widget.initialRoomSnapshot;
    if (snap != null && snap.isNotEmpty) {
      _applyRoomSnapshot(snap);
    }
    _load();
  }

  Future<void> _load() async {
    if (_roomId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Invalid room ID. Go back and try again.';
      });
      return;
    }
    setState(() {
      if (_data == null) _loading = true;
      _error = null;
    });
    try {
      final res = await portalDio()
          .get<Map<String, dynamic>>('/admin/rooms/$_roomId');
      if (!mounted) return;
      final payload = _normalizePayload(res.data);
      if (!mounted) return;
      setState(() {
        _loading = false;
        final room = payload != null ? _asMap(payload['room']) : null;
        if (payload != null && room != null) {
          final priorRoom = _asMap(_data?['room']);
          final priorBooking = _data?['active_booking'];
          _data = {
            ...?_data,
            'room': _mergeRoomMaps(priorRoom, room),
            'active_booking':
                payload['active_booking'] ?? priorBooking,
            'booking_charges':
                payload['booking_charges'] ?? _data?['booking_charges'],
            'booking_charges_total': payload['booking_charges_total'] ??
                _data?['booking_charges_total'],
            'refund_total': payload['refund_total'] ?? _data?['refund_total'],
            'can_edit_guest_stay': payload['can_edit_guest_stay'] ??
                _data?['can_edit_guest_stay'],
            'management_blocked_reason': payload['management_blocked_reason'] ??
                _data?['management_blocked_reason'],
            'pending_reservation': payload['pending_reservation'] ??
                _data?['pending_reservation'],
          };
          if (_canEditGuestStay) {
            _data!.remove('management_blocked_reason');
          }
          _applyActiveBookingFallback();
          _error = null;
        } else if (_data == null) {
          _error = payload == null || payload.isEmpty
              ? 'No room data returned from the server.'
              : 'Room data is unavailable. Pull to refresh.';
        } else {
          _error = payload == null || payload.isEmpty
              ? 'Could not refresh room details. Showing last loaded info.'
              : 'Room data is unavailable. Pull to refresh.';
        }
      });
    } on DioException catch (e) {
      setState(() {
        _error = dioErrorMessage(e);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _addFee() async {
    final booking = _asMap(_data?['active_booking']);
    final room = _asMap(_data?['room']);
    final bookingId = booking?['id']?.toString() ?? '';
    final roomId = room?['id']?.toString() ?? _roomId;
    if (bookingId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No active booking for this room.')));
      return;
    }

    final reasonCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add fee'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                  labelText: 'Reason (custom)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              decoration: const InputDecoration(
                  labelText: 'Amount', border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop({
              'label': reasonCtrl.text.trim(),
              'amount': double.tryParse(amountCtrl.text.trim()) ?? 0,
            }),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    reasonCtrl.dispose();
    amountCtrl.dispose();

    if (payload == null) return;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final label = (payload['label'] ?? '').toString();
    final amount = (payload['amount'] as num?)?.toDouble() ?? 0;
    if (label.isEmpty || amount <= 0) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Enter a reason and amount > 0.')),
      );
      return;
    }

    if (_busy) return;
    setState(() => _busy = true);
    try {
      await portalDio().post('/billing/charges', data: {
        'booking_id': bookingId,
        'room_id': roomId,
        'type': 'manual',
        'label': label,
        'amount': amount,
        'quantity': 1,
        'is_manual': true,
      });
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Fee added.')),
      );
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(dioErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkoutGuest() async {
    final room = _asMap(_data?['room']);
    final booking = _asMap(_data?['active_booking']);
    final roomId = (room?['id'] ?? _roomId).toString();
    final guest = (room?['current_guest_name'] ?? booking?['guest_name'] ?? 'Guest').toString();
    final paid = (booking?['payment_status'] ?? '').toString() == 'paid';

    if (!paid) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mark payment as paid before checking out this guest.'),
        ),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Check out guest'),
        content: Text(
          'Check out $guest from this room?\n\n'
          '• Guest details will be cleared from room management\n'
          '• Room will move to maintenance for cleaning\n'
          '• Stay will appear in Guest list history\n'
          '• Chat history for this room will be cleared',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Check out'),
          ),
        ],
      ),
    );
    if (ok != true || _checkingOut) return;

    setState(() => _checkingOut = true);
    try {
      final res = await portalDio().post<Map<String, dynamic>>(
        '/rooms/$roomId/checkout',
      );
      if (!mounted) return;
      final msg = (res.data?['message'] ?? 'Guest checked out.').toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(dioErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _checkingOut = false);
    }
  }

  Future<void> _changeStatus() async {
    final room = _asMap(_data?['room']);
    final booking = _asMap(_data?['active_booking']);
    final roomId = (room?['id'] ?? _roomId).toString();
    final current = (room?['status'] ?? 'available').toString();
    final paid = (booking?['payment_status'] ?? '').toString() == 'paid';
    final hasStay = current == 'checked_in' ||
        current == 'booked' ||
        (room?['current_guest_name'] ?? '').toString().trim().isNotEmpty;
    final showCheckedOut = hasStay && paid && _canEditGuestStay;
    String status = current;
    final statusItems = _canEditGuestStay
        ? [
            const DropdownMenuItem(value: 'available', child: Text('available')),
            const DropdownMenuItem(value: 'booked', child: Text('booked')),
            const DropdownMenuItem(value: 'checked_in', child: Text('Occupied')),
            if (showCheckedOut)
              const DropdownMenuItem(value: 'checked_out', child: Text('checked_out')),
            const DropdownMenuItem(value: 'maintenance', child: Text('maintenance')),
            const DropdownMenuItem(value: 'reserved', child: Text('reserved')),
          ]
        : const [
            DropdownMenuItem(value: 'available', child: Text('available')),
            DropdownMenuItem(value: 'maintenance', child: Text('maintenance')),
          ];
    final chosen = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_canEditGuestStay ? 'Change room status' : 'Housekeeping status'),
        content: DropdownButtonFormField<String>(
          initialValue: _canEditGuestStay
              ? current
              : (current == 'maintenance' ? 'maintenance' : 'available'),
          items: statusItems,
          onChanged: (v) => status = v ?? current,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(status),
              child: const Text('Update')),
        ],
      ),
    );
    if (chosen == null) return;
    if (chosen == 'checked_out' && hasStay && !paid) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mark payment as paid before checking out this guest.'),
        ),
      );
      return;
    }
    if (_changingStatus) return;
    setState(() => _changingStatus = true);
    try {
      final Response<Map<String, dynamic>> res;
      if (chosen == 'checked_out') {
        res = await portalDio().post<Map<String, dynamic>>(
          '/rooms/$roomId/checkout',
        );
      } else {
        res = await portalDio().put<Map<String, dynamic>>(
          '/rooms/$roomId/status',
          data: {'status': chosen},
        );
      }
      if (!mounted) return;
      final msg = (res.data?['message'] ?? 'Status updated.').toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      if (chosen == 'checked_out') {
        final receipt = res.data?['receipt'] as Map<String, dynamic>?;
        if (context.mounted) {
          await showStayReceiptDialog(context, receipt: receipt);
        }
      }
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(dioErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _changingStatus = false);
    }
  }

  Future<void> _showNoRoomsAlert() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.meeting_room_outlined, color: Colors.orange.shade800, size: 40),
        title: const Text('No rooms available'),
        content: const Text(
          'All rooms are currently occupied, booked, or under maintenance. '
          'Try again later or mark a room as available before transferring.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _transferRoom() async {
    final booking = _asMap(_data?['active_booking']);
    final room = _asMap(_data?['room']);
    final bookingId = (booking?['id'] ?? '').toString();
    final fromRoomId = (room?['id'] ?? _roomId).toString();
    if (bookingId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No active booking to transfer.')));
      return;
    }
    try {
      final res = await portalDio().get<List<dynamic>>('/rooms/available');
      final available = res.data ?? const [];
      if (!mounted) return;
      if (available.isEmpty) {
        await _showNoRoomsAlert();
        return;
      }
      String toRoomId =
          ((available.first as Map<String, dynamic>)['id'] ?? '').toString();
      if (!mounted) return;
      final payload = await showDialog<Map<String, String>>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: const Text('Transfer room'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: toRoomId,
                  items: available.map((r) {
                    final m = r as Map<String, dynamic>;
                    final id = (m['id'] ?? m['_id'] ?? '').toString();
                    final no = (m['room_number'] ?? '').toString();
                    return DropdownMenuItem(value: id, child: Text('Room $no'));
                  }).toList(),
                  onChanged: (v) => setLocal(() => toRoomId = v ?? toRoomId),
                  decoration: const InputDecoration(labelText: 'Transfer to'),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel')),
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).pop({'to_room_id': toRoomId}),
                child: const Text('Transfer'),
              ),
            ],
          ),
        ),
      );
      if (payload == null) return;
      final toId = payload['to_room_id'] ?? '';
      Map<String, dynamic>? preview;
      try {
        final previewRes = await portalDio().get<Map<String, dynamic>>(
          '/room-transfers/preview',
          queryParameters: {
            'booking_id': bookingId,
            'from_room_id': fromRoomId,
            'to_room_id': toId,
          },
        );
        preview = previewRes.data;
      } on DioException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(dioErrorMessage(e))));
        return;
      }
      var approveAdjustment = false;
      final adjustment = (preview?['price_adjustment'] as num?)?.toDouble() ?? 0;
      if (preview?['requires_approval'] == true && adjustment.abs() > 0) {
        if (!mounted) return;
        final approved = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: Icon(
              adjustment > 0 ? Icons.trending_up : Icons.trending_down,
              color: adjustment > 0 ? Colors.orange.shade800 : Colors.green.shade700,
            ),
            title: const Text('Room rate change'),
            content: Text(
              'Transferring from Room ${preview?['from_room_number']} '
              '(${formatPeso((preview?['from_nightly_rate'] as num?) ?? 0)}/night) '
              'to Room ${preview?['to_room_number']} '
              '(${formatPeso((preview?['to_nightly_rate'] as num?) ?? 0)}/night).\n\n'
              'Bill ${adjustment > 0 ? 'increases' : 'decreases'} by ${formatPeso(adjustment.abs())}.\n'
              'New total: ${formatPeso((preview?['new_total'] as num?) ?? 0)}.\n\n'
              'Approve this price adjustment?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Approve & transfer'),
              ),
            ],
          ),
        );
        if (approved != true) return;
        approveAdjustment = true;
      }
      await portalDio().post('/room-transfers', data: {
        'booking_id': bookingId,
        'from_room_id': fromRoomId,
        'to_room_id': toId,
        'reason': 'Guest requested transfer',
        if (approveAdjustment) 'approve_price_adjustment': true,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Room transferred successfully.')));
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(dioErrorMessage(e))));
    }
  }

  Future<void> _updatePaymentStatus() async {
    final booking = _asMap(_data?['active_booking']);
    final bookingId = (booking?['id'] ?? '').toString();
    if (bookingId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active booking for this room.')),
      );
      return;
    }
    Map<String, dynamic>? billSummary;
    try {
      final billRes = await portalDio().get<Map<String, dynamic>>(
        '/admin/bookings/$bookingId/bill-summary',
      );
      billSummary = billRes.data;
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(dioErrorMessage(e))));
      return;
    }
    final current = (booking?['payment_status'] ?? 'unpaid').toString();
    final currentMethodRaw = (booking?['payment_method'] ?? '').toString().trim();
    String method = (() {
      final lower = currentMethodRaw.toLowerCase();
      if (lower == 'gcash' || lower == 'g-cash') return 'GCash';
      if (lower == 'paymaya' || lower == 'maya' || lower == 'pay maya') {
        return 'PayMaya';
      }
      if (lower == 'credit card' || lower == 'credit_card' || lower == 'card') {
        return 'Credit Card';
      }
      return 'Cash';
    })();
    String next = current;
    final totalDue =
        (billSummary?['total_due'] as num?)?.toDouble() ??
        (booking?['total_amount'] as num?)?.toDouble() ??
        0;
    final lines = (billSummary?['lines'] as List?) ?? const [];
    final refCtrl =
        TextEditingController(text: (booking?['payment_reference'] ?? '').toString());
    final tenderCtrl = TextEditingController(
      text: totalDue > 0 ? totalDue.toStringAsFixed(0) : '',
    );
    if (!mounted) return;
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          final tendered = double.tryParse(tenderCtrl.text.trim()) ?? 0;
          final change = next == 'paid' && tendered > 0
              ? (tendered - totalDue).clamp(0, double.infinity)
              : 0.0;
          return AlertDialog(
            title: const Text('Record payment'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Total bill: ${formatPeso(totalDue)}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  if (lines.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ...lines.whereType<Map>().map(
                      (line) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Expanded(child: Text('${line['label']}')),
                            Text(formatBillLineAmount(line)),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const Divider(),
                  DropdownButtonFormField<String>(
                    initialValue: current,
                    items: const [
                      DropdownMenuItem(value: 'unpaid', child: Text('Unpaid')),
                      DropdownMenuItem(value: 'paid', child: Text('Paid')),
                    ],
                    onChanged: (v) => setLocal(() => next = v ?? current),
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: tenderCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Amount given by guest',
                      border: OutlineInputBorder(),
                      prefixText: '₱ ',
                    ),
                    onChanged: (_) => setLocal(() {}),
                  ),
                  if (next == 'paid' && tendered > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Change: ${formatPeso(change)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: refCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Payment reference (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: method,
                    items: const [
                      DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                      DropdownMenuItem(value: 'GCash', child: Text('GCash')),
                      DropdownMenuItem(value: 'PayMaya', child: Text('PayMaya')),
                      DropdownMenuItem(
                        value: 'Credit Card',
                        child: Text('Credit Card'),
                      ),
                    ],
                    onChanged: (v) => setLocal(() => method = v ?? method),
                    decoration: const InputDecoration(
                      labelText: 'Payment method',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop({
                  'payment_status': next,
                  'payment_reference': refCtrl.text.trim(),
                  'payment_method': method,
                  'amount_tendered': tendered > 0 ? tendered : null,
                }),
                child: const Text('Pay'),
              ),
            ],
          );
        },
      ),
    );
    refCtrl.dispose();
    tenderCtrl.dispose();
    if (payload == null || _updatingPayment) return;
    setState(() => _updatingPayment = true);
    try {
      final res = await portalDio().post<Map<String, dynamic>>(
        '/admin/bookings/$bookingId/payment-status',
        data: payload,
      );
      if (!mounted) return;
      final changeDue = (res.data?['change_due'] as num?)?.toDouble();
      final msg = changeDue != null && changeDue > 0
          ? 'Payment recorded. Change due: ${formatPeso(changeDue)}'
          : 'Payment recorded.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(dioErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _updatingPayment = false);
    }
  }

  Future<void> _issueRefund() async {
    final booking = _asMap(_data?['active_booking']);
    final bookingId = (booking?['id'] ?? '').toString();
    if (bookingId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active booking for this room.')),
      );
      return;
    }
    final amountCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Issue refund'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountCtrl,
              decoration: const InputDecoration(
                labelText: 'Amount (optional, leave blank for max refundable)',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Reason',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop({
              'amount': double.tryParse(amountCtrl.text.trim()),
              'reason': reasonCtrl.text.trim(),
            }),
            child: const Text('Refund'),
          ),
        ],
      ),
    );
    if (payload == null || _issuingRefund) return;
    setState(() => _issuingRefund = true);
    try {
      await portalDio().post('/admin/bookings/$bookingId/refund', data: payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Refund recorded and reports updated.')),
      );
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(dioErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _issuingRefund = false);
    }
  }

  void _close() {
    if (widget.onClose != null) {
      widget.onClose!();
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.panelBodyOnly) {
      return ColoredBox(
        color: const Color(0xFFF5F3EF),
        child: _buildSafeBody(),
      );
    }

    final body = SizedBox.expand(child: _buildSafeBody());

    if (widget.embedded) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F3EF),
        appBar: AppBar(
          title: const Text('Room details'),
          leading: BackButton(onPressed: _close),
          actions: [
            IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          ],
        ),
        body: body,
      );
    }

    return PopScope(
      canPop: widget.onClose == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && widget.onClose != null) {
          widget.onClose!();
        }
      },
      child: AdminOpaqueScaffold(
      backgroundColor: const Color(0xFFF5F3EF),
      appBar: AppBar(
        title: const Text('Room details'),
        leading: BackButton(onPressed: _close),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: SizedBox.expand(child: _buildSafeBody()),
    ),
    );
  }

  Widget _buildSafeBody() {
    try {
      return _buildBody();
    } catch (e, st) {
      debugPrint('AdminRoomDetailScreen build error: $e\n$st');
      return AppErrorView(
        message: 'Could not display room details ($e).',
        onRetry: _load,
      );
    }
  }

  bool get _canEditGuestStay {
    if (_data?['can_edit_guest_stay'] == true) return true;
    final room = _asMap(_data?['room']);
    if (room == null) return false;
    final status = AdminDashboardModels.statusOf(room);
    if (status != 'checked_in') return false;
    final guest = (room['current_guest_name'] ?? '').toString().trim();
    if (guest.isNotEmpty) return true;
    final booking = _asMap(_data?['active_booking']);
    if (booking != null) return true;
    return AdminDashboardModels.guestName(room) != '—';
  }

  String? get _managementBlockedReason {
    final r = _data?['management_blocked_reason'];
    return r == null ? null : r.toString();
  }

  String? get _stayBlockedMessage {
    if (_canEditGuestStay) return null;
    final reason = _managementBlockedReason;
    if (reason != null && reason.trim().isNotEmpty) return reason;
    final room = _asMap(_data?['room']);
    final status = room == null ? '' : AdminDashboardModels.statusOf(room);
    if (status == 'booked' || status == 'reserved') {
      return 'Check the guest in from the Bookings tab before adding fees or editing payment here.';
    }
    return 'Check the guest in from the Bookings tab before adding fees or editing payment here.';
  }

  Widget _buildBody() {
    if (_loading && _data == null) return const AppLoadingView();
    if (_error != null && _data == null) {
      return AppErrorView(message: _error!, onRetry: _load);
    }
    if (_data == null) {
      return AppErrorView(
        message: 'Room data is unavailable.',
        onRetry: _load,
      );
    }

    final room = _asMap(_data!['room']);
    if (room == null) {
      return AppErrorView(
        message: _error ?? 'Room data is unavailable. Pull to refresh.',
        onRetry: _load,
      );
    }
    final booking = _asMap(_data!['active_booking']);
    final charges = _chargesList();
    final chargesTotal =
        ((_data!['booking_charges_total'] as num?)?.toDouble() ?? 0);

    final roomNo = (room['room_number'] ?? '').toString();
    final status = AdminDashboardModels.statusOf(room);
    final guest = (room['current_guest_name'] ?? booking?['guest_name'] ?? '').toString();
    final pwd = (room['room_access_password'] ?? '').toString();
    const roomCardColor = Color(0xFFF3EDE3);
    final accent = Theme.of(context).colorScheme.primary;

    final children = <Widget>[
      if (_loading) const LinearProgressIndicator(minHeight: 2),
      Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: roomCardColor,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Room $roomNo',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              Text('Status: ${roomStatusLabel(status)}'),
              if (guest.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Guest: $guest'),
              ],
              if (pwd.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Password: $pwd'),
              ],
            ],
          ),
        ),
        if (!_canEditGuestStay) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _stayBlockedMessage ??
                      'Check the guest in from the Bookings tab before adding fees or editing payment here.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _close,
                    child: const Text('Back'),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'Booking info',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 8),
        if (booking == null)
          const Text('No active booking found for this room.')
        else
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: roomCardColor,
              border: Border.all(color: accent.withValues(alpha: 0.2)),
            ),
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.person_outline, color: accent, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (booking['guest_name'] ?? 'Guest').toString(),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      if ((booking['guest_phone'] ?? '').toString().isNotEmpty)
                        Text((booking['guest_phone'] ?? '').toString()),
                      if ((booking['guest_email'] ?? '').toString().isNotEmpty)
                        Text((booking['guest_email'] ?? '').toString()),
                      if ((booking['booking_reference'] ?? '')
                          .toString()
                          .isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Ref: ${(booking['booking_reference'] ?? '').toString()}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      if ((booking['stay_duration_label'] ?? '')
                          .toString()
                          .isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            (booking['stay_duration_label'] ?? '').toString(),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      if ((booking['check_in_display'] ?? '')
                          .toString()
                          .isNotEmpty)
                        Text(
                          'Arrival: ${AdminDashboardModels.cleanStayDisplay((booking['check_in_display'] ?? '').toString())}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      if ((booking['check_out_display'] ?? '')
                          .toString()
                          .isNotEmpty)
                        Text(
                          'Departure: ${AdminDashboardModels.cleanStayDisplay((booking['check_out_display'] ?? '').toString())}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (_canEditGuestStay) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _addFee,
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.add),
              label: const Text('+ Add fee'),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _updatingPayment ? null : _updatePaymentStatus,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: accent,
                    side: BorderSide(color: accent),
                  ),
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Payment'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _issuingRefund ? null : _issueRefund,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: accent,
                    side: BorderSide(color: accent),
                  ),
                  icon: const Icon(Icons.replay_outlined),
                  label: const Text('Refund'),
                ),
              ),
            ],
          ),
          if (status == 'checked_in' || status == 'booked') ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (_checkingOut || _changingStatus) ? null : _checkoutGuest,
                icon: _checkingOut
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.logout_outlined),
                label: Text(_checkingOut ? 'Checking out…' : 'Check out guest'),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _changingStatus ? null : _changeStatus,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: accent,
                    side: BorderSide(color: accent),
                  ),
                  icon: const Icon(Icons.toggle_on_outlined),
                  label: const Text('Change status'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _transferRoom,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: accent,
                    side: BorderSide(color: accent),
                  ),
                  icon: const Icon(Icons.swap_horiz_outlined),
                  label: const Text('Transfer room'),
                ),
              ),
            ],
          ),
        ] else ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _changingStatus ? null : _changeStatus,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: accent,
                    side: BorderSide(color: accent),
                  ),
                  icon: const Icon(Icons.toggle_on_outlined),
                  label: const Text('Change status'),
                ),
              ),
              if (booking != null) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _transferRoom,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: accent,
                      side: BorderSide(color: accent),
                    ),
                    icon: const Icon(Icons.swap_horiz_outlined),
                    label: const Text('Transfer room'),
                  ),
                ),
              ],
            ],
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'Charges',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 4),
        Text('Total fee: ${formatPeso(chargesTotal)}'),
        const SizedBox(height: 8),
        if (charges.isEmpty)
          const Text('No charges yet.')
        else
          ...charges.take(20).map((c) {
            if (c is! Map) return const SizedBox.shrink();
            final m = Map<String, dynamic>.from(c);
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: roomCardColor,
              ),
              child: ListTile(
                leading: Icon(Icons.receipt_long_outlined, color: accent),
                title: Text((m['label'] ?? '').toString()),
                subtitle: Text('Type: ${(m['type'] ?? '').toString()}'),
                trailing: Text(
                  formatBillLineAmount(m),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            );
          }),
    ];

    if (widget.panelBodyOnly) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: children,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: children,
      ),
    );
  }
}
