import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';

import '../../dio_client.dart';
import '../../utils/money_format.dart';
import '../../widgets/app_state_views.dart';
import '../../widgets/room_status_label.dart';
import '../widgets/extend_stay_dialog.dart';
import 'admin_dashboard_models.dart';
import 'widgets/admin_opaque_scaffold.dart';
import 'widgets/hourly_billing.dart';
import 'widgets/stay_receipt_dialog.dart';
import 'admin_room_fee_presets_screen.dart';

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
  bool _issuingRefund = false;
  bool _recordingPartialPayment = false;
  bool _extendingStay = false;
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
    if (prior == null) return merged;

    final freshStatus = AdminDashboardModels.statusOf(fresh);
    if (freshStatus.isEmpty) {
      final priorStatus = AdminDashboardModels.statusOf(prior);
      if (priorStatus.isNotEmpty) {
        merged['status'] = prior['status'];
      }
    }

    // After checkout the API clears guest fields — do not restore stale snapshot data.
    if ({'maintenance', 'available'}.contains(freshStatus)) {
      return merged;
    }

    final priorGuest =
        (prior['current_guest_name'] ?? '').toString().trim();
    final freshGuest =
        (fresh['current_guest_name'] ?? '').toString().trim();
    if (freshGuest.isEmpty && priorGuest.isNotEmpty) {
      merged['current_guest_name'] = prior['current_guest_name'];
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

  void _clearActiveStayFromState() {
    final roomMap = _asMap(_data?['room']);
    if (_data == null || roomMap == null) return;
    final room = Map<String, dynamic>.from(roomMap);
    room['status'] = 'maintenance';
    room['current_guest_name'] = null;
    room['current_check_in'] = null;
    room['current_check_out'] = null;
    room['room_access_password'] = '';
    _data = {
      ..._data!,
      'room': room,
      'active_booking': null,
      'booking_charges': const [],
      'booking_charges_total': 0,
      'refund_total': 0,
    };
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
          final activeBooking = payload['active_booking'];
          _data = {
            ...?_data,
            'room': _mergeRoomMaps(priorRoom, room),
            'active_booking': activeBooking,
            'booking_charges': activeBooking == null
                ? const []
                : (payload['booking_charges'] ?? const []),
            'booking_charges_total': activeBooking == null
                ? 0
                : (payload['booking_charges_total'] ?? 0),
            'refund_total': activeBooking == null
                ? 0
                : (payload['refund_total'] ?? 0),
            'can_edit_guest_stay': payload['can_edit_guest_stay'] ??
                _data?['can_edit_guest_stay'],
            'management_blocked_reason': payload['management_blocked_reason'] ??
                _data?['management_blocked_reason'],
            'pending_reservation': payload['pending_reservation'] ??
                _data?['pending_reservation'],
            'extension_options': payload['extension_options'] ??
                _data?['extension_options'],
          };
          if (_canEditGuestStay) {
            _data!.remove('management_blocked_reason');
          }
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
      showAppMessage(context, 'No active booking for this room.');
      return;
    }

    final presets = await fetchRoomFeePresets();
    if (!mounted) return;
    final reasonCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          void applyPreset(Map<String, dynamic> preset) {
            reasonCtrl.text = (preset['label'] ?? '').toString();
            final amount = (preset['amount'] as num?)?.toDouble() ?? 0;
            if (amount > 0) {
              amountCtrl.text = amount == amount.roundToDouble()
                  ? '${amount.toInt()}'
                  : amount.toStringAsFixed(2);
            }
            setLocal(() {});
          }

          return AlertDialog(
            title: const Text('Add fee'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (presets.isNotEmpty) ...[
                    Text(
                      'Quick pick',
                      style: Theme.of(ctx).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: presets.map((preset) {
                        final label = (preset['label'] ?? '').toString();
                        final amount = (preset['amount'] as num?)?.toDouble() ?? 0;
                        final subtitle = amount > 0
                            ? '₱${amount.toStringAsFixed(amount == amount.roundToDouble() ? 0 : 2)}'
                            : null;
                        return ActionChip(
                          label: Text(
                            subtitle == null ? label : '$label · $subtitle',
                          ),
                          onPressed: () => applyPreset(preset),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    controller: reasonCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Reason (custom)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop({
                  'label': reasonCtrl.text.trim(),
                  'amount': double.tryParse(amountCtrl.text.trim()) ?? 0,
                }),
                child: const Text('Add'),
              ),
            ],
          );
        },
      ),
    );
    reasonCtrl.dispose();
    amountCtrl.dispose();

    if (payload == null) return;
    if (!mounted) return;
    final label = (payload['label'] ?? '').toString();
    final amount = parseJsonDouble(payload['amount']);
    if (label.isEmpty || amount <= 0) {
      showAppMessage(context, 'Enter a reason and amount > 0.');
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
      showAppMessage(context, 'Fee added.');
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _extendStay() async {
    final room = _asMap(_data?['room']);
    final booking = _asMap(_data?['active_booking']);
    final bookingId = (booking?['id'] ?? booking?['_id'] ?? '').toString();
    if (bookingId.isEmpty || room == null) {
      showAppMessage(context, 'No active booking to extend.');
      return;
    }

    if (!HourlyBilling.isHourly(room)) {
      showAppMessage(context, 'Extend by nights is not available here yet.');
      return;
    }

    final extensionOptions =
        _asMap(_data?['extension_options']);
    final payload = await showExtendStayDialog(
      context,
      extensionOptions: extensionOptions,
      maxPickerHours: 10,
    );
    if (payload == null) {
      if (!mounted) return;
      showAppMessage(context, 'No extension options available. Set “Price per extra hour” on the room category for hourly extensions.',);
      return;
    }
    if (!mounted) return;

    if (_extendingStay) return;
    setState(() => _extendingStay = true);
    try {
      final res = await portalDio().post<Map<String, dynamic>>(
        '/admin/bookings/$bookingId/extend-stay',
        data: payload,
      );
      if (!mounted) return;
      final fee = res.data?['extension_fee'];
      final checkout = res.data?['new_checkout_date'];
      final checkoutTime = res.data?['new_checkout_time'];
      final when = checkoutTime != null ? '$checkout $checkoutTime' : checkout;
      showAppMessage(
        context,
        'Stay extended. New checkout: $when. Fee: ${formatPeso(fee)}',
      );
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _extendingStay = false);
    }
  }

  Future<void> _checkoutGuest() async {
    final room = _asMap(_data?['room']);
    final booking = _asMap(_data?['active_booking']);
    final roomId = (room?['id'] ?? _roomId).toString();
    final bookingId = (booking?['id'] ?? '').toString();
    final guest =
        (room?['current_guest_name'] ?? booking?['guest_name'] ?? 'Guest')
            .toString();

    if (bookingId.isEmpty) {
      if (!mounted) return;
      showAppMessage(context, 'No active booking for this room.');
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
      showAppMessage(context, dioErrorMessage(e), isError: true);
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
    final billTotalRaw = billSummary?['total_due'] ?? billSummary?['balance_due'];
    final totalDue = billTotalRaw != null
        ? parseJsonDouble(billTotalRaw)
        : parseJsonDouble(booking?['total_amount']);
    final amountPaid = parseJsonDouble(billSummary?['amount_paid']);
    String status = current == 'paid' ? 'paid' : 'unpaid';
    var paymentReady = current == 'paid' && totalDue <= 0.009;
    var remainingDue = totalDue;
    var paidSoFar = amountPaid;
    final lines = (billSummary?['lines'] as List?) ?? const [];
    final refCtrl =
        TextEditingController(text: (booking?['payment_reference'] ?? '').toString());
    final tenderCtrl = TextEditingController(
      text: totalDue > 0 ? totalDue.toStringAsFixed(2) : '',
    );

    if (!mounted) return;
    final shouldCheckout = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) {
          final tendered = double.tryParse(tenderCtrl.text.trim()) ?? 0;
          final change = status == 'paid' && tendered > 0
              ? (tendered - remainingDue).clamp(0, double.infinity)
              : 0.0;
          final balanceCleared = remainingDue <= 0.009;
          final canCheckout =
              paymentReady && status == 'paid' && balanceCleared;

          return AlertDialog(
            title: const Text('Check out guest'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Guest: $guest',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    paidSoFar > 0
                        ? 'Remaining due: ${formatPeso(remainingDue)}'
                        : 'Amount due: ${formatPeso(remainingDue)}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  if (paidSoFar > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Already paid: ${formatPeso(paidSoFar)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  if (!balanceCleared)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Checkout is blocked until the full balance is paid.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.w600,
                            ),
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
                  const Divider(height: 24),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    items: const [
                      DropdownMenuItem(value: 'unpaid', child: Text('Unpaid')),
                      DropdownMenuItem(value: 'paid', child: Text('Paid in full')),
                    ],
                    onChanged: balanceCleared && paymentReady
                        ? null
                        : (v) => setLocal(() {
                              status = v ?? status;
                              if (status != 'paid') {
                                paymentReady = false;
                              }
                            }),
                    decoration: const InputDecoration(
                      labelText: 'Payment status',
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
                  const SizedBox(height: 10),
                  TextField(
                    controller: tenderCtrl,
                    enabled: !balanceCleared || !paymentReady,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: remainingDue > 0
                          ? 'Amount given by guest (min ${formatPeso(remainingDue)})'
                          : 'Amount given by guest',
                      border: const OutlineInputBorder(),
                      prefixText: '₱ ',
                    ),
                    onChanged: (_) => setLocal(() {}),
                  ),
                  if (status == 'paid' && tendered > 0 && remainingDue > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        tendered + 0.009 < remainingDue
                            ? 'Need at least ${formatPeso(remainingDue)} to clear the balance.'
                            : 'Change: ${formatPeso(change)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: tendered + 0.009 < remainingDue
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.primary,
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
                  if (!canCheckout) ...[
                    const SizedBox(height: 12),
                    Text(
                      !balanceCleared
                          ? 'Collect the remaining ${formatPeso(remainingDue)} and save payment as Paid in full.'
                          : 'Confirm payment as Paid in full, then check out.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              if (!paymentReady || !balanceCleared)
                FilledButton.tonal(
                  onPressed: status != 'paid' ||
                          (remainingDue > 0.009 &&
                              tendered + 0.009 < remainingDue)
                      ? null
                      : () async {
                          try {
                            final res =
                                await portalDio().post<Map<String, dynamic>>(
                              '/admin/bookings/$bookingId/payment-status',
                              data: {
                                'payment_status': 'paid',
                                'payment_reference': refCtrl.text.trim(),
                                'payment_method': method,
                                'amount_tendered':
                                    tendered > 0 ? tendered : null,
                              },
                            );
                            if (!context.mounted) return;
                            final bill = res.data?['bill'];
                            final billMap = bill is Map
                                ? Map<String, dynamic>.from(bill)
                                : const <String, dynamic>{};
                            final changeDue =
                                parseJsonDouble(res.data?['change_due']);
                            setLocal(() {
                              remainingDue = parseJsonDouble(
                                billMap['balance_due'] ?? billMap['total_due'],
                              );
                              paidSoFar = parseJsonDouble(billMap['amount_paid']);
                              status = 'paid';
                              paymentReady = remainingDue <= 0.009;
                            });
                            showAppMessage(
                              context,
                              remainingDue > 0.009
                                  ? 'Payment saved, but a balance remains.'
                                  : (changeDue > 0
                                      ? 'Payment recorded. Change due: ${formatPeso(changeDue)}'
                                      : 'Full payment recorded. Ready to check out.'),
                            );
                          } on DioException catch (e) {
                            if (!context.mounted) return;
                            showAppMessage(
                              context,
                              dioErrorMessage(e),
                              isError: true,
                            );
                          }
                        },
                  child: const Text('Save full payment'),
                ),
              FilledButton(
                onPressed: canCheckout
                    ? () => Navigator.of(dialogContext).pop(true)
                    : null,
                child: const Text('Check out guest'),
              ),
            ],
          );
        },
      ),
    );

    refCtrl.dispose();
    tenderCtrl.dispose();
    if (shouldCheckout != true || _checkingOut) return;

    setState(() => _checkingOut = true);
    try {
      final res = await portalDio().post<Map<String, dynamic>>(
        '/rooms/$roomId/checkout',
      );
      if (!mounted) return;
      final msg = (res.data?['message'] ?? 'Guest checked out.').toString();
      setState(_clearActiveStayFromState);
      showAppMessage(context, msg);
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
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
    final balanceDue = parseJsonDouble(
      _data?['balance_due'] ??
          _asMap(_data?['bill_summary'])?['balance_due'] ??
          _data?['booking_charges_total'],
    );
    final hasStay = current == 'checked_in' ||
        current == 'booked' ||
        (room?['current_guest_name'] ?? '').toString().trim().isNotEmpty;
    final showCheckedOut =
        hasStay && paid && balanceDue <= 0.009 && _canEditGuestStay;
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
      showAppMessage(context, 'Mark payment as paid before checking out this guest.');
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
      if (chosen == 'checked_out') {
        setState(_clearActiveStayFromState);
        final receipt = res.data?['receipt'] as Map<String, dynamic>?;
        if (context.mounted) {
          await showStayReceiptDialog(context, receipt: receipt);
        }
      }
      showAppMessage(context, msg);
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
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
      showAppMessage(context, 'No active booking to transfer.');
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
        showAppMessage(context, dioErrorMessage(e), isError: true);
        return;
      }
      var approveAdjustment = false;
      final adjustment = parseJsonDouble(preview?['price_adjustment']);
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
              '(${formatPeso(parseJsonDouble(preview?['from_nightly_rate']))}/night) '
              'to Room ${preview?['to_room_number']} '
              '(${formatPeso(parseJsonDouble(preview?['to_nightly_rate']))}/night).\n\n'
              'Bill ${adjustment > 0 ? 'increases' : 'decreases'} by ${formatPeso(adjustment.abs())}.\n'
              'New total: ${formatPeso(parseJsonDouble(preview?['new_total']))}.\n\n'
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
      showAppMessage(context, 'Room transferred successfully.');
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  Future<void> _issueRefund() async {
    final booking = _asMap(_data?['active_booking']);
    final bookingId = (booking?['id'] ?? '').toString();
    if (bookingId.isEmpty) {
      if (!mounted) return;
      showAppMessage(context, 'No active booking for this room.');
      return;
    }
    final amountCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Issue refund'),
        content: SingleChildScrollView(
          child: Column(
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
      showAppMessage(context, 'Refund recorded and reports updated.');
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _issuingRefund = false);
    }
  }

  Future<void> _recordPartialPayment() async {
    final booking = _asMap(_data?['active_booking']);
    final bookingId = (booking?['id'] ?? '').toString();
    if (bookingId.isEmpty) {
      if (!mounted) return;
      showAppMessage(context, 'No active booking for this room.');
      return;
    }

    final balanceDue = parseJsonDouble(
      _data?['balance_due'] ??
          _asMap(_data?['bill_summary'])?['balance_due'] ??
          _data?['booking_charges_total'] ??
          booking?['total_amount'],
    );
    if (balanceDue <= 0) {
      if (!mounted) return;
      showAppMessage(context, 'No remaining balance on this booking.');
      return;
    }

    final amountCtrl = TextEditingController(
      text: balanceDue.toStringAsFixed(2),
    );
    final refCtrl = TextEditingController(
      text: (booking?['payment_reference'] ?? '').toString(),
    );
    final noteCtrl = TextEditingController();
    var method = (() {
      final raw = (booking?['payment_method'] ?? 'Cash').toString().trim().toLowerCase();
      if (raw == 'gcash' || raw == 'g-cash') return 'GCash';
      if (raw == 'paymaya' || raw == 'maya' || raw == 'pay maya') return 'PayMaya';
      if (raw == 'credit card' || raw == 'credit_card' || raw == 'card') {
        return 'Credit Card';
      }
      return 'Cash';
    })();

    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) {
          final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
          final remainingAfter = (balanceDue - amount).clamp(0, double.infinity);
          return AlertDialog(
            title: const Text('Partial payment'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Remaining balance: ${formatPeso(balanceDue)}',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Amount received',
                      border: OutlineInputBorder(),
                      prefixText: '₱ ',
                    ),
                    onChanged: (_) => setLocal(() {}),
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
                  const SizedBox(height: 10),
                  TextField(
                    controller: refCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Payment reference (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Note (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (amount > 0) ...[
                    const SizedBox(height: 12),
                    Text(
                      amount >= balanceDue
                          ? 'This clears the balance in full.'
                          : 'Balance after payment: ${formatPeso(remainingAfter)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: amount <= 0 || amount > balanceDue + 0.009
                    ? null
                    : () => Navigator.of(context).pop({
                          'amount': amount,
                          'payment_method': method,
                          'payment_reference': refCtrl.text.trim(),
                          'note': noteCtrl.text.trim(),
                        }),
                child: const Text('Record payment'),
              ),
            ],
          );
        },
      ),
    );
    if (payload == null || _recordingPartialPayment) return;
    setState(() => _recordingPartialPayment = true);
    try {
      final res = await portalDio().post<Map<String, dynamic>>(
        '/admin/bookings/$bookingId/partial-payment',
        data: payload,
      );
      if (!mounted) return;
      final paid = parseJsonDouble(res.data?['amount']);
      final remaining = parseJsonDouble(res.data?['balance_due']);
      final status = (res.data?['payment_status'] ?? '').toString();
      showAppMessage(
        context,
        status == 'paid'
            ? 'Payment of ${formatPeso(paid)} recorded. Balance cleared.'
            : 'Partial payment of ${formatPeso(paid)} recorded. Remaining ${formatPeso(remaining)}.',
      );
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _recordingPartialPayment = false);
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
    final chargesTotal = parseJsonDouble(_data!['booking_charges_total']);
    final amountPaid = parseJsonDouble(
      _data!['amount_paid'] ?? _asMap(_data!['bill_summary'])?['amount_paid'],
    );
    final balanceDue = parseJsonDouble(
      _data!['balance_due'] ??
          _asMap(_data!['bill_summary'])?['balance_due'] ??
          chargesTotal,
    );
    final paymentStatus =
        (booking?['payment_status'] ?? 'unpaid').toString().toLowerCase();

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
                      const SizedBox(height: 8),
                      Text(
                        'Payment: ${paymentStatus == 'partial' ? 'Partial' : paymentStatus == 'paid' ? 'Paid' : 'Unpaid'}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      if (amountPaid > 0)
                        Text(
                          'Paid so far: ${formatPeso(amountPaid)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      Text(
                        'Balance due: ${formatPeso(balanceDue)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: accent,
                            ),
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
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: (_recordingPartialPayment || balanceDue <= 0)
                  ? null
                  : _recordPartialPayment,
              icon: _recordingPartialPayment
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.payments_outlined),
              label: Text(
                _recordingPartialPayment
                    ? 'Recording…'
                    : 'Partial payment',
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
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
          if ((status == 'checked_in' || status == 'booked') &&
              booking != null &&
              HourlyBilling.isHourly(room)) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: (_extendingStay || _busy) ? null : _extendStay,
                style: OutlinedButton.styleFrom(
                  foregroundColor: accent,
                  side: BorderSide(color: accent),
                ),
                icon: _extendingStay
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.more_time_outlined),
                label: Text(_extendingStay ? 'Extending…' : 'Extend stay'),
              ),
            ),
          ],
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
        if (amountPaid > 0 || paymentStatus == 'partial') ...[
          const SizedBox(height: 2),
          Text('Paid so far: ${formatPeso(amountPaid)}'),
          Text(
            'Balance due: ${formatPeso(balanceDue)}',
            style: TextStyle(fontWeight: FontWeight.w700, color: accent),
          ),
        ],
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
