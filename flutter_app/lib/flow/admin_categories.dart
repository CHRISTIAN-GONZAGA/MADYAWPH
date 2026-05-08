import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../dio_client.dart';
import '../widgets/theme_fab.dart';

class AdminCategoriesScreen extends StatefulWidget {
  const AdminCategoriesScreen({super.key});

  @override
  State<AdminCategoriesScreen> createState() => _AdminCategoriesScreenState();
}

class _AdminCategoriesScreenState extends State<AdminCategoriesScreen> {
  List<dynamic> _cats = const [];
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
      final res =
          await portalDio().get<Map<String, dynamic>>('/room-categories');
      final data = res.data;
      setState(() {
        _cats = (data?['data'] as List?) ??
            (data?['categories'] as List?) ??
            const [];
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

  Future<void> _create() async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final imgCtrl = TextEditingController();
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create category'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                  labelText: 'Name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                  labelText: 'Description', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: imgCtrl,
              decoration: const InputDecoration(
                  labelText: 'Category image URL',
                  border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop({
              'name': nameCtrl.text.trim(),
              'description': descCtrl.text.trim(),
              'image_url': imgCtrl.text.trim(),
            }),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (payload == null) return;
    if ((payload['name'] ?? '').toString().isEmpty) return;

    if (_busy) return;
    setState(() => _busy = true);
    try {
      await portalDio().post('/room-categories', data: payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Category created.')));
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(dioErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createRoomInCategory(Map<String, dynamic> category) async {
    final nameCtrl = TextEditingController();
    final roomNoCtrl = TextEditingController();
    final priceCtrl = TextEditingController(
        text: '${(category['default_price'] as num?)?.toDouble() ?? 0}');
    String roomType = 'Single';
    String status = 'available';
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('Create room in ${(category['name'] ?? 'category')}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Display name'),
                ),
                TextField(
                  controller: roomNoCtrl,
                  decoration: const InputDecoration(labelText: 'Room number'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: roomType,
                  items: const [
                    DropdownMenuItem(value: 'Single', child: Text('Single')),
                    DropdownMenuItem(value: 'Double', child: Text('Double')),
                    DropdownMenuItem(value: 'Suite', child: Text('Suite')),
                    DropdownMenuItem(value: 'Deluxe', child: Text('Deluxe')),
                  ],
                  onChanged: (v) => setLocal(() => roomType = v ?? roomType),
                ),
                TextField(
                  controller: priceCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Price per night'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  items: const [
                    DropdownMenuItem(value: 'available', child: Text('available')),
                    DropdownMenuItem(value: 'booked', child: Text('booked')),
                    DropdownMenuItem(
                        value: 'checked_in', child: Text('checked_in')),
                    DropdownMenuItem(
                        value: 'checked_out', child: Text('checked_out')),
                    DropdownMenuItem(
                        value: 'maintenance', child: Text('maintenance')),
                    DropdownMenuItem(value: 'reserved', child: Text('reserved')),
                  ],
                  onChanged: (v) => setLocal(() => status = v ?? status),
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
                'category_id': (category['id'] ?? '').toString(),
                'display_name': nameCtrl.text.trim(),
                'room_number': roomNoCtrl.text.trim(),
                'room_type': roomType,
                'price_per_night': double.tryParse(priceCtrl.text.trim()) ?? 0,
                'status': status,
              }),
              child: const Text('Create'),
            )
          ],
        ),
      ),
    );
    if (payload == null) return;
    try {
      await portalDio().post('/rooms', data: payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Room created.')));
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(dioErrorMessage(e))));
    }
  }

  Future<void> _deleteRoomInCategory(Map<String, dynamic> category) async {
    try {
      final res = await portalDio().get<Map<String, dynamic>>('/admin/rooms');
      final rooms = (res.data?['data'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .where((r) => (r['category_id'] ?? '').toString() ==
              (category['id'] ?? '').toString())
          .toList();
      if (rooms.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No rooms found in this category.')),
        );
        return;
      }
      String selectedId = (rooms.first['id'] ?? '').toString();
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: const Text('Delete room'),
            content: DropdownButtonFormField<String>(
              initialValue: selectedId,
              items: rooms.map((r) {
                final id = (r['id'] ?? '').toString();
                final no = (r['room_number'] ?? '').toString();
                return DropdownMenuItem(value: id, child: Text('Room $no'));
              }).toList(),
              onChanged: (v) => setLocal(() => selectedId = v ?? selectedId),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Delete')),
            ],
          ),
        ),
      );
      if (ok != true) return;
      await portalDio().delete('/rooms/$selectedId');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Room deleted.')));
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(dioErrorMessage(e))));
    }
  }

  Future<void> _deleteCategory(Map<String, dynamic> category) async {
    final categoryId = (category['id'] ?? '').toString();
    if (categoryId.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete category'),
        content: const Text(
            'This will also delete all rooms inside this category. Continue?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await portalDio().delete('/room-categories/$categoryId');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Category deleted.')));
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
        title: const Text('Room categories'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          IconButton(
              onPressed: _busy ? null : _create, icon: const Icon(Icons.add)),
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
        itemCount: _cats.length,
        itemBuilder: (context, i) {
          final c = _cats[i] as Map<String, dynamic>;
          final name =
              (c['name'] ?? c['category_name'] ?? 'Category').toString();
          final desc = (c['description'] ?? '').toString();
          final imageUrl = (c['image_url'] ?? '').toString();
          return Card(
            child: ListTile(
              leading: imageUrl.isEmpty
                  ? const Icon(Icons.category_outlined)
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        imageUrl,
                        width: 42,
                        height: 42,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.broken_image_outlined),
                      ),
                    ),
              title: Text(name),
              subtitle: desc.isEmpty ? null : Text(desc),
              onTap: () async {
                final action = await showModalBottomSheet<String>(
                  context: context,
                  builder: (context) => SafeArea(
                    child: Wrap(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.add_business_outlined),
                          title: const Text('Create room in this category'),
                          onTap: () => Navigator.of(context).pop('create_room'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.delete_outline),
                          title: const Text('Delete a room in this category'),
                          onTap: () => Navigator.of(context).pop('delete_room'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.delete_forever_outlined),
                          title: const Text('Delete this category'),
                          onTap: () => Navigator.of(context).pop('delete_cat'),
                        ),
                      ],
                    ),
                  ),
                );
                if (action == 'create_room') {
                  await _createRoomInCategory(c);
                  await _load();
                } else if (action == 'delete_room') {
                  await _deleteRoomInCategory(c);
                  await _load();
                } else if (action == 'delete_cat') {
                  await _deleteCategory(c);
                }
              },
            ),
          );
        },
      ),
    );
  }
}
