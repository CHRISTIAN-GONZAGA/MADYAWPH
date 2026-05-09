import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../dio_client.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/app_state_views.dart';
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
      if (status.isNotEmpty) 'Status: $status',
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
      builder: (context) => AlertDialog(
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

    if (payload == null) return;
    final label = (payload['label'] ?? '').toString();
    final amount = (payload['amount'] as num?)?.toDouble() ?? 0;
    if (label.isEmpty || amount <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a reason and amount > 0.')),
      );
      return;
    }

    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
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

  Future<void> _changeStatus() async {
    final room = _data?['room'] as Map<String, dynamic>?;
    final booking = _data?['active_booking'] as Map<String, dynamic>?;
    final roomId = (room?['id'] ?? widget.roomId).toString();
    final current = (room?['status'] ?? 'available').toString();
    final paid = (booking?['payment_status'] ?? '').toString() == 'paid';
    final canCheckout = current != 'checked_in' || paid;
    String status = current;
    final chosen = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change room status'),
        content: DropdownButtonFormField<String>(
          initialValue: current,
          items: [
            const DropdownMenuItem(value: 'available', child: Text('available')),
            const DropdownMenuItem(value: 'booked', child: Text('booked')),
            const DropdownMenuItem(value: 'checked_in', child: Text('checked_in')),
            if (canCheckout)
              const DropdownMenuItem(value: 'checked_out', child: Text('checked_out')),
            const DropdownMenuItem(value: 'maintenance', child: Text('maintenance')),
            const DropdownMenuItem(value: 'reserved', child: Text('reserved')),
          ],
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
    if (_changingStatus) return;
    setState(() => _changingStatus = true);
    try {
      await portalDio().put('/rooms/$roomId/status', data: {'status': chosen});
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Status updated.')));
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(dioErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _changingStatus = false);
    }
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
      if (available.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('No available rooms.')));
        return;
      }
      String toRoomId =
          ((available.first as Map<String, dynamic>)['id'] ?? '').toString();
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
      await portalDio().post('/room-transfers', data: {
        'booking_id': bookingId,
        'from_room_id': fromRoomId,
        'to_room_id': payload['to_room_id'],
        'reason': 'Guest requested transfer',
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
    final refCtrl =
        TextEditingController(text: (booking?['payment_reference'] ?? '').toString());
    final payload = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Payment status'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: current,
                items: const [
                  DropdownMenuItem(value: 'unpaid', child: Text('unpaid')),
                  DropdownMenuItem(value: 'paid', child: Text('paid')),
                ],
                onChanged: (v) => setLocal(() => next = v ?? current),
                decoration: const InputDecoration(
                  labelText: 'Status',
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
                  helperText: 'Manual tracking only. Not linked to PayMongo.',
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
                'payment_status': next,
                'payment_reference': refCtrl.text.trim(),
                'payment_method': method,
              }),
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
    if (payload == null || _updatingPayment) return;
    setState(() => _updatingPayment = true);
    try {
      await portalDio().post('/admin/bookings/$bookingId/payment-status', data: payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment status updated.')),
      );
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
              Text('Status: $status'),
              if (guest.isNotEmpty) Text('Guest: $guest'),
              if (pwd.isNotEmpty) Text('Password: $pwd'),
            ],
          ),
        ),
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
