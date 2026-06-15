import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../dio_client.dart';
import '../widgets/app_state_views.dart';
import '../widgets/room_status_label.dart';
import 'admin/admin_dashboard_models.dart';
import 'admin/widgets/admin_opaque_scaffold.dart';
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
    return AdminOpaqueScaffold(
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
                          await AdminRoomNavigation.openRoom(
                            context,
                            room: r,
                            onSuccess: _load,
                          );
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
          extra.join(' Â· '),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onOpenDetail,
      ),
    );
  }
}
