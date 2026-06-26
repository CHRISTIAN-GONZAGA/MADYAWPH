import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../dio_client.dart';
import '../widgets/app_state_views.dart';
import '../widgets/app_overlay.dart';
import '../widgets/chat_attachment.dart';
import 'admin/admin_dashboard_models.dart';
import 'admin/widgets/admin_dev_error_panel.dart';
import 'admin/widgets/admin_opaque_scaffold.dart';
import 'admin/widgets/admin_room_edit_screen.dart';
import 'admin/widgets/admin_room_editor.dart';
import 'admin/widgets/hourly_price_picker.dart';

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

  String _categoryId(Map<String, dynamic> category) =>
      AdminDashboardModels.normalizeRoomIdString(
        category['id'] ?? category['_id'],
      );

  String _roomId(Map<String, dynamic> room) =>
      AdminDashboardModels.roomIdOf(room);

  bool _roomBelongsToCategory(
    Map<String, dynamic> room,
    Map<String, dynamic> category,
  ) {
    final catId = _categoryId(category);
    final roomCatId = AdminDashboardModels.normalizeRoomIdString(
      room['category_id'] ?? room['categoryId'],
    );
    if (catId.isNotEmpty && roomCatId.isNotEmpty && roomCatId == catId) {
      return true;
    }
    final nested = room['category'];
    if (nested is Map) {
      final nestedId = AdminDashboardModels.normalizeRoomIdString(
        nested['id'] ?? nested['_id'],
      );
      if (catId.isNotEmpty && nestedId.isNotEmpty && nestedId == catId) {
        return true;
      }
    }
    final catName = (category['name'] ?? category['category_name'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final roomCatName =
        (room['category_name'] ?? '').toString().trim().toLowerCase();
    return catName.isNotEmpty && roomCatName == catName;
  }

  List<Map<String, dynamic>> _parseRoomRows(dynamic raw) {
    return (raw as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((e) => normalizeAdminRoomForEdit(Map<String, dynamic>.from(e)))
        .where((r) => _roomId(r).isNotEmpty)
        .toList();
  }

  Future<List<Map<String, dynamic>>> _roomsInCategory(
    Map<String, dynamic> category,
  ) async {
    final catId = _categoryId(category);
    final params =
        catId.isNotEmpty ? <String, dynamic>{'category_id': catId} : null;

    List<Map<String, dynamic>> filterRooms(List<Map<String, dynamic>> raw) {
      return raw
          .where((r) => _roomBelongsToCategory(r, category))
          .toList();
    }

    final res = await portalDio().get<Map<String, dynamic>>(
      '/admin/rooms',
      queryParameters: params,
    );
    final filtered = filterRooms(_parseRoomRows(res.data?['data']));
    if (filtered.isNotEmpty) return filtered;

    final fallback = await portalDio().get<Map<String, dynamic>>('/admin/rooms');
    return filterRooms(_parseRoomRows(fallback.data?['data']));
  }

  Future<Map<String, dynamic>?> _fetchRoomForEdit(String roomId) async {
    try {
      final res = await portalDio().get<Map<String, dynamic>>(
        '/admin/rooms/$roomId',
      );
      final data = res.data;
      if (data == null) return null;
      final raw = data['room'] is Map
          ? Map<String, dynamic>.from(data['room'] as Map)
          : Map<String, dynamic>.from(data);
      return normalizeAdminRoomForEdit(raw);
    } on DioException {
      return null;
    }
  }

  Future<void> _putMultipart(
    String path,
    Map<String, dynamic> fields,
    XFile? image,
  ) async {
    if (image != null) {
      final form = await ChatAttachment.formWithImage(
        fields: fields,
        file: image,
      );
      await portalDio().put(
        path,
        data: form,
        options: Options(
          contentType: 'multipart/form-data',
          headers: {Headers.acceptHeader: 'application/json'},
        ),
      );
    } else {
      final body = <String, dynamic>{};
      for (final entry in fields.entries) {
        final v = entry.value;
        if (v == null) continue;
        body[entry.key] = v is num || v is bool ? v.toString() : v;
      }
      await portalDio().put(path, data: body);
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
      await portalDio().post(
        path,
        data: form,
        options: Options(
          contentType: 'multipart/form-data',
          headers: {Headers.acceptHeader: 'application/json'},
        ),
      );
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
    final nightlyCtrl = TextEditingController(text: '0');
    final blockPriceCtrl = TextEditingController(text: '1000');
    var catBillingMode = 'hourly';
    var catPricePerNight = 0.0;
    var catPricePerBlock = 1000.0;
    var catBlockHours = 3;
    var catPricePerExtraHour = 0.0;
    var catFloorCount = 1;
    final floorCountCtrl = TextEditingController(text: '1');
    final extraHourPriceCtrl = TextEditingController(text: '0');
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
                    const SizedBox(height: 16),
                    TextField(
                      controller: floorCountCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Number of floors',
                        hintText: 'e.g. 3',
                        prefixIcon: Icon(Icons.layers_outlined),
                        helperText: 'Used when adding rooms to this building',
                      ),
                      onChanged: (v) {
                        final n = int.tryParse(v.trim());
                        if (n != null && n > 0) catFloorCount = n;
                      },
                    ),
                    const SizedBox(height: 16),
                    RoomPricingFields(
                      billingMode: catBillingMode,
                      pricePerNight: catPricePerNight,
                      pricePerBlock: catPricePerBlock,
                      blockHours: catBlockHours,
                      pricePerExtraHour: catPricePerExtraHour,
                      nightlyController: nightlyCtrl,
                      blockPriceController: blockPriceCtrl,
                      extraHourPriceController: extraHourPriceCtrl,
                      onChanged: ({
                        required String billingMode,
                        required double pricePerNight,
                        required double pricePerBlock,
                        required int blockHours,
                        required double pricePerExtraHour,
                      }) {
                        setLocal(() {
                          catBillingMode = billingMode;
                          catPricePerNight = pricePerNight;
                          catPricePerBlock = pricePerBlock;
                          catBlockHours = blockHours;
                          catPricePerExtraHour = pricePerExtraHour;
                        });
                      },
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
                            'billing_mode': catBillingMode,
                            'default_price': catBillingMode == 'nightly'
                                ? catPricePerNight
                                : catPricePerBlock,
                            'price_per_block': catPricePerBlock,
                            'block_hours': catBlockHours,
                            'price_per_extra_hour': catPricePerExtraHour,
                            'floor_count': int.tryParse(floorCountCtrl.text.trim()) ?? catFloorCount,
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
    if (_categoryId(category).isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Category id missing. Pull to refresh and try again.'),
        ),
      );
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final created = await showAdminCreateRoomDialog(
        context,
        category: category,
      );
      if (!mounted) return;
      if (created) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Room created.')),
        );
      }
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dioErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editCategory(Map<String, dynamic> category) async {
    final categoryId = _categoryId(category);
    if (categoryId.isEmpty) return;
    final nameCtrl = TextEditingController(text: (category['name'] ?? '').toString());
    final descCtrl = TextEditingController(text: (category['description'] ?? '').toString());
    final nightlyCtrl = TextEditingController(
      text: '${(category['default_price'] as num?)?.toDouble() ?? 0}',
    );
    final blockPriceCtrl = TextEditingController(
      text: '${(category['price_per_block'] as num?)?.toDouble() ?? 0}',
    );
    var catBillingMode = (category['billing_mode'] ?? 'nightly').toString();
    var catPricePerNight = (category['default_price'] as num?)?.toDouble() ?? 0.0;
    var catPricePerBlock = (category['price_per_block'] as num?)?.toDouble() ?? 0.0;
    var catBlockHours = (category['block_hours'] as num?)?.toInt() ?? 3;
    var catPricePerExtraHour =
        (category['price_per_extra_hour'] as num?)?.toDouble() ?? 0.0;
    var catFloorCount = (category['floor_count'] as num?)?.toInt() ?? 1;
    final floorCountCtrl = TextEditingController(text: '$catFloorCount');
    final extraHourPriceCtrl =
        TextEditingController(text: '$catPricePerExtraHour');
    XFile? pickedImage;

    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Edit category'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: floorCountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Number of floors',
                    prefixIcon: Icon(Icons.layers_outlined),
                  ),
                  onChanged: (v) {
                    final n = int.tryParse(v.trim());
                    if (n != null && n > 0) catFloorCount = n;
                  },
                ),
                const SizedBox(height: 12),
                RoomPricingFields(
                  billingMode: catBillingMode,
                  pricePerNight: catPricePerNight,
                  pricePerBlock: catPricePerBlock,
                  blockHours: catBlockHours,
                  pricePerExtraHour: catPricePerExtraHour,
                  nightlyController: nightlyCtrl,
                  blockPriceController: blockPriceCtrl,
                  extraHourPriceController: extraHourPriceCtrl,
                  onChanged: ({
                    required String billingMode,
                    required double pricePerNight,
                    required double pricePerBlock,
                    required int blockHours,
                    required double pricePerExtraHour,
                  }) {
                    setLocal(() {
                      catBillingMode = billingMode;
                      catPricePerNight = pricePerNight;
                      catPricePerBlock = pricePerBlock;
                      catBlockHours = blockHours;
                      catPricePerExtraHour = pricePerExtraHour;
                    });
                  },
                ),
                const SizedBox(height: 12),
                _galleryPickerTile(
                  image: pickedImage,
                  onPick: () async {
                    final file = await ChatAttachment.pickRoomImageFromGallery(context);
                    if (file != null) setLocal(() => pickedImage = file);
                  },
                  onClear: () => setLocal(() => pickedImage = null),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(context, {
                'name': nameCtrl.text.trim(),
                'description': descCtrl.text.trim(),
                'default_price': catPricePerNight,
                'billing_mode': catBillingMode,
                'price_per_block': catPricePerBlock,
                'block_hours': catBlockHours,
                'price_per_extra_hour': catPricePerExtraHour,
                'floor_count': int.tryParse(floorCountCtrl.text.trim()) ?? catFloorCount,
                '__image': pickedImage,
              }),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
    descCtrl.dispose();
    nightlyCtrl.dispose();
    blockPriceCtrl.dispose();
    if (payload == null) return;
    final image = payload.remove('__image') as XFile?;
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _putMultipart('/room-categories/$categoryId', payload, image);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Category updated.')),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dioErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editRoomInCategory(Map<String, dynamic> category) async {
    if (_busy) return;

    List<Map<String, dynamic>> rooms;
    setState(() => _busy = true);
    try {
      rooms = await _roomsInCategory(category);
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dioErrorMessage(e))),
      );
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }

    if (rooms.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No rooms in this category.')),
      );
      return;
    }

    Map<String, dynamic> room = rooms.first;
    final catName =
        (category['name'] ?? category['category_name'] ?? 'Category')
            .toString();
    if (rooms.length > 1) {
      if (!mounted) return;
      final picked = await showAdminRoomPickerSheet(
        context,
        categoryLabel: catName,
        rooms: rooms,
      );
      if (picked == null || !mounted) return;
      room = picked;
    }

    final roomId = _roomId(room);
    if (roomId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Room id missing. Pull to refresh and try again.'),
        ),
      );
      return;
    }

    try {
      final detailed = await _fetchRoomForEdit(roomId);
      final roomForEdit = normalizeAdminRoomForEdit(
        Map<String, dynamic>.from(detailed ?? room),
      );
      if (_roomId(roomForEdit).isEmpty) {
        roomForEdit['id'] = roomId;
      }

      if (!mounted) return;

      final saved = await showAdminEditRoomDialog(
        context,
        room: roomForEdit,
        categoryDefaults: category,
        categoryLabel: catName,
      );
      if (!mounted) return;
      if (saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Room updated.')),
        );
        await _load();
      }
    } catch (e, stack) {
      if (!mounted) return;
      await pushAdminFullScreen<void>(
        context,
        builder: (_) => AdminOpaqueScaffold(
          appBar: AppBar(title: const Text('Edit room failed')),
          body: AdminDevErrorPanel(
            title: 'Could not open room editor',
            message: AdminDevErrorPanel.formatError(e, stack),
            hint: 'Copy this error and share it with your developer.',
          ),
        ),
      );
    }
  }

  Future<void> _deleteRoomInCategory(Map<String, dynamic> category) async {
    try {
      final rooms = await _roomsInCategory(category);
      if (rooms.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No rooms found in this category.')),
        );
        return;
      }
      String selectedId = _roomId(rooms.first);
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: const Text('Delete room'),
            content: DropdownButtonFormField<String>(
              key: ValueKey<String>(selectedId),
              initialValue: selectedId.isEmpty ? null : selectedId,
              items: rooms
                  .where((r) => _roomId(r).isNotEmpty)
                  .map((r) {
                final id = _roomId(r);
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
    return AdminOpaqueScaffold(
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
    if (_loading) {
      return appScrollableLoading(onRefresh: _load);
    }
    if (_error != null) {
      return appScrollableError(message: _error!, onRetry: _load, onRefresh: _load);
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
                          leading: const Icon(Icons.edit_outlined),
                          title: const Text('Edit category'),
                          onTap: () => Navigator.of(context).pop('edit_cat'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.add_business_outlined),
                          title: const Text('Create room in this category'),
                          onTap: () => Navigator.of(context).pop('create_room'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.meeting_room_outlined),
                          title: const Text('Edit a room in this category'),
                          onTap: () => Navigator.of(context).pop('edit_room'),
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
                if (action == 'edit_cat') {
                  await _editCategory(c);
                  await _load();
                } else if (action == 'create_room') {
                  await _createRoomInCategory(c);
                  await _load();
                } else if (action == 'edit_room') {
                  await _editRoomInCategory(c);
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
