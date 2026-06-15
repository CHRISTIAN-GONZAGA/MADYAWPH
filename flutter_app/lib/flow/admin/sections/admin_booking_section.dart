import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../dio_client.dart';
import '../../../locale_controller.dart';
import '../../../widgets/app_state_views.dart';
import '../../../widgets/chat_attachment.dart';
import '../../../widgets/hotel_credits_policy.dart';
import '../../dashboards.dart';

/// Admin local booking — same browse UI as public customers, submits to `/admin/bookings`.
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

  @override
  Widget build(BuildContext context) {
    if (!AdminCreditsGate.canPerformActions(context)) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          Icon(Icons.lock_outline, size: 48, color: Theme.of(context).colorScheme.outline),
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

    final categories = (_categoriesRes?['categories'] as List<dynamic>?) ?? [];
    final scheme = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          Text(
            'Local booking',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Same room browse as the public customer portal. Bookings here are saved as Local (front desk), not Online.',
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
          Text(
            context.tr('find_your_room'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Pick a category, choose an available room, then complete the booking form.',
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
                    Icon(Icons.event_busy_outlined, size: 48, color: scheme.outline),
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
            final imageUrl =
                ChatAttachment.resolveMediaUrl('${m['image_url'] ?? ''}');
            final available = (m['available_rooms'] as num?)?.toInt() ?? 0;
            final availLabel = available == 1
                ? context.tr('one_room_available')
                : context.tr('rooms_available_label', {'n': '$available'});

            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Material(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: available <= 0
                      ? null
                      : () {
                          Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) => CustomerRoomsScreen(
                                hotelId: widget.hotelId,
                                categoryId: id,
                                categoryName: name,
                                categoryImageUrl: imageUrl,
                                hotelName: widget.hotelName,
                                adminLocalBooking: true,
                                onBooked: _onBooked,
                              ),
                            ),
                          );
                        },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (imageUrl.isEmpty)
                        Container(
                          height: 120,
                          color: scheme.surfaceContainerHighest,
                          alignment: Alignment.center,
                          child: Icon(Icons.category_outlined,
                              size: 40, color: scheme.outline),
                        )
                      else
                        NetworkMediaImage(
                          url: imageUrl,
                          height: 120,
                          width: double.infinity,
                          error: Container(
                            height: 120,
                            color: scheme.surfaceContainerHighest,
                            alignment: Alignment.center,
                            child: Icon(Icons.broken_image_outlined,
                                color: scheme.outline),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: available > 0
                                    ? scheme.primaryContainer
                                    : scheme.errorContainer
                                        .withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                availLabel,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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
