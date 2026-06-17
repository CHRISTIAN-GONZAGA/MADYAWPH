import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../dio_client.dart';
import '../widgets/app_state_views.dart';
import '../widgets/chat_attachment.dart';
import '../widgets/room_status_label.dart';
import 'admin/widgets/admin_opaque_scaffold.dart';
import 'admin/widgets/admin_room_editor.dart';
import 'admin/widgets/admin_room_navigation.dart';
import 'admin_categories.dart';

export 'admin/admin_room_detail_screen.dart';

class AdminRoomsScreen extends StatefulWidget {
  const AdminRoomsScreen({super.key});

  @override
  State<AdminRoomsScreen> createState() => _AdminRoomsScreenState();
}

class _AdminRoomsScreenState extends State<AdminRoomsScreen> {
  List<Map<String, dynamic>> _rooms = const [];
  List<Map<String, dynamic>> _categories = const [];
  String? _error;
  bool _loading = true;
  bool _busy = false;

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

  String _categoryId(Map<String, dynamic> category) =>
      (category['id'] ?? category['_id'] ?? '').toString().trim();

  String _categoryName(Map<String, dynamic> category) =>
      (category['name'] ?? category['category_name'] ?? 'Category')
          .toString()
          .trim();

  List<Map<String, dynamic>> _parseRooms(List<dynamic> raw) {
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((r) => (r['id'] ?? r['_id'] ?? '').toString().isNotEmpty)
        .toList();
  }

  List<Map<String, dynamic>> _parseCategories(List<dynamic> raw) {
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((c) => _categoryId(c).isNotEmpty)
        .toList();
  }

  /// Groups rooms under category ids from the categories API.
  List<({String id, String name, List<Map<String, dynamic>> rooms})>
      _roomSections() {
    final byCategory = <String, List<Map<String, dynamic>>>{};
    for (final cat in _categories) {
      byCategory[_categoryId(cat)] = [];
    }

    final uncategorized = <Map<String, dynamic>>[];
    for (final room in _rooms) {
      final categoryId = (room['category_id'] ?? '').toString().trim();
      if (categoryId.isNotEmpty && byCategory.containsKey(categoryId)) {
        byCategory[categoryId]!.add(room);
      } else {
        uncategorized.add(room);
      }
    }

    final sections = <({String id, String name, List<Map<String, dynamic>> rooms})>[];
    for (final cat in _categories) {
      final id = _categoryId(cat);
      final rooms = List<Map<String, dynamic>>.from(byCategory[id] ?? const [])
        ..sort(_compareRoomNumber);
      sections.add((id: id, name: _categoryName(cat), rooms: rooms));
    }

    if (uncategorized.isNotEmpty) {
      uncategorized.sort(_compareRoomNumber);
      sections.add((
        id: '_uncategorized',
        name: 'Uncategorized',
        rooms: uncategorized,
      ));
    }

    if (sections.isEmpty && _rooms.isNotEmpty) {
      final all = List<Map<String, dynamic>>.from(_rooms)
        ..sort(_compareRoomNumber);
      sections.add((id: '_all', name: 'All rooms', rooms: all));
    }

    return sections;
  }

  Map<String, dynamic>? _categoryForRoom(Map<String, dynamic> room) {
    final categoryId = (room['category_id'] ?? '').toString();
    if (categoryId.isEmpty) return null;
    for (final cat in _categories) {
      if (_categoryId(cat) == categoryId) return cat;
    }
    return null;
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
      final results = await Future.wait([
        portalDio().get<Map<String, dynamic>>('/admin/rooms'),
        portalDio().get<Map<String, dynamic>>('/room-categories'),
      ]);
      final roomsRes = results[0];
      final catsRes = results[1];
      final catData = catsRes.data;
      final rawRooms = (roomsRes.data?['data'] as List<dynamic>?) ?? const [];
      final rawCats = (catData?['data'] as List?) ??
          (catData?['categories'] as List?) ??
          const [];
      setState(() {
        _rooms = _parseRooms(rawRooms);
        _categories = _parseCategories(rawCats);
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

  Future<void> _editRoom(Map<String, dynamic> room) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final saved = await showAdminEditRoomDialog(
        context,
        room: room,
        categoryDefaults: _categoryForRoom(room),
      );
      if (!mounted) return;
      if (saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Room updated.')),
        );
        await _load();
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

  Future<void> _manageStay(Map<String, dynamic> room) async {
    await AdminRoomNavigation.openRoom(
      context,
      room: room,
      onSuccess: _load,
      mode: AdminRoomOpenMode.manageOnly,
    );
  }

  Future<void> _addRoom({Map<String, dynamic>? preselectedCategory}) async {
    if (_categories.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Create a room category first, then add rooms.'),
        ),
      );
      return;
    }

    Map<String, dynamic>? category = preselectedCategory;
    if (category == null) {
      if (_categories.length == 1) {
        category = _categories.first;
      } else {
        if (!mounted) return;
        category = await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (context) {
            var selected = _categories.first;
            return StatefulBuilder(
              builder: (context, setLocal) => AlertDialog(
                title: const Text('Choose category'),
                content: DropdownButtonFormField<String>(
                  key: ValueKey(_categoryId(selected)),
                  initialValue: _categoryId(selected),
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    for (final cat in _categories)
                      DropdownMenuItem(
                        value: _categoryId(cat),
                        child: Text(_categoryName(cat)),
                      ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    final picked = _categories.firstWhere(
                      (c) => _categoryId(c) == v,
                      orElse: () => selected,
                    );
                    setLocal(() => selected = picked);
                  },
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, selected),
                    child: const Text('Continue'),
                  ),
                ],
              ),
            );
          },
        );
      }
    }

    if (category == null || !mounted) return;
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
        await _load();
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

  @override
  Widget build(BuildContext context) {
    return AdminOpaqueScaffold(
      appBar: AppBar(
        title: const Text('Rooms & status'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          IconButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const AdminCategoriesScreen(),
              ),
            ),
            icon: const Icon(Icons.category_outlined),
            tooltip: 'Manage categories',
          ),
        ],
      ),
      floatingActionButton: _loading
          ? null
          : FloatingActionButton.extended(
              onPressed: _busy ? null : () => _addRoom(),
              icon: const Icon(Icons.add),
              label: const Text('Add room'),
            ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const AppLoadingView();
    if (_error != null) {
      return AppErrorView(message: _error!, onRetry: _load);
    }

    final sections = _roomSections();
    final hasAnyRooms = _rooms.isNotEmpty;

    if (!hasAnyRooms) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _categories.isEmpty
                    ? 'Create a room category first, then add your first room.'
                    : 'No rooms yet. Add a room to your categories.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : () => _addRoom(),
                icon: const Icon(Icons.add),
                label: const Text('Add room'),
              ),
            ],
          ),
        ),
      );
    }

    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12, left: 4, right: 4),
            child: Text(
              'Tap Edit on a room to change its photo, rates, and details.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final section in sections) ...[
            _CategoryHeader(
              name: section.name,
              roomCount: section.rooms.length,
              onAddRoom: section.id == '_uncategorized' || section.id == '_all'
                  ? null
                  : () => _addRoom(
                        preselectedCategory: _categories.firstWhere(
                          (c) => _categoryId(c) == section.id,
                          orElse: () => _categories.first,
                        ),
                      ),
            ),
            if (section.rooms.isEmpty)
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No rooms in this category yet.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              for (final room in section.rooms)
                _AdminRoomRow(
                  room: room,
                  onEdit: () => _editRoom(room),
                  onManageStay: () => _manageStay(room),
                ),
          ],
        ],
      ),
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({
    required this.name,
    required this.roomCount,
    this.onAddRoom,
  });

  final String name;
  final int roomCount;
  final VoidCallback? onAddRoom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Row(
        children: [
          Icon(Icons.folder_outlined, color: theme.colorScheme.primary, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '$roomCount room${roomCount == 1 ? '' : 's'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (onAddRoom != null)
            TextButton.icon(
              onPressed: onAddRoom,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
            ),
        ],
      ),
    );
  }
}

class _AdminRoomRow extends StatelessWidget {
  const _AdminRoomRow({
    required this.room,
    required this.onEdit,
    required this.onManageStay,
  });

  final Map<String, dynamic> room;
  final VoidCallback onEdit;
  final VoidCallback onManageStay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roomNo = (room['room_number'] ?? '').toString();
    final status = (room['status'] ?? '').toString();
    final guest = (room['current_guest_name'] ?? '').toString();
    final displayName = (room['display_name'] ?? '').toString().trim();
    final imageUrl = (room['image_url'] ?? '').toString().trim();
    final rate = adminRoomRateLabel(room);

    final subtitleParts = <String>[
      rate,
      if (status.isNotEmpty) roomStatusLabel(status),
      if (displayName.isNotEmpty) displayName,
      if (guest.isNotEmpty) 'Guest: $guest',
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: theme.colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _RoomThumbnail(imageUrl: imageUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      roomNo.isEmpty ? 'Room' : 'Room $roomNo',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitleParts.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitleParts.join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Edit room',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
              PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: (action) {
                  if (action == 'edit') {
                    onEdit();
                  } else if (action == 'manage') {
                    onManageStay();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 20),
                        SizedBox(width: 12),
                        Text('Edit room setup'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'manage',
                    child: Row(
                      children: [
                        Icon(Icons.manage_accounts_outlined, size: 20),
                        SizedBox(width: 12),
                        Text('Manage stay'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomThumbnail extends StatelessWidget {
  const _RoomThumbnail({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (imageUrl.isEmpty) {
      return CircleAvatar(
        radius: 24,
        backgroundColor: scheme.surfaceContainerHighest,
        child: Icon(Icons.meeting_room_outlined, color: scheme.primary),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 48,
        height: 48,
        child: NetworkMediaImage(
          url: imageUrl,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          error: ColoredBox(
            color: scheme.surfaceContainerHighest,
            child: Icon(Icons.broken_image_outlined, color: scheme.outline),
          ),
        ),
      ),
    );
  }
}
