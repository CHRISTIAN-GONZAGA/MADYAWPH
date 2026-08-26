import 'package:dio/dio.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';
import 'package:flutter/material.dart';

import '../../../dio_client.dart';
import '../admin_dashboard_models.dart';
import '../widgets/admin_room_navigation.dart';
import '../widgets/admin_sales_panel.dart';
import '../widgets/amenity_charges_panel.dart';
import '../widgets/charge_amenity_to_room_dialog.dart';
import '../../../utils/money_format.dart';

class AmenitiesSection extends StatefulWidget {
  const AmenitiesSection({
    super.key,
    required this.claims,
    required this.onAddProduct,
    required this.onRefresh,
    this.canManageProducts = true,
    this.isFrontDesk = false,
    this.rooms = const [],
    this.categories = const [],
  });

  final List<dynamic> claims;
  final Future<void> Function() onAddProduct;
  final Future<void> Function() onRefresh;
  final bool canManageProducts;
  final bool isFrontDesk;
  final List<Map<String, dynamic>> rooms;
  final List<Map<String, dynamic>> categories;

  @override
  State<AmenitiesSection> createState() => _AmenitiesSectionState();
}

class _AmenitiesSectionState extends State<AmenitiesSection> {
  List<dynamic> _menu = const [];
  bool _loadingMenu = true;
  String? _filterType;

  @override
  void initState() {
    super.initState();
    _loadMenu();
  }

  Future<void> _loadMenu() async {
    setState(() => _loadingMenu = true);
    try {
      final res =
          await portalDio().get<Map<String, dynamic>>('/admin/amenity-menu');
      if (!mounted) return;
      setState(() {
        _menu = (res.data?['data'] as List?) ?? (res.data as List?) ?? const [];
        _loadingMenu = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _loadingMenu = false);
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  List<Map<String, dynamic>> get _filteredMenu {
    return _menu.whereType<Map<String, dynamic>>().where((m) {
      final status = (m['approval_status'] ?? m['approvalStatus'] ?? 'approved')
          .toString()
          .toLowerCase();
      if (status == 'rejected' && !widget.canManageProducts) return false;
      if (_filterType == null) return true;
      final t = (m['amenity_type'] ?? m['type'] ?? '').toString();
      return t == _filterType;
    }).toList();
  }

  List<Map<String, dynamic>> get _pendingProducts {
    return _menu.whereType<Map<String, dynamic>>().where(_isPending).toList();
  }

  bool _isPending(Map<String, dynamic> item) {
    return (item['approval_status'] ?? item['approvalStatus'] ?? '')
            .toString()
            .toLowerCase() ==
        'pending';
  }

  bool _isBreakfastProduct(Map<String, dynamic> item) {
    if (item['is_breakfast'] == true || item['isBreakfast'] == true) {
      return true;
    }
    final type =
        (item['amenity_type'] ?? item['type'] ?? '').toString().toLowerCase();
    final name = (item['name'] ?? '').toString().toLowerCase();
    return type.contains('breakfast') || name.contains('breakfast');
  }

  Set<String> get _types {
    return _menu
        .whereType<Map<String, dynamic>>()
        .map((m) => (m['amenity_type'] ?? m['type'] ?? 'Other').toString())
        .toSet();
  }

  Future<void> _fulfillClaim(String id) async {
    try {
      await portalDio().patch('/admin/amenity-claims/$id/fulfill');
      await widget.onRefresh();
      await _loadMenu();
      if (!mounted) return;
      showAppMessage(context, 'Request marked fulfilled.');
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  Future<void> _onProductTap(Map<String, dynamic> item) async {
    final id = AdminDashboardModels.documentIdOf(item);
    if (id.isEmpty) {
      await showAppMessage(
        context,
        'Product has no ID in menu data (raw id: ${item['id']}, _id: ${item['_id']}). Pull to refresh or re-save the product.',
        isError: true,
        title: 'Cannot charge product',
      );
      return;
    }

    if (_isPending(item)) {
      if (!widget.canManageProducts) {
        showAppMessage(
          context,
          'This item is waiting for admin or super admin approval.',
        );
        return;
      }
      await _reviewPendingProduct(item);
      return;
    }

    final available = item['is_active'] != false;

    final action = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                (item['name'] ?? 'Product').toString(),
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                available
                    ? 'Available — can be charged to rooms'
                    : 'Unavailable — cannot be charged to rooms',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: available
                          ? Colors.green.shade700
                          : Theme.of(ctx).colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: available
                    ? () => Navigator.pop(ctx, 'charge')
                    : null,
                icon: const Icon(Icons.hotel_outlined),
                label: Text(
                  available
                      ? 'Charge to room'
                      : 'Unavailable to charge',
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(
                  ctx,
                  available ? 'mark_unavailable' : 'mark_available',
                ),
                icon: Icon(
                  available
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                label: Text(
                  available
                      ? 'Mark as unavailable'
                      : 'Mark as available',
                ),
              ),
              if (widget.canManageProducts) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(ctx, 'edit'),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit product'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(ctx, 'delete'),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete product'),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (!mounted || action == null) return;
    switch (action) {
      case 'charge':
        if (!available) {
          showAppMessage(
            context,
            'This product is unavailable and cannot be charged to a room.',
            isError: true,
          );
          return;
        }
        try {
          final charged = await showChargeAmenityToRoomDialog(
            context: context,
            menuItem: item,
            rooms: widget.rooms,
            categories: widget.categories,
          );
          if (charged) {
            await widget.onRefresh();
            await _loadMenu();
          }
        } catch (e, st) {
          if (!mounted) return;
          await showAppMessage(
            context,
            'Charge to room crashed: $e\n$st',
            isError: true,
            title: 'Developer error',
          );
        }
        break;
      case 'mark_unavailable':
        await _setAvailability(item, available: false);
        break;
      case 'mark_available':
        await _setAvailability(item, available: true);
        break;
      case 'edit':
        await _editItem(item);
        break;
      case 'delete':
        await _deleteItem(item);
        break;
    }
  }

  Future<void> _reviewPendingProduct(Map<String, dynamic> item) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                (item['name'] ?? 'Product').toString(),
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Requested by ${item['requested_by_name'] ?? 'front desk'}. '
                'Approve to add this to the amenity menu.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, 'approve'),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Approve product'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(ctx, 'reject'),
                icon: const Icon(Icons.close_rounded),
                label: const Text('Reject'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'approve') await _approveItem(item);
    if (action == 'reject') await _rejectItem(item);
  }

  Future<void> _approveItem(Map<String, dynamic> item) async {
    final id = AdminDashboardModels.documentIdOf(item);
    if (id.isEmpty) return;
    try {
      final res = await portalDio().patch<Map<String, dynamic>>(
        '/admin/amenity-menu/$id/approve',
      );
      await _loadMenu();
      await widget.onRefresh();
      if (!mounted) return;
      showAppMessage(
        context,
        (res.data?['message'] ?? 'Product approved.').toString(),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  Future<void> _rejectItem(Map<String, dynamic> item) async {
    final id = AdminDashboardModels.documentIdOf(item);
    if (id.isEmpty) return;
    try {
      final res = await portalDio().patch<Map<String, dynamic>>(
        '/admin/amenity-menu/$id/reject',
      );
      await _loadMenu();
      await widget.onRefresh();
      if (!mounted) return;
      showAppMessage(
        context,
        (res.data?['message'] ?? 'Product rejected.').toString(),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  Future<void> _showAddProductDialog() async {
    final typeCtrl = TextEditingController(text: 'Breakfast');
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController(text: '0');
    var isBreakfast = true;
    var active = true;

    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(
            widget.isFrontDesk ? 'Request amenity product' : 'Add amenity product',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.isFrontDesk)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Admin or super admin must approve this in Amenities before guests can claim it.',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  ),
                TextField(
                  controller: typeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Category / type',
                    hintText: 'e.g. Breakfast, Laundry',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Item name'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: priceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Price (PHP)'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: isBreakfast,
                  onChanged: (v) => setLocal(() {
                    isBreakfast = v;
                    if (v && typeCtrl.text.trim().isEmpty) {
                      typeCtrl.text = 'Breakfast';
                    }
                  }),
                  title: const Text('Breakfast meal'),
                  subtitle: const Text(
                    'Guests can claim this as complimentary breakfast when eligible',
                  ),
                ),
                if (!widget.isFrontDesk)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: active,
                    onChanged: (v) => setLocal(() => active = v),
                    title: const Text('Available now'),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(ctx, {
                  'amenity_type': typeCtrl.text.trim().isEmpty
                      ? (isBreakfast ? 'Breakfast' : 'Other')
                      : typeCtrl.text.trim(),
                  'name': name,
                  'price': double.tryParse(priceCtrl.text.trim()) ?? 0,
                  'is_active': widget.isFrontDesk ? false : active,
                  'is_breakfast': isBreakfast,
                });
              },
              child: Text(widget.isFrontDesk ? 'Submit request' : 'Create'),
            ),
          ],
        ),
      ),
    );
    if (payload == null) return;
    try {
      final res = await portalDio().post<Map<String, dynamic>>(
        '/admin/amenity-menu',
        data: payload,
      );
      await _loadMenu();
      await widget.onRefresh();
      if (!mounted) return;
      showAppMessage(
        context,
        (res.data?['message'] ?? 'Amenity menu item created.').toString(),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  Future<void> _setAvailability(
    Map<String, dynamic> item, {
    required bool available,
  }) async {
    final id = AdminDashboardModels.documentIdOf(item);
    if (id.isEmpty) return;
    try {
      final res = await portalDio().patch<Map<String, dynamic>>(
        '/admin/amenity-menu/$id/availability',
        data: {'is_active': available},
      );
      await _loadMenu();
      if (!mounted) return;
      showAppMessage(
        context,
        (res.data?['message'] ??
                (available
                    ? 'Product is available.'
                    : 'Product marked unavailable.'))
            .toString(),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  Future<void> _editItem(Map<String, dynamic> item) async {
    final id = (item['id'] ?? item['_id'] ?? '').toString();
    if (id.isEmpty) return;

    final typeCtrl = TextEditingController(
      text: (item['amenity_type'] ?? item['type'] ?? '').toString(),
    );
    final nameCtrl = TextEditingController(text: (item['name'] ?? '').toString());
    final priceCtrl =
        TextEditingController(text: '${item['price'] ?? 0}');
    var active = item['is_active'] != false;
    var isBreakfast = _isBreakfastProduct(item);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Edit product'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: typeCtrl,
                  decoration: const InputDecoration(labelText: 'Category'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: priceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Price (PHP)'),
                ),
                SwitchListTile(
                  value: isBreakfast,
                  onChanged: (v) => setLocal(() => isBreakfast = v),
                  title: const Text('Breakfast meal'),
                ),
                SwitchListTile(
                  value: active,
                  onChanged: (v) => setLocal(() => active = v),
                  title: const Text('Available to charge'),
                  subtitle: const Text(
                    'Turn off to mark this product unavailable for room charges',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    try {
      await portalDio().put('/admin/amenity-menu/$id', data: {
        'amenity_type': typeCtrl.text.trim(),
        'name': nameCtrl.text.trim(),
        'price': double.tryParse(priceCtrl.text.trim()) ?? 0,
        'is_active': active,
        'is_breakfast': isBreakfast,
      });
      await _loadMenu();
      if (!mounted) return;
      showAppMessage(context, 'Product updated.');
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  Future<void> _deleteItem(Map<String, dynamic> item) async {
    final id = (item['id'] ?? item['_id'] ?? '').toString();
    if (id.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete product?'),
        content: Text('Remove "${item['name']}" from the menu?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await portalDio().delete('/admin/amenity-menu/$id');
      await _loadMenu();
      if (!mounted) return;
      showAppMessage(context, 'Product removed.');
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  Widget _categoryChips() {
    final types = _types.toList()..sort();
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        FilterChip(
          label: const Text('All'),
          selected: _filterType == null,
          onSelected: (_) => setState(() => _filterType = null),
        ),
        ...types.map(
          (t) => FilterChip(
            label: Text(t),
            selected: _filterType == t,
            onSelected: (_) => setState(() => _filterType = t),
          ),
        ),
      ],
    );
  }

  Widget _productGrid() {
    if (_loadingMenu) {
      return const Center(child: CircularProgressIndicator());
    }
    final items = _filteredMenu;
    if (items.isEmpty) {
      return const Center(child: Text('No products in this category.'));
    }
    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.05,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final m = items[i];
        final active = m['is_active'] != false;
        final pending = _isPending(m);
        return Card(
          color: pending
              ? Colors.orange.shade50
              : active
                  ? null
                  : Colors.grey.shade100,
          child: InkWell(
            onTap: () => _onProductTap(m),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          (m['name'] ?? '').toString(),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: active ? null : Colors.grey.shade700,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'edit') {
                            _editItem(m);
                          } else if (v == 'delete') {
                            _deleteItem(m);
                          } else if (v == 'unavailable') {
                            _setAvailability(m, available: false);
                          } else if (v == 'available') {
                            _setAvailability(m, available: true);
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: active ? 'unavailable' : 'available',
                            child: Text(
                              active
                                  ? 'Mark unavailable'
                                  : 'Mark available',
                            ),
                          ),
                          if (widget.canManageProducts) ...[
                            const PopupMenuItem(
                              value: 'edit',
                              child: Text('Edit'),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete'),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  Text(
                    (m['amenity_type'] ?? m['type'] ?? '').toString(),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Spacer(),
                  Text(
                    formatMoney(parseJsonDouble(m['price'])),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    pending
                        ? 'Pending approval'
                        : active
                            ? (_isBreakfastProduct(m)
                                ? 'Breakfast · Available'
                                : 'Available')
                            : 'Unavailable',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: pending
                          ? Colors.orange.shade800
                          : active
                              ? Colors.green.shade700
                              : Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showBreakfastClaimsSheet({required bool fulfilled}) {
    final claims = AdminDashboardModels.breakfastClaims(
      widget.claims,
      fulfilled: fulfilled,
    );
    final title = fulfilled ? 'Breakfast prepared' : 'Breakfast to prepare';
    final scheme = Theme.of(context).colorScheme;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                Text(
                  fulfilled
                      ? 'Fulfilled breakfast requests from guests.'
                      : 'Pending breakfast requests waiting for prep.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                if (claims.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      fulfilled
                          ? 'No fulfilled breakfast requests yet.'
                          : 'Nothing to prepare right now.',
                      textAlign: TextAlign.center,
                      style: Theme.of(ctx).textTheme.bodyMedium,
                    ),
                  )
                else
                  SizedBox(
                    height: (claims.length * 88.0).clamp(120, 420),
                    child: ListView.separated(
                      itemCount: claims.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final c = claims[i];
                        final id = (c['id'] ?? c['_id'] ?? '').toString();
                        final status = (c['status'] ?? 'pending').toString();
                        final isDone = status == 'fulfilled';
                        return Card(
                          child: ListTile(
                            leading: Icon(
                              isDone
                                  ? Icons.check_circle_outline
                                  : Icons.free_breakfast_outlined,
                              color: isDone
                                  ? Colors.green.shade700
                                  : scheme.primary,
                            ),
                            title: Text(
                              (c['amenityName'] ??
                                      c['amenity_name'] ??
                                      'Breakfast')
                                  .toString(),
                            ),
                            subtitle: Text(
                              'Room ${c['roomNumber'] ?? c['room_number'] ?? '—'} · '
                              'Qty ${c['quantity'] ?? 1} · $status',
                            ),
                            trailing: isDone
                                ? null
                                : FilledButton(
                                    onPressed: id.isEmpty
                                        ? null
                                        : () async {
                                            await _fulfillClaim(id);
                                            if (ctx.mounted) {
                                              Navigator.pop(ctx);
                                            }
                                          },
                                    child: const Text('Mark done'),
                                  ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _breakfastPrepSummary() {
    final summary = AdminDashboardModels.breakfastPrepSummary(widget.claims);
    final toPrepare = summary['to_prepare'] ?? 0;
    final done = summary['done'] ?? 0;
    final pendingOrders = summary['pending_orders'] ?? 0;
    final fulfilledOrders = summary['fulfilled_orders'] ?? 0;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      color: scheme.primaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.free_breakfast_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Breakfast prep',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _BreakfastPrepStat(
                    label: 'To prepare',
                    count: toPrepare,
                    subtitle: pendingOrders == 1
                        ? '1 request'
                        : '$pendingOrders requests',
                    color: Colors.orange.shade800,
                    icon: Icons.pending_actions_outlined,
                    onTap: () => _showBreakfastClaimsSheet(fulfilled: false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _BreakfastPrepStat(
                    label: 'Done',
                    count: done,
                    subtitle: fulfilledOrders == 1
                        ? '1 fulfilled'
                        : '$fulfilledOrders fulfilled',
                    color: Colors.green.shade700,
                    icon: Icons.check_circle_outline,
                    onTap: () => _showBreakfastClaimsSheet(fulfilled: true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pendingProductRequests() {
    final pending = _pendingProducts;
    if (pending.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Card(
        color: Colors.orange.shade50,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.canManageProducts
                    ? 'Front desk product requests'
                    : 'Waiting for admin approval',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Colors.orange.shade900,
                    ),
              ),
              const SizedBox(height: 6),
              ...pending.map((item) {
                final name = (item['name'] ?? 'Item').toString();
                final by = (item['requested_by_name'] ?? 'Front desk').toString();
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.free_breakfast_outlined,
                    color: scheme.primary,
                  ),
                  title: Text(name),
                  subtitle: Text(
                    _isBreakfastProduct(item)
                        ? 'Breakfast · from $by'
                        : 'From $by',
                  ),
                  trailing: widget.canManageProducts
                      ? Wrap(
                          spacing: 4,
                          children: [
                            TextButton(
                              onPressed: () => _rejectItem(item),
                              child: const Text('Reject'),
                            ),
                            FilledButton(
                              onPressed: () => _approveItem(item),
                              child: const Text('Approve'),
                            ),
                          ],
                        )
                      : Text(
                          'Pending',
                          style: TextStyle(
                            color: Colors.orange.shade800,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _claimsList() {
    final claims = widget.claims.whereType<Map<String, dynamic>>().toList();
    if (claims.isEmpty) {
      return const Center(child: Text('No guest amenity requests yet.'));
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(8),
      itemCount: claims.length,
      itemBuilder: (context, i) {
        final c = claims[i];
        final id = (c['id'] ?? c['_id'] ?? '').toString();
        final status = (c['status'] ?? 'pending').toString();
        final fulfilled = status == 'fulfilled';
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text(
              '${c['amenityName'] ?? c['amenity_name'] ?? 'Item'}',
            ),
            subtitle: Text(
              'Room ${c['roomNumber'] ?? c['room_number']} · '
              'Qty ${c['quantity'] ?? 1} · $status',
            ),
            isThreeLine: true,
            trailing: fulfilled
                ? const Icon(Icons.check_circle, color: Colors.green)
                : FilledButton(
                    onPressed: id.isEmpty ? null : () => _fulfillClaim(id),
                    child: const Text('Fulfill'),
                  ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final header = Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Amenities marketplace',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              FilledButton.icon(
                onPressed: () async {
                  await _showAddProductDialog();
                },
                icon: const Icon(Icons.add, size: 18),
                label: Text(widget.isFrontDesk ? 'Request product' : 'Add product'),
              ),
            ],
          ),
        );

        if (wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              _breakfastPrepSummary(),
              _pendingProductRequests(),
              const Expanded(
                flex: 2,
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: AdminSalesPanel(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _categoryChips(),
              ),
              Expanded(
                flex: 3,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 3, child: _productGrid()),
                    const VerticalDivider(width: 1),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              'Guest requests',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          Expanded(child: _claimsList()),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        return DefaultTabController(
          length: 4,
          child: Column(
            children: [
              header,
              _breakfastPrepSummary(),
              _pendingProductRequests(),
              const TabBar(
                tabs: [
                  Tab(text: 'Sales'),
                  Tab(text: 'Products'),
                  Tab(text: 'Requests'),
                  Tab(text: 'Charges'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(12),
                      children: const [AdminSalesPanel()],
                    ),
                    Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _categoryChips(),
                        ),
                        Expanded(child: _productGrid()),
                      ],
                    ),
                    _claimsList(),
                    AmenityChargesPanel(
                      isFrontDesk: widget.isFrontDesk,
                      onChanged: widget.onRefresh,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BreakfastPrepStat extends StatelessWidget {
  const _BreakfastPrepStat({
    required this.label,
    required this.count,
    required this.subtitle,
    required this.color,
    required this.icon,
    this.onTap,
  });

  final String label;
  final int count;
  final String subtitle;
  final Color color;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                    ),
                  ),
                  if (onTap != null)
                    Icon(Icons.chevron_right, size: 18, color: color),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '$count',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: color,
                      height: 1,
                    ),
              ),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: color.withValues(alpha: 0.85),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
