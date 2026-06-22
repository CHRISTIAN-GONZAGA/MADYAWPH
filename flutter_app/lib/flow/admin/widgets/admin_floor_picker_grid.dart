import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../admin_dashboard_models.dart';

/// Tap-to-select floor tiles before showing rooms on that floor.
class AdminFloorPickerGrid extends StatelessWidget {
  const AdminFloorPickerGrid({
    super.key,
    required this.rooms,
    required this.onFloorTap,
    this.subtitle,
  });

  final List<Map<String, dynamic>> rooms;
  final ValueChanged<int> onFloorTap;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final floors = AdminDashboardModels.distinctFloors(rooms);
    final columns = MediaQuery.sizeOf(context).width >= 600 ? 3 : 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (subtitle != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              subtitle!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
        Text(
          'Tap a floor to view rooms',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.35,
            ),
            itemCount: floors.length,
            itemBuilder: (context, index) {
              final floor = floors[index];
              final count =
                  AdminDashboardModels.roomsOnFloor(rooms, floor).length;
              return Material(
                color: scheme.primaryContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onFloorTap(floor);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.layers_outlined,
                          color: scheme.primary,
                          size: 28,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          AdminDashboardModels.floorLabel(floor),
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$count room${count == 1 ? '' : 's'}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
