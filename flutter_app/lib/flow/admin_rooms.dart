import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../dio_client.dart';
import '../widgets/theme_fab.dart';
import 'admin_categories.dart';

class AdminRoomsScreen extends StatefulWidget {
  const AdminRoomsScreen({super.key});

  @override
  State<AdminRoomsScreen> createState() => _AdminRoomsScreenState();
}

class _AdminRoomsScreenState extends State<AdminRoomsScreen> {
  List<dynamic> _rooms = const [];
  List<dynamic> _categories = const [];
  String? _error;
  bool _loading = true;
  bool _creating = false;

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
      final cat =
          await portalDio().get<Map<String, dynamic>>('/room-categories');
      setState(() {
        _rooms = (res.data?['data'] as List<dynamic>?) ?? const [];
        _categories = (cat.data?['data'] as List<dynamic>?) ?? const [];
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage rooms'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          IconButton(
            onPressed: _creating ? null : _createRoom,
            icon: const Icon(Icons.add_business_outlined),
            tooltip: 'Create room',
          ),
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
      floatingActionButton: const ThemeFab(),
      body: _buildBody(),
    );
  }

  Future<void> _createRoom() async {
    if (_categories.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create a category first.')),
      );
      return;
    }
    final nameCtrl = TextEditingController();
    final roomNoCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final imgCtrl = TextEditingController();
    final amenitiesCtrl = TextEditingController();
    String categoryId =
        ((_categories.first as Map<String, dynamic>)['id'] ?? '').toString();
    String roomType = 'Single';
    String status = 'available';
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Create room'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: categoryId,
                  items: _categories.map((c) {
                    final m = c as Map<String, dynamic>;
                    final id = (m['id'] ?? '').toString();
                    final name = (m['name'] ?? 'Unknown').toString();
                    return DropdownMenuItem(value: id, child: Text(name));
                  }).toList(),
                  onChanged: (v) =>
                      setLocal(() => categoryId = v ?? categoryId),
                  decoration: const InputDecoration(
                      labelText: 'Category', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Display name',
                        border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(
                    controller: roomNoCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Room number',
                        border: OutlineInputBorder())),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: roomType,
                  items: const [
                    DropdownMenuItem(value: 'Single', child: Text('Single')),
                    DropdownMenuItem(value: 'Double', child: Text('Double')),
                    DropdownMenuItem(value: 'Suite', child: Text('Suite')),
                    DropdownMenuItem(value: 'Deluxe', child: Text('Deluxe')),
                  ],
                  onChanged: (v) => setLocal(() => roomType = v ?? roomType),
                  decoration: const InputDecoration(
                      labelText: 'Room type', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                    controller: priceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Price per night',
                        border: OutlineInputBorder())),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  items: const [
                    DropdownMenuItem(
                        value: 'available', child: Text('available')),
                    DropdownMenuItem(value: 'booked', child: Text('booked')),
                    DropdownMenuItem(
                        value: 'maintenance', child: Text('maintenance')),
                    DropdownMenuItem(
                        value: 'reserved', child: Text('reserved')),
                  ],
                  onChanged: (v) => setLocal(() => status = v ?? status),
                  decoration: const InputDecoration(
                      labelText: 'Status', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: amenitiesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Amenities (comma separated)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: imgCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Room image URL (or upload later)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.of(context).pop({
                'category_id': categoryId,
                'display_name': nameCtrl.text.trim(),
                'room_number': roomNoCtrl.text.trim(),
                'room_type': roomType,
                'price_per_night': double.tryParse(priceCtrl.text.trim()) ?? 0,
                'status': status,
                'amenities': amenitiesCtrl.text
                    .split(',')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList(),
                'image_url': imgCtrl.text.trim(),
              }),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (payload == null) return;

    if (_creating) return;
    setState(() => _creating = true);
    try {
      final imageUrl = (payload['image_url'] ?? '').toString();
      if (imageUrl.isEmpty) payload.remove('image_url');
      await portalDio().post('/rooms', data: payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Room created.')));
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(dioErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _rooms.length,
        itemBuilder: (context, i) {
          final r = _rooms[i] as Map<String, dynamic>;
          final roomNo = (r['room_number'] ?? '').toString();
          final status = (r['status'] ?? '').toString();
          final guest = (r['current_guest_name'] ?? '').toString();
          final pwd = (r['room_access_password'] ?? '').toString();
          final id = (r['id'] ?? r['_id'] ?? '').toString();
          return Card(
            child: ListTile(
              leading: const Icon(Icons.meeting_room_outlined),
              title: Text('Room $roomNo'),
              subtitle: Text(
                [
                  if (status.isNotEmpty) 'Status: $status',
                  if (guest.isNotEmpty) 'Guest: $guest',
                  if (pwd.isNotEmpty) 'Password: $pwd',
                ].join(' · '),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => AdminRoomDetailScreen(roomId: id),
                  ),
                );
                await _load();
              },
            ),
          );
        },
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
    final roomId = (room?['id'] ?? widget.roomId).toString();
    final current = (room?['status'] ?? 'available').toString();
    String status = current;
    final chosen = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change room status'),
        content: DropdownButtonFormField<String>(
          initialValue: current,
          items: const [
            DropdownMenuItem(value: 'available', child: Text('available')),
            DropdownMenuItem(value: 'booked', child: Text('booked')),
            DropdownMenuItem(value: 'maintenance', child: Text('maintenance')),
            DropdownMenuItem(value: 'reserved', child: Text('reserved')),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Room details'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: const ThemeFab(),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final room = _data!['room'] as Map<String, dynamic>;
    final booking = _data!['active_booking'] as Map<String, dynamic>?;
    final charges = (_data!['booking_charges'] as List<dynamic>?) ?? const [];

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
              title: Text((booking['guest_name'] ?? '').toString()),
              subtitle: Text(
                [
                  'Phone: ${(booking['guest_phone'] ?? '').toString()}',
                  'Email: ${(booking['guest_email'] ?? '').toString()}',
                  'Ref: ${(booking['booking_reference'] ?? '').toString()}',
                ].where((s) => !s.endsWith(': ')).join('\n'),
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
