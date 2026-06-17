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
  List<dynamic> _rooms = const [];
  List<dynamic> _categories = const [];
  String? _error;
  bool _loading = true;
  bool _busy = false;

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

  Map<String, dynamic>? _categoryForRoom(Map<String, dynamic> room) {
    final categoryId = (room['category_id'] ?? '').toString();
    if (categoryId.isEmpty) return null;
    for (final raw in _categories) {
      final cat = raw as Map<String, dynamic>;
      final id = (cat['id'] ?? cat['_id'] ?? '').toString();
      if (id == categoryId) return cat;
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
      setState(() {
        _rooms = (roomsRes.data?['data'] as List<dynamic>?) ?? const [];
        _categories = (catData?['data'] as List?) ??
            (catData?['categories'] as List?) ??
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

  Future<void> _addRoom() async {
    if (_categories.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Create a room category first, then add rooms.'),
        ),
      );
      return;
    }

    Map<String, dynamic>? category;
    if (_categories.length == 1) {
      category = _categories.first as Map<String, dynamic>;
    } else {
      if (!mounted) return;
      category = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) {
          var selected = _categories.first as Map<String, dynamic>;
          return StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: const Text('Choose category'),
              content: DropdownButtonFormField<String>(
                key: ValueKey(
                  (selected['id'] ?? selected['_id'] ?? '').toString(),
                ),
                initialValue:
                    (selected['id'] ?? selected['_id'] ?? '').toString(),
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  for (final raw in _categories)
                    DropdownMenuItem(
                      value: (raw['id'] ?? raw['_id'] ?? '').toString(),
                      child: Text(
                        (raw['name'] ?? raw['category_name'] ?? 'Category')
                            .toString(),
                      ),
                    ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  final picked =
                      _categories.cast<Map<String, dynamic>>().firstWhere(
                            (c) =>
                                (c['id'] ?? c['_id'] ?? '').toString() == v,
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
              onPressed: _busy ? null : _addRoom,
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

    if (_rooms.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'No rooms yet. Add a category, then create your first room.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _addRoom,
                icon: const Icon(Icons.add),
                label: const Text('Add room'),
              ),
            ],
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
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 4),
            child: Text(
              'Tap a room to edit photo, rates, and details. Use the menu to manage an active stay.',
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
                        onEdit: () => _editRoom(r),
                        onManageStay: () => _manageStay(r),
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
    required this.onEdit,
    required this.onManageStay,
  });

  final Map<String, dynamic> room;
  final VoidCallback onEdit;
  final VoidCallback onManageStay;

  @override
  Widget build(BuildContext context) {
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
      margin: const EdgeInsets.only(top: 8),
      child: ListTile(
        leading: imageUrl.isEmpty
            ? CircleAvatar(
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.meeting_room_outlined),
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: NetworkMediaImage(
                  url: imageUrl,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  error: const Icon(Icons.broken_image_outlined, size: 22),
                ),
              ),
        title: Text('Room $roomNo'),
        subtitle: Text(
          subtitleParts.join(' · '),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (action) {
            if (action == 'edit') {
              onEdit();
            } else if (action == 'manage') {
              onManageStay();
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'edit',
              child: ListTile(
                leading: Icon(Icons.edit_outlined),
                title: Text('Edit room setup'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: 'manage',
              child: ListTile(
                leading: Icon(Icons.manage_accounts_outlined),
                title: Text('Manage stay'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
        onTap: onEdit,
      ),
    );
  }
}
