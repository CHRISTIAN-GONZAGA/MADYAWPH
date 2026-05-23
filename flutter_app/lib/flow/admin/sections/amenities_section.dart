import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../dio_client.dart';

class AmenitiesSection extends StatefulWidget {
  const AmenitiesSection({
    super.key,
    required this.claims,
    required this.onAddProduct,
    required this.onRefresh,
  });

  final List<dynamic> claims;
  final Future<void> Function() onAddProduct;
  final Future<void> Function() onRefresh;

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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(dioErrorMessage(e))));
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request marked fulfilled.')),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(dioErrorMessage(e))));
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Product updated.')),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(dioErrorMessage(e))));
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Product removed.')),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(dioErrorMessage(e))));
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
      return const Center(child: Text('No products. Tap Add to create one.'));
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
            onTap: () => _editItem(m),
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
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _categoryChips(),
              ),
              Expanded(
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
          length: 2,
          child: Column(
            children: [
              header,
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _categoryChips(),
              ),
              const TabBar(
                tabs: [
                  Tab(text: 'Products'),
                  Tab(text: 'Requests'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _productGrid(),
                    _claimsList(),
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
