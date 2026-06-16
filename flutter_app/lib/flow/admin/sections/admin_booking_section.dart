import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../dio_client.dart';
import '../../../locale_controller.dart';
import '../../../widgets/app_state_views.dart';
import '../../../widgets/hotel_credits_policy.dart';
import '../admin_dashboard_models.dart';
import 'admin_walk_in_category_rooms_screen.dart';

/// Admin walk-in booking — pick a category, then a color-coded room list.
class AdminBookingSection extends StatefulWidget {
  const AdminBookingSection({
    super.key,
    required this.hotelId,
    required this.hotelName,
    required this.rooms,
    required this.onChanged,
  });

  final String hotelId;
  final String hotelName;
  final List<Map<String, dynamic>> rooms;
  final Future<void> Function() onChanged;

  @override
  State<AdminBookingSection> createState() => _AdminBookingSectionState();
}

class _AdminBookingSectionState extends State<AdminBookingSection> {
  Map<String, dynamic>? _categoriesRes;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.hotelId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Hotel ID missing. Pull to refresh the dashboard.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await publicDio().get<Map<String, dynamic>>(
        '/customer/categories',
        queryParameters: {'hotel_id': widget.hotelId},
      );
      if (!mounted) return;
      setState(() {
        _categoriesRes = res.data;
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = dioErrorMessage(e);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _onBooked() async {
    await widget.onChanged();
    if (mounted) await _load();
  }

  void _openCategory({
    required String categoryId,
    required String categoryName,
  }) {
    final categoryRooms = AdminDashboardModels.roomsForCategory(
      widget.rooms,
      categoryId: categoryId,
      categoryName: categoryName,
    );
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AdminWalkInCategoryRoomsScreen(
          hotelId: widget.hotelId,
          categoryName: categoryName,
          rooms: categoryRooms,
          onBooked: _onBooked,
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _fallbackCategoriesFromRooms() {
    final grouped = AdminDashboardModels.groupByCategory(widget.rooms);
    final keys = grouped.keys.toList()..sort();
    return keys
        .map(
          (label) => {
            'id': label,
            'name': label,
          },
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    if (!AdminCreditsGate.canPerformActions(context)) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          Icon(Icons.lock_outline,
              size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(
            'Credits depleted. Top up in Settings to book walk-in guests.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      );
    }

    if (_loading) {
      return const AppLoadingView();
    }
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: _load, child: Text(context.tr('retry'))),
        ],
      );
    }

    final apiCategories =
        (_categoriesRes?['categories'] as List<dynamic>?) ?? [];
    final categories = apiCategories.isNotEmpty
        ? apiCategories
        : _fallbackCategoriesFromRooms();
    final scheme = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          Text(
            'Walk-in',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Pick a category, then tap a green available room to book a local walk-in stay.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.35,
                ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.hotelName,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.primary,
                ),
          ),
          const SizedBox(height: 16),
          _WalkInStatusLegend(scheme: scheme),
          const SizedBox(height: 16),
          Text(
            context.tr('find_your_room'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Categories show all rooms. Green = available, orange = reserved, red = occupied.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          if (categories.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(Icons.event_busy_outlined,
                        size: 48, color: scheme.outline),
                    const SizedBox(height: 12),
                    Text(
                      context.tr('no_categories_available'),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Add categories and rooms under Settings first.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ...categories.map((c) {
            final m = c as Map<String, dynamic>;
            final id = '${m['id']}';
            final name = '${m['name']}';
            final categoryRooms = AdminDashboardModels.roomsForCategory(
              widget.rooms,
              categoryId: id,
              categoryName: name,
            );
            final counts =
                AdminDashboardModels.walkInStatusCounts(categoryRooms);
            final summary = categoryRooms.isEmpty
                ? 'No rooms linked'
                : '${counts['available']} available · '
                    '${counts['reserved']} reserved · '
                    '${counts['occupied']} occupied';

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _openCategory(
                    categoryId: id,
                    categoryName: name,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: scheme.primaryContainer,
                          child: Icon(Icons.king_bed_outlined,
                              color: scheme.onPrimaryContainer),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                summary,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: scheme.primary),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _WalkInStatusLegend extends StatelessWidget {
  const _WalkInStatusLegend({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Wrap(
          spacing: 16,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            _legendDot(
              AdminDashboardModels.walkInTileColor('available'),
              'Available',
            ),
            _legendDot(
              AdminDashboardModels.walkInTileColor('reserved'),
              'Reserved',
            ),
            _legendDot(
              AdminDashboardModels.walkInTileColor('occupied'),
              'Occupied',
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
      ],
    );
  }
}
