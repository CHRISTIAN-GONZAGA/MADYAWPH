import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth_storage.dart';
import '../widgets/chat_attachment.dart';
import 'customer_search_context.dart';
import 'dashboards.dart';

/// Hotels that can accommodate the guest's search criteria.
class HotelSearchResultsScreen extends StatelessWidget {
  const HotelSearchResultsScreen({
    super.key,
    required this.hotels,
    required this.search,
  });

  final List<Map<String, dynamic>> hotels;
  final CustomerSearchContext search;

  String _fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}';
  }

  Future<void> _openHotel(BuildContext context, Map<String, dynamic> hotel) async {
    HapticFeedback.selectionClick();
    final id = (hotel['id'] ?? '').toString();
    final name = (hotel['name'] ?? 'Hotel').toString();
    if (id.isEmpty) return;
    await AuthStorage.setHotelContext(id: id, name: name);
    if (!context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CustomerDashboardScreen(
          hotelId: id,
          searchContext: search,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      appBar: AppBar(
        title: Text('${hotels.length} hotels available'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${_fmtDate(search.checkIn)} → ${_fmtDate(search.checkOut)} · '
                '${search.rooms} room${search.rooms == 1 ? '' : 's'}, '
                '${search.adults} adult${search.adults == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ),
          ),
        ),
      ),
      body: hotels.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.hotel_outlined, size: 56, color: scheme.outline),
                    const SizedBox(height: 16),
                    Text(
                      'No hotels can accommodate your dates',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Try different dates or a broader destination.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: hotels.length,
              separatorBuilder: (_, __) => const SizedBox(height: 14),
              itemBuilder: (context, i) {
                final h = hotels[i];
                final name = (h['name'] ?? 'Hotel').toString();
                final city = (h['city'] ?? h['location'] ?? '').toString();
                final region = (h['region'] ?? '').toString();
                final loc = [city, region].where((s) => s.isNotEmpty).join(' · ');
                final minPrice = (h['min_price'] as num?)?.toDouble() ?? 0;
                final available = (h['available_rooms'] as num?)?.toInt() ?? 0;
                final banner = ChatAttachment.resolveMediaUrl(
                  (h['banner_url'] ?? '').toString(),
                );

                return Material(
                  elevation: 2,
                  shadowColor: Colors.black26,
                  borderRadius: BorderRadius.circular(18),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _openHotel(context, h),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 150,
                          child: banner.isEmpty
                              ? Container(
                                  color: scheme.primaryContainer,
                                  alignment: Alignment.center,
                                  child: Icon(Icons.apartment,
                                      size: 48, color: scheme.primary),
                                )
                              : NetworkMediaImage(
                                  url: banner,
                                  fit: BoxFit.cover,
                                  height: 150,
                                  width: double.infinity,
                                  error: Container(
                                    color: scheme.surfaceContainerHighest,
                                    alignment: Alignment.center,
                                    child: const Icon(Icons.broken_image_outlined),
                                  ),
                                ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16),
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
                              if (loc.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  loc,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: scheme.onSurfaceVariant),
                                ),
                              ],
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: scheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      '$available rooms free',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: scheme.onPrimaryContainer,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  if (minPrice > 0)
                                    Text(
                                      'from ₱${minPrice.toStringAsFixed(0)}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            color: scheme.primary,
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                  const SizedBox(width: 4),
                                  Icon(Icons.chevron_right, color: scheme.primary),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
