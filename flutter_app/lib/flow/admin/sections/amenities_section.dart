import 'package:dio/dio.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';
import 'package:flutter/material.dart';

import '../../../dio_client.dart';
import '../admin_dashboard_models.dart';
import '../widgets/admin_room_navigation.dart';
import '../widgets/admin_sales_panel.dart';
import '../widgets/amenity_charges_panel.dart';
import '../widgets/charge_amenity_to_room_dialog.dart';

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
      if (_filterType == null) return true;
      final t = (m['amenity_type'] ?? m['type'] ?? '').toString();
      return t == _filterType;
    }).toList();
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
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, 'charge'),
                icon: const Icon(Icons.hotel_outlined),
                label: const Text('Charge to room'),
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
      case 'edit':
        await _editItem(item);
        break;
      case 'delete':
        await _deleteItem(item);
        break;
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
                  value: active,
                  onChanged: (v) => setLocal(() => active = v),
                  title: const Text('Active on menu'),
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
        return Card(
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
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.canManageProducts)
                        PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'edit') {
                              _editItem(m);
                            } else if (v == 'delete') {
                              _deleteItem(m);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('Edit')),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete'),
                            ),
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
                    '₱${m['price'] ?? 0}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    active ? 'Active' : 'Hidden',
                    style: TextStyle(
                      fontSize: 11,
                      color: active ? Colors.green.shade700 : Colors.grey,
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
              if (widget.canManageProducts)
                FilledButton.icon(
                  onPressed: () async {
                    await widget.onAddProduct();
                    await _loadMenu();
                    await widget.onRefresh();
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add product'),
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
