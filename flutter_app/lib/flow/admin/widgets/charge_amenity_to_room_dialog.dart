import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';

import '../../../dio_client.dart';
import '../admin_dashboard_models.dart';

/// Charges an amenity menu item to a checked-in room (updates booking bill / receipt).
Future<bool> showChargeAmenityToRoomDialog({
  required BuildContext context,
  required Map<String, dynamic> menuItem,
  required List<Map<String, dynamic>> rooms,
  List<Map<String, dynamic>> categories = const [],
}) async {
  final itemId = (menuItem['id'] ?? menuItem['_id'] ?? '').toString();
  final name = (menuItem['name'] ?? 'Item').toString();
  final unitPrice = (menuItem['price'] as num?)?.toDouble() ?? 0.0;
  if (itemId.isEmpty || unitPrice <= 0) {
    showAppMessage(context, 'This product has no price set.');
    return false;
  }

  var resolvedRooms = rooms;
  if (resolvedRooms.isEmpty) {
    try {
      final res = await portalDioWithLongTimeout()
          .get<Map<String, dynamic>>('/admin/dashboard');
      resolvedRooms = AdminDashboardModels.parseRoomMaps(
        res.data?['rooms'] as List<dynamic>?,
      );
      final rawCategories = res.data?['categories'] as List<dynamic>?;
      if (rawCategories != null && categories.isEmpty) {
        categories = AdminDashboardModels.parseRoomMaps(rawCategories);
      }
    } on DioException catch (e) {
      if (!context.mounted) return false;
      showAppMessage(context, dioErrorMessage(e), isError: true);
      return false;
    }
  }

  final chargeable =
      AdminDashboardModels.amenityChargeableRooms(resolvedRooms);
  if (chargeable.isEmpty) {
    if (!context.mounted) return false;
    showAppMessage(
      context,
      'No in-house rooms to charge. Check a guest in first, then pull to refresh.',
    );
    return false;
  }

  final grouped = AdminDashboardModels.groupByCategory(chargeable);
  final categoryKeys = grouped.keys.toList()..sort();

  if (!context.mounted) return false;
  final selection = await showModalBottomSheet<_ChargeSelection>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => _ChargeAmenityRoomPicker(
      productName: name,
      unitPrice: unitPrice,
      groupedRooms: grouped,
      categoryKeys: categoryKeys,
      categories: categories,
    ),
  );

  if (selection == null || !context.mounted) return false;

  final room = selection.room;
  final quantity = selection.quantity;
  final roomId = AdminDashboardModels.roomIdOf(room);
  final booking = room['latest_booking'] as Map?;
  final bookingId = (booking?['id'] ?? booking?['_id'] ?? '').toString().trim();
  if (roomId.isEmpty || bookingId.isEmpty) {
    showAppMessage(context, 'No active booking for this room. Refresh and try again.');
    return false;
  }

  try {
    await portalDio().post('/billing/charges', data: {
      'booking_id': bookingId,
      'room_id': roomId,
      'type': 'amenity',
      'label': 'Amenity: $name',
      'amount': unitPrice,
      'quantity': quantity,
      'is_manual': false,
    });
    if (!context.mounted) return false;
    showAppMessage(
      context,
      'Charged $name × $quantity to room ${room['room_number']}.',
    );
    return true;
  } on DioException catch (e) {
    if (!context.mounted) return false;
    showAppMessage(context, dioErrorMessage(e), isError: true);
    return false;
  }
}

class _ChargeSelection {
  const _ChargeSelection({required this.room, required this.quantity});

  final Map<String, dynamic> room;
  final int quantity;
}

class _ChargeAmenityRoomPicker extends StatefulWidget {
  const _ChargeAmenityRoomPicker({
    required this.productName,
    required this.unitPrice,
    required this.groupedRooms,
    required this.categoryKeys,
    required this.categories,
  });

  final String productName;
  final double unitPrice;
  final Map<String, List<Map<String, dynamic>>> groupedRooms;
  final List<String> categoryKeys;
  final List<Map<String, dynamic>> categories;

  @override
  State<_ChargeAmenityRoomPicker> createState() =>
      _ChargeAmenityRoomPickerState();
}

class _ChargeAmenityRoomPickerState extends State<_ChargeAmenityRoomPicker> {
  String? _category;
  Map<String, dynamic>? _selectedRoom;
  var _quantity = 1;

  @override
  void initState() {
    super.initState();
    if (widget.categoryKeys.length == 1) {
      _category = widget.categoryKeys.first;
    }
  }

  void _pickCategory(String label) {
    HapticFeedback.selectionClick();
    setState(() {
      _category = label;
      _selectedRoom = null;
    });
  }

  void _pickRoom(Map<String, dynamic> room) {
    HapticFeedback.selectionClick();
    setState(() => _selectedRoom = room);
  }

  void _clearCategory() {
    setState(() {
      _category = null;
      _selectedRoom = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.88;
    final pickingCategory = _category == null && widget.categoryKeys.length > 1;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SizedBox(
        height: maxHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Row(
                children: [
                  if (!pickingCategory && widget.categoryKeys.length > 1)
                    IconButton(
                      onPressed: _clearCategory,
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'All categories',
                    )
                  else
                    const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Charge to room',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        Text(
                          '${widget.productName} · ₱${widget.unitPrice.toStringAsFixed(2)} each',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: pickingCategory
                  ? _buildCategoryList(context)
                  : _buildRoomPicker(context),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Text('Quantity'),
                      const Spacer(),
                      IconButton(
                        onPressed: _quantity > 1
                            ? () => setState(() => _quantity--)
                            : null,
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Text(
                        '$_quantity',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      IconButton(
                        onPressed: () => setState(() => _quantity++),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                  Text(
                    'Total: ₱${(widget.unitPrice * _quantity).toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: _selectedRoom == null
                        ? null
                        : () => Navigator.pop(
                              context,
                              _ChargeSelection(
                                room: _selectedRoom!,
                                quantity: _quantity,
                              ),
                            ),
                    child: Text(
                      _selectedRoom == null
                          ? 'Select a room'
                          : 'Charge room ${_selectedRoom!['room_number']}',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryList(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Choose a category',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        ...widget.categoryKeys.map((label) {
          final list = widget.groupedRooms[label] ?? const [];
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const Icon(Icons.category_outlined),
              title: Text(label),
              subtitle: Text(
                '${list.length} in-house room${list.length == 1 ? '' : 's'}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _pickCategory(label),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildRoomPicker(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final columns = MediaQuery.sizeOf(context).width >= 600 ? 4 : 3;

    if (widget.categoryKeys.length == 1) {
      return _buildCategoryRoomSection(
        context,
        category: widget.categoryKeys.first,
        rooms: widget.groupedRooms[widget.categoryKeys.first] ?? const [],
        columns: columns,
        scheme: scheme,
      );
    }

    if (_category != null) {
      return _buildCategoryRoomSection(
        context,
        category: _category!,
        rooms: widget.groupedRooms[_category!] ?? const [],
        columns: columns,
        scheme: scheme,
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: widget.categoryKeys.map((label) {
        final rooms = widget.groupedRooms[label] ?? const [];
        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: _buildCategoryRoomSection(
            context,
            category: label,
            rooms: rooms,
            columns: columns,
            scheme: scheme,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCategoryRoomSection(
    BuildContext context, {
    required String category,
    required List<Map<String, dynamic>> rooms,
    required int columns,
    required ColorScheme scheme,
  }) {
    if (rooms.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'No chargeable rooms in $category.',
          textAlign: TextAlign.center,
        ),
      );
    }

    final byFloor = <int, List<Map<String, dynamic>>>{};
    for (final room in rooms) {
      final floor = AdminDashboardModels.floorOf(room);
      byFloor.putIfAbsent(floor, () => []).add(room);
    }
    final floors = byFloor.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          category,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'Tap a room to charge this product',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 12),
        ...floors.map((floor) {
          final floorRooms =
              AdminDashboardModels.sortRoomsByNumber(byFloor[floor]!);
          final floorLabel = floors.length > 1
              ? AdminDashboardModels.floorLabel(floor)
              : null;
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (floorLabel != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      floorLabel,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: scheme.primary,
                          ),
                    ),
                  ),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1.35,
                  ),
                  itemCount: floorRooms.length,
                  itemBuilder: (context, i) => _roomTile(
                    context,
                    room: floorRooms[i],
                    scheme: scheme,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _roomTile(
    BuildContext context, {
    required Map<String, dynamic> room,
    required ColorScheme scheme,
  }) {
    final selected = _selectedRoom != null &&
        AdminDashboardModels.roomIdOf(room) ==
            AdminDashboardModels.roomIdOf(_selectedRoom!);
    final guest = AdminDashboardModels.guestName(room);
    final floor = AdminDashboardModels.floorOf(room);

    return Material(
      color: selected ? scheme.primary : Colors.green.shade600,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _pickRoom(room),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                (room['room_number'] ?? '—').toString(),
                style: TextStyle(
                  color: selected ? scheme.onPrimary : Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              Text(
                'F$floor',
                style: TextStyle(
                  color: selected
                      ? scheme.onPrimary.withValues(alpha: 0.85)
                      : Colors.white.withValues(alpha: 0.85),
                  fontSize: 10,
                ),
              ),
              if (guest != '—') ...[
                const SizedBox(height: 2),
                Text(
                  guest,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected
                        ? scheme.onPrimary.withValues(alpha: 0.9)
                        : Colors.white.withValues(alpha: 0.92),
                    fontSize: 10,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
