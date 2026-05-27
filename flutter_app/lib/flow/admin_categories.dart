import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../dio_client.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/app_state_views.dart';
import '../widgets/chat_attachment.dart';

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

  Future<void> _postMultipart(
    String path,
    Map<String, dynamic> fields,
    XFile? image,
  ) async {
    if (image != null) {
      final form = await ChatAttachment.formWithImage(
        fields: fields,
        file: image,
      );
      await portalDio().post(path, data: form);
    } else {
      final body = <String, dynamic>{};
      for (final entry in fields.entries) {
        final v = entry.value;
        if (v == null) continue;
        body[entry.key] = v is num || v is bool ? v.toString() : v;
      }
      await portalDio().post(path, data: body);
    }
  }

  Widget _galleryPickerTile({
    required XFile? image,
    required VoidCallback onPick,
    required VoidCallback onClear,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (image != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(image.path),
              height: 140,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          )
        else
          Container(
            height: 100,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Icon(
              Icons.add_photo_alternate_outlined,
              size: 40,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onPick,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Choose from gallery'),
              ),
            ),
            if (image != null) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Remove photo',
                onPressed: onClear,
                icon: const Icon(Icons.close),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Future<void> _create() async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    XFile? pickedImage;
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Create category',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: nameCtrl,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        prefixIcon: Icon(Icons.label_outline),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: descCtrl,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        alignLabelWithHint: true,
                        prefixIcon: Icon(Icons.notes_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _galleryPickerTile(
                      image: pickedImage,
                      onPick: () async {
                        final file =
                            await ChatAttachment.pickRoomImageFromGallery(context);
                        if (file != null) setLocal(() => pickedImage = file);
                      },
                      onClear: () => setLocal(() => pickedImage = null),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () => Navigator.of(context).pop({
                            'name': nameCtrl.text.trim(),
                            'description': descCtrl.text.trim(),
                            '__image': pickedImage,
                          }),
                          child: const Text('Create'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (payload == null) return;
    final image = payload.remove('__image') as XFile?;
    if ((payload['name'] ?? '').toString().isEmpty) return;

    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _postMultipart('/room-categories', payload, image);
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
    XFile? pickedImage;
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'New room · ${(category['name'] ?? 'category')}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: nameCtrl,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Display name',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: roomNoCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Room number',
                        prefixIcon: Icon(Icons.door_front_door_outlined),
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      key: ValueKey<String>(roomType),
                      initialValue: roomType,
                      decoration: const InputDecoration(
                        labelText: 'Room type',
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 'Single', child: Text('Single')),
                        DropdownMenuItem(
                            value: 'Double', child: Text('Double')),
                        DropdownMenuItem(
                            value: 'Suite', child: Text('Suite')),
                        DropdownMenuItem(
                            value: 'Deluxe', child: Text('Deluxe')),
                      ],
                      onChanged: (v) =>
                          setLocal(() => roomType = v ?? roomType),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: priceCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Price per night (PHP)',
                        prefixIcon: Icon(Icons.payments_outlined),
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      key: ValueKey<String>(status),
                      initialValue: status,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 'available', child: Text('available')),
                        DropdownMenuItem(
                            value: 'booked', child: Text('booked')),
                        DropdownMenuItem(
                            value: 'checked_in', child: Text('checked_in')),
                        DropdownMenuItem(
                            value: 'checked_out', child: Text('checked_out')),
                        DropdownMenuItem(
                            value: 'maintenance', child: Text('maintenance')),
                        DropdownMenuItem(
                            value: 'reserved', child: Text('reserved')),
                      ],
                      onChanged: (v) => setLocal(() => status = v ?? status),
                    ),
                    const SizedBox(height: 14),
                    _galleryPickerTile(
                      image: pickedImage,
                      onPick: () async {
                        final file =
                            await ChatAttachment.pickRoomImageFromGallery(context);
                        if (file != null) setLocal(() => pickedImage = file);
                      },
                      onClear: () => setLocal(() => pickedImage = null),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () => Navigator.of(context).pop({
                            'category_id': (category['id'] ?? '').toString(),
                            'display_name': nameCtrl.text.trim(),
                            'room_number': roomNoCtrl.text.trim(),
                            'room_type': roomType,
                            'price_per_night':
                                double.tryParse(priceCtrl.text.trim()) ?? 0,
                            'status': status,
                            '__image': pickedImage,
                          }),
                          child: const Text('Create'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (payload == null) return;
    final image = payload.remove('__image') as XFile?;
    try {
      await _postMultipart('/rooms', payload, image);
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
      if (!mounted) return;
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
    return AppScaffold(
      appBar: AppBar(
        title: const Text('Room categories'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          IconButton(
              onPressed: _busy ? null : _create, icon: const Icon(Icons.add)),
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
                  : NetworkMediaImage(
                      url: imageUrl,
                      width: 42,
                      height: 42,
                      borderRadius: BorderRadius.circular(8),
                      error: const Icon(Icons.broken_image_outlined),
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
