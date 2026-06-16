import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../dio_client.dart';
import '../../../locale_controller.dart';
import '../../../widgets/app_state_views.dart';
import '../../../widgets/hotel_credits_policy.dart';
import '../../dashboards.dart';

/// Admin local booking — same browse + book flow as the public customer portal,
/// without photos, saved as Local (front desk) via `/admin/bookings`.
class AdminBookingSection extends StatefulWidget {
  const AdminBookingSection({
    super.key,
    required this.hotelId,
    required this.hotelName,
    required this.onChanged,
  });

  final String hotelId;
  final String hotelName;
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
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CustomerRoomsScreen(
          hotelId: widget.hotelId,
          categoryId: categoryId,
          categoryName: categoryName,
          hotelName: widget.hotelName,
          adminLocalBooking: true,
          hideImages: true,
          onBooked: _onBooked,
        ),
      ),
    );
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

    final categories =
        (_categoriesRes?['categories'] as List<dynamic>?) ?? [];
    final scheme = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final gridColumns = width >= 720 ? 4 : (width >= 480 ? 3 : 2);
    final availableCategories = categories.where((raw) {
      final m = raw as Map<String, dynamic>;
      return ((m['available_rooms'] as num?)?.toInt() ?? 0) > 0;
    }).length;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 88),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Walk-in · ${widget.hotelName}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    Text(
                      'Tap a category, then an available room.',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              if (categories.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 2),
                  child: Text(
                    '$availableCategories / ${categories.length}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: scheme.primary,
                        ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
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
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: gridColumns,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 1.85,
              ),
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final m = categories[index] as Map<String, dynamic>;
                final id = '${m['id']}';
                final name = '${m['name']}';
                final available = (m['available_rooms'] as num?)?.toInt() ?? 0;
                final availLabel = available == 1
                    ? context.tr('one_room_available')
                    : context.tr('rooms_available_label', {'n': '$available'});

                return Material(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(10),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: available <= 0
                        ? null
                        : () => _openCategory(
                              categoryId: id,
                              categoryName: name,
                            ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.king_bed_outlined,
                                  size: 16, color: scheme.primary),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            availLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: available > 0
                                      ? Colors.green.shade800
                                      : scheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
