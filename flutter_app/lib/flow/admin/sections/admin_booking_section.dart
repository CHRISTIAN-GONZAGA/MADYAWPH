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
    final gridColumns = MediaQuery.sizeOf(context).width >= 600 ? 3 : 2;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
        children: [
          Text(
            'Walk-in',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.hotelName,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap a category, then tap an available room to book locally.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
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
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.35,
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
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: available <= 0
                        ? null
                        : () => _openCategory(
                              categoryId: id,
                              categoryName: name,
                            ),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.king_bed_outlined,
                                  size: 18, color: scheme.primary),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
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
