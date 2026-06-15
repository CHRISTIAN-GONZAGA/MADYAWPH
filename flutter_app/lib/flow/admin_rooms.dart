import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../dio_client.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/app_state_views.dart';
import '../widgets/room_status_label.dart';
import 'admin/widgets/stay_receipt_dialog.dart';
import 'admin_categories.dart';

class AdminRoomsScreen extends StatefulWidget {
  const AdminRoomsScreen({super.key});

  @override
  State<AdminRoomsScreen> createState() => _AdminRoomsScreenState();
}

class _AdminRoomsScreenState extends State<AdminRoomsScreen> {
  List<dynamic> _rooms = const [];
  String? _error;
  bool _loading = true;

  static String _categoryLabel(Map<String, dynamic> r) {
    final cn = (r['category_name'] ?? '').toString().trim();
    if (cn.isNotEmpty) {
      return cn;
    }
    final rt = (r['room_type'] ?? '').toString().trim();
    if (rt.isEmpty) {
      return 'Uncategorized';
    }
    if (rt.length == 1) {
      return rt.toUpperCase();
    }
    return '${rt[0].toUpperCase()}${rt.substring(1)}';
  }

  static int _compareRoomNumber(Map<String, dynamic> a, Map<String, dynamic> b) {
    final na = (a['room_number'] ?? '').toString();
    final nb = (b['room_number'] ?? '').toString();
    final ia = int.tryParse(na);
    final ib = int.tryParse(nb);
    if (ia != null && ib != null) {
      return ia.compareTo(ib);
    }
    return na.toLowerCase().compareTo(nb.toLowerCase());
  }

  /// Groups rooms by category label; sorts rooms within each group.
  Map<String, List<Map<String, dynamic>>> _roomsByCategory() {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final raw in _rooms) {
      final r = raw as Map<String, dynamic>;
      final label = _categoryLabel(r);
      map.putIfAbsent(label, () => []).add(r);
    }
    for (final list in map.values) {
      list.sort(_compareRoomNumber);
    }
    return map;
  }

  List<String> _sortedCategoryKeys(Map<String, List<Map<String, dynamic>>> grouped) {
    final keys = grouped.keys.toList();
    keys.sort((a, b) {
      const unc = 'Uncategorized';
      if (a == unc) return 1;
      if (b == unc) return -1;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
    return keys;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await portalDio().get<Map<String, dynamic>>('/admin/rooms');
      setState(() {
        _rooms = (res.data?['data'] as List<dynamic>?) ?? const [];
        _loading = false;
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

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppBar(
        title: const Text('Manage rooms'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          IconButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                  builder: (_) => const AdminCategoriesScreen()),
            ),
            icon: const Icon(Icons.category_outlined),
            tooltip: 'Manage categories',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const AppLoadingView();
    if (_error != null) {
      return AppErrorView(message: _error!, onRetry: _load);
    }

    if (_rooms.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No rooms yet. Add rooms or sync from your property setup.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      );
    }

    final grouped = _roomsByCategory();
    final categories = _sortedCategoryKeys(grouped);
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 4),
            child: Text(
              'Rooms are grouped by category. Tap a section to expand or collapse.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ...categories.asMap().entries.map((entry) {
            final index = entry.key;
            final cat = entry.value;
            final rooms = grouped[cat]!;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  key: PageStorageKey<String>('admin_room_cat_$cat'),
                  initiallyExpanded: index == 0,
                  tilePadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  collapsedShape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                  backgroundColor: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.35),
                  collapsedBackgroundColor:
                      theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.2),
                  leading: Icon(
                    Icons.folder_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  title: Text(
                    cat,
                    style: theme.textTheme.titleMedium,
                  ),
                  subtitle: Text(
                    '${rooms.length} room${rooms.length == 1 ? '' : 's'}',
                    style: theme.textTheme.bodySmall,
                  ),
                  childrenPadding:
                      const EdgeInsets.only(left: 8, right: 8, bottom: 12),
                  children: [
                    for (final r in rooms)
                      _AdminRoomRow(
                        room: r,
                        categoryFallback: cat,
                        onOpenDetail: () async {
                          final id =
                              (r['id'] ?? r['_id'] ?? '').toString();
                          await Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  AdminRoomDetailScreen(roomId: id),
                            ),
                          );
                          await _load();
                        },
                      ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _AdminRoomRow extends StatelessWidget {
  const _AdminRoomRow({
    required this.room,
    required this.categoryFallback,
    required this.onOpenDetail,
  });

  final Map<String, dynamic> room;
  final String categoryFallback;
  final VoidCallback onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final roomNo = (room['room_number'] ?? '').toString();
    final status = (room['status'] ?? '').toString();
    final guest = (room['current_guest_name'] ?? '').toString();
    final pwd = (room['room_access_password'] ?? '').toString();
    final displayName = (room['display_name'] ?? '').toString().trim();
    final typeHint = (room['room_type'] ?? '').toString().trim();
    final subtitleParts = <String>[
      if (status.isNotEmpty) 'Status: ${roomStatusLabel(status)}',
      if (guest.isNotEmpty) 'Guest: $guest',
      if (pwd.isNotEmpty) 'Password: $pwd',
    ];

    final extra = <String>[
      if (displayName.isNotEmpty) displayName,
      ...subtitleParts,
      if (typeHint.isNotEmpty && categoryFallback == 'Uncategorized')
        'Type: $typeHint',
    ];

    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: ListTile(
        leading: const Icon(Icons.meeting_room_outlined),
        title: Text('Room $roomNo'),
        subtitle: Text(
          extra.join(' · '),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onOpenDetail,
      ),
    );
  }
}

class AdminRoomDetailScreen extends StatefulWidget {
  const AdminRoomDetailScreen({super.key, required this.roomId});

  final String roomId;

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await portalDio()
          .get<Map<String, dynamic>>('/admin/rooms/${widget.roomId}');
      setState(() {
        _data = res.data;
        _loading = false;
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
    final booking = _data?['active_booking'] as Map<String, dynamic>?;
    final room = _data?['room'] as Map<String, dynamic>?;
    final bookingId = booking?['id']?.toString() ?? '';
    final roomId = room?['id']?.toString() ?? widget.roomId;
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
    final room = _data?['room'] as Map<String, dynamic>?;
    final booking = _data?['active_booking'] as Map<String, dynamic>?;
    final roomId = (room?['id'] ?? widget.roomId).toString();
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
    final room = _data?['room'] as Map<String, dynamic>?;
    final booking = _data?['active_booking'] as Map<String, dynamic>?;
    final roomId = (room?['id'] ?? widget.roomId).toString();
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
    final booking = _data?['active_booking'] as Map<String, dynamic>?;
    final room = _data?['room'] as Map<String, dynamic>?;
    final bookingId = (booking?['id'] ?? '').toString();
    final fromRoomId = (room?['id'] ?? widget.roomId).toString();
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
              '(₱${(preview?['from_nightly_rate'] as num?)?.toStringAsFixed(0) ?? '0'}/night) '
              'to Room ${preview?['to_room_number']} '
              '(₱${(preview?['to_nightly_rate'] as num?)?.toStringAsFixed(0) ?? '0'}/night).\n\n'
              'Bill ${adjustment > 0 ? 'increases' : 'decreases'} by ₱${adjustment.abs().toStringAsFixed(0)}.\n'
              'New total: ₱${(preview?['new_total'] as num?)?.toStringAsFixed(0) ?? '0'}.\n\n'
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
    final booking = _data?['active_booking'] as Map<String, dynamic>?;
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
                    'Total bill: ₱${totalDue.toStringAsFixed(2)}',
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
                            Text(
                              '₱${((line['amount'] as num?) ?? 0).toStringAsFixed(0)}',
                            ),
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
                        'Change: ₱${change.toStringAsFixed(2)}',
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
          ? 'Payment recorded. Change due: ₱${changeDue.toStringAsFixed(2)}'
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
    final booking = _data?['active_booking'] as Map<String, dynamic>?;
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

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppBar(
        title: const Text('Room details'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _buildBody(),
    );
  }

  bool get _canEditGuestStay => _data?['can_edit_guest_stay'] == true;

  String? get _managementBlockedReason {
    final r = _data?['management_blocked_reason'];
    return r == null ? null : r.toString();
  }

  Widget _buildBody() {
    if (_loading) return const AppLoadingView();
    if (_error != null) {
      return AppErrorView(message: _error!, onRetry: _load);
    }

    final room = _data!['room'] as Map<String, dynamic>;
    final booking = _data!['active_booking'] as Map<String, dynamic>?;
    final charges = (_data!['booking_charges'] as List<dynamic>?) ?? const [];
    final chargesTotal =
        ((_data!['booking_charges_total'] as num?)?.toDouble() ?? 0);
    final refundTotal = ((_data!['refund_total'] as num?)?.toDouble() ?? 0);

    final roomNo = (room['room_number'] ?? '').toString();
    final status = (room['status'] ?? '').toString();
    final guest = (room['current_guest_name'] ?? '').toString();
    final pwd = (room['room_access_password'] ?? '').toString();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Room $roomNo',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: roomStatusColor(status).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      roomStatusLabel(status),
                      style: TextStyle(
                        color: roomStatusColor(status),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              if (guest.isNotEmpty) Text('Guest: $guest'),
              if (_canEditGuestStay && pwd.isNotEmpty) Text('Password: $pwd'),
            ],
          ),
        ),
        if (!_canEditGuestStay) ...[
          const SizedBox(height: 12),
          MaterialBanner(
            backgroundColor: Colors.orange.shade50,
            content: Text(
              _managementBlockedReason ??
                  'Check the guest in from the Bookings tab before adding fees or editing payment here.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Back'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        Text('Booking info', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (booking == null)
          const Text('No active booking found for this room.')
        else
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_outline),
              isThreeLine: true,
              title: Text((booking['guest_name'] ?? '').toString()),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [
                      'Phone: ${(booking['guest_phone'] ?? '').toString()}',
                      'Email: ${(booking['guest_email'] ?? '').toString()}',
                      'Ref: ${(booking['booking_reference'] ?? '').toString()}',
                    ].where((s) => !s.endsWith(': ')).join('\n'),
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
                      'Arrival: ${(booking['check_in_display'] ?? '').toString()}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if ((booking['check_out_display'] ?? '')
                      .toString()
                      .isNotEmpty)
                    Text(
                      'Departure: ${(booking['check_out_display'] ?? '').toString()}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  Text(
                    'Payment method: ${(booking['payment_method'] ?? '-').toString()}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    'Payment status: ${(booking['payment_status'] ?? 'unpaid').toString()}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        if (_canEditGuestStay) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _addFee,
                  icon: const Icon(Icons.add),
                  label: const Text('Add fee'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _updatingPayment ? null : _updatePaymentStatus,
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Payment'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _issuingRefund ? null : _issueRefund,
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
                  icon: const Icon(Icons.toggle_on_outlined),
                  label: const Text('Change status'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _transferRoom,
                  icon: const Icon(Icons.swap_horiz_outlined),
                  label: const Text('Transfer room'),
                ),
              ),
            ],
          ),
        ] else ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _changingStatus ? null : _changeStatus,
            icon: const Icon(Icons.build_outlined),
            label: const Text('Housekeeping status only'),
          ),
        ],
        const SizedBox(height: 16),
        Text('Charges', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
            'Total fee: ₱${chargesTotal.toStringAsFixed(2)} · Refunds: ₱${refundTotal.toStringAsFixed(2)}'),
        const SizedBox(height: 8),
        if (charges.isEmpty)
          const Text('No charges yet.')
        else
          ...charges.take(20).map((c) {
            final m = c as Map<String, dynamic>;
            return Card(
              child: ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: Text((m['label'] ?? '').toString()),
                subtitle: Text('Type: ${(m['type'] ?? '').toString()}'),
                trailing: Text('₱${(m['amount'] ?? '').toString()}'),
              ),
            );
          }),
      ],
    );
  }
}
