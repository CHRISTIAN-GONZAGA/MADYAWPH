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
  String? _error;
  bool _loading = true;

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
    return Scaffold(
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
