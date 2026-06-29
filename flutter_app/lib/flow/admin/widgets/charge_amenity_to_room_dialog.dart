import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';

import '../../../dio_client.dart';
import '../admin_dashboard_models.dart';
import 'admin_floor_picker_grid.dart';

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
      final res =
          await portalDio().get<Map<String, dynamic>>('/admin/dashboard');
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
      'No checked-in rooms to charge. Check a guest in first.',
    );
    return false;
  }

  if (!context.mounted) return false;
  final grouped = AdminDashboardModels.groupByCategory(chargeable);
  final categoryKeys = grouped.keys.toList()..sort();

  final selection = await showModalBottomSheet<_ChargeSelection>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => _ChargeAmenityRoomPicker(
      productName: name,
      unitPrice: unitPrice,
      groupedRooms: grouped,
      categoryKeys: categoryKeys,
      allRooms: resolvedRooms,
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

enum _PickerStep { category, floor, room }

class _ChargeAmenityRoomPicker extends StatefulWidget {
  const _ChargeAmenityRoomPicker({
    required this.productName,
    required this.unitPrice,
    required this.groupedRooms,
    required this.categoryKeys,
    required this.allRooms,
    required this.categories,
  });

  final String productName;
  final double unitPrice;
  final Map<String, List<Map<String, dynamic>>> groupedRooms;
  final List<String> categoryKeys;
  final List<Map<String, dynamic>> allRooms;
  final List<Map<String, dynamic>> categories;

  @override
  State<_ChargeAmenityRoomPicker> createState() =>
      _ChargeAmenityRoomPickerState();
}

class _ChargeAmenityRoomPickerState extends State<_ChargeAmenityRoomPicker> {
  _PickerStep _step = _PickerStep.category;
  String? _category;
  int? _floor;
  Map<String, dynamic>? _selectedRoom;
  var _quantity = 1;

  List<Map<String, dynamic>> get _categoryRooms =>
      _category == null ? const [] : widget.groupedRooms[_category!] ?? const [];

  void _pickCategory(String label) {
    HapticFeedback.selectionClick();
    final categoryRooms = widget.groupedRooms[label] ?? const [];
    final floorCount = AdminDashboardModels.categoryFloorCountFrom(
      label,
      categoryRooms,
      widget.categories,
    );
    final floors = AdminDashboardModels.floorsForRooms(
      categoryRooms,
      categoryFloorCount: floorCount,
    );
    setState(() {
      _category = label;
      _selectedRoom = null;
      if (floors.length == 1) {
        _floor = floors.first;
        _step = _PickerStep.room;
      } else {
        _floor = null;
        _step = _PickerStep.floor;
      }
    });
  }

  void _pickFloor(int floor) {
    HapticFeedback.selectionClick();
    setState(() {
      _floor = floor;
      _selectedRoom = null;
      _step = _PickerStep.room;
    });
  }

  void _pickRoom(Map<String, dynamic> room) {
    HapticFeedback.selectionClick();
    setState(() => _selectedRoom = room);
  }

  void _back() {
    setState(() {
      switch (_step) {
        case _PickerStep.room:
          _step = _PickerStep.floor;
          _selectedRoom = null;
        case _PickerStep.floor:
          _step = _PickerStep.category;
          _category = null;
          _floor = null;
        case _PickerStep.category:
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.88;

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
                  if (_step != _PickerStep.category)
                    IconButton(
                      onPressed: _back,
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'Back',
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
            Expanded(child: _buildStepBody(context)),
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

  Widget _buildStepBody(BuildContext context) {
    switch (_step) {
      case _PickerStep.category:
        return _buildCategoryList(context);
      case _PickerStep.floor:
        return _buildFloorPicker(context);
      case _PickerStep.room:
        return _buildRoomGrid(context);
    }
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
                '${list.length} checked-in room${list.length == 1 ? '' : 's'}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _pickCategory(label),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildFloorPicker(BuildContext context) {
    final label = _category ?? '';
    final categoryRooms = _categoryRooms;
    final floorCount = AdminDashboardModels.categoryFloorCountFrom(
      label,
      categoryRooms,
      widget.categories,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        Expanded(
          child: AdminFloorPickerGrid(
            rooms: categoryRooms,
            categoryFloorCount: floorCount,
            onFloorTap: _pickFloor,
            subtitle: 'Checked-in rooms on each floor',
          ),
        ),
      ],
    );
  }
  Widget _buildRoomGrid(BuildContext context) {
    final label = _category ?? '';
    final floor = _floor ?? 1;
    final onFloor = AdminDashboardModels.roomsOnFloor(_categoryRooms, floor);
    final scheme = Theme.of(context).colorScheme;

    if (onFloor.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No checked-in rooms on ${AdminDashboardModels.floorLabel(floor)}.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '$label · ${AdminDashboardModels.floorLabel(floor)}',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
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
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.35,
          ),
          itemCount: onFloor.length,
          itemBuilder: (context, i) {
            final room = onFloor[i];
            final selected = _selectedRoom != null &&
                AdminDashboardModels.roomIdOf(room) ==
                    AdminDashboardModels.roomIdOf(_selectedRoom!);
            final guest = AdminDashboardModels.guestName(room);
            return Material(
              color: selected
                  ? scheme.primary
                  : Colors.green.shade600,
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
                      if (guest != '—') ...[
                        const SizedBox(height: 4),
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
          },
        ),
      ],
    );
  }
}
