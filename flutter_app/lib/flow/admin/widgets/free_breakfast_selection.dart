/// Complimentary amenity selections for walk-in bookings.
class FreeBreakfastSelection {
  const FreeBreakfastSelection({
    required this.menuItemId,
    required this.name,
    required this.quantity,
    this.amenityType = '',
  });

  final String menuItemId;
  final String name;
  final int quantity;
  final String amenityType;

  Map<String, dynamic> toJson() => {
        if (menuItemId.isNotEmpty) 'menu_item_id': menuItemId,
        'name': name,
        'quantity': quantity,
        if (amenityType.isNotEmpty) 'amenity_type': amenityType,
      };

  static FreeBreakfastSelection? fromDynamic(dynamic raw) {
    if (raw is String) {
      final name = raw.trim();
      if (name.isEmpty) return null;
      return FreeBreakfastSelection(menuItemId: '', name: name, quantity: 1);
    }
    if (raw is Map) {
      final name = (raw['name'] ?? '').toString().trim();
      if (name.isEmpty) return null;
      return FreeBreakfastSelection(
        menuItemId: (raw['menu_item_id'] ?? raw['id'] ?? '').toString(),
        name: name,
        quantity: (raw['quantity'] as num?)?.toInt().clamp(1, 20) ?? 1,
        amenityType: (raw['amenity_type'] ?? raw['amenityType'] ?? '').toString(),
      );
    }
    return null;
  }

  static List<FreeBreakfastSelection> listFromDynamic(List<dynamic>? raw) {
    if (raw == null) return const [];
    return raw
        .map(fromDynamic)
        .whereType<FreeBreakfastSelection>()
        .toList(growable: false);
  }

  static int totalQuantity(Iterable<FreeBreakfastSelection> items) {
    var total = 0;
    for (final item in items) {
      total += item.quantity;
    }
    return total;
  }
}
