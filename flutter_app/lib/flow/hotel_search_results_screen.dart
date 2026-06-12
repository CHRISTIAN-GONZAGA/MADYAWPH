import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth_storage.dart';
import '../locale_controller.dart';
import '../ui/app_visual.dart';
import '../widgets/chat_attachment.dart';
import 'customer_search_context.dart';
import 'dashboards.dart';
import 'member_subscription_flow.dart';

/// Hotels that can accommodate the guest's search criteria.
class HotelSearchResultsScreen extends StatelessWidget {
  const HotelSearchResultsScreen({
    super.key,
    required this.hotels,
    required this.search,
  });

  final List<Map<String, dynamic>> hotels;
  final CustomerSearchContext search;

  int get _nights =>
      search.checkOut.difference(search.checkIn).inDays.clamp(1, 365);

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
      PageRouteBuilder<void>(
        pageBuilder: (_, animation, __) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.05, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
          child: CustomerDashboardScreen(
            hotelId: id,
            searchContext: search,
          ),
        ),
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final destination = search.destinationQuery.trim();

    final visual = AppVisual.of(context);

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: visual.scaffoldGradient(scheme),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppBar(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
        title: Text(
          hotels.isEmpty
              ? context.tr('no_matches')
              : context.tr('hotels_found_count', {'n': '${hotels.length}'}),
        ),
              actions: [
                IconButton(
                  tooltip: context.tr('edit_search'),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.tune),
                ),
              ],
            ),
            Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  scheme.primaryContainer,
                  scheme.surface,
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (destination.isNotEmpty)
                  Row(
                    children: [
                      Icon(Icons.place_outlined, size: 18, color: scheme.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          destination,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                if (destination.isNotEmpty) const SizedBox(height: 8),
                Text(
                  context.tr('search_summary_line', {
                    'checkin': _fmtDate(search.checkIn),
                    'checkout': _fmtDate(search.checkOut),
                    'nights': context.tr('nights_count', {'n': '$_nights'}),
                    'party': context.tr('guest_party_line', {
                      'rooms': '${search.rooms}',
                      'adults': '${search.adults}',
                      'children': '${search.children}',
                    }),
                  }),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _MemberPromoBanner(
                onTap: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const MemberRegistrationScreen(),
                    ),
                  );
                },
              ),
            ),
            Expanded(
              child: hotels.isEmpty
                  ? _EmptyResults(search: search)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: hotels.length,
                      itemBuilder: (context, i) {
                        return _AnimatedHotelCard(
                          index: i,
                          hotel: hotels[i],
                          nights: _nights,
                          onTap: () => _openHotel(context, hotels[i]),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberPromoBanner extends StatelessWidget {
  const _MemberPromoBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1A2B4A), Color(0xFF2D4A7A)],
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFD4A843).withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.workspace_premium_outlined,
                    color: Color(0xFFD4A843), size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BE A MEMBER',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₱300/month — exclusive perks & priority booking',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white70,
                          ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults({required this.search});

  final CustomerSearchContext search;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.hotel_outlined, size: 48, color: scheme.outline),
            ),
            const SizedBox(height: 20),
            Text(
              context.tr('no_hotels_for_stay'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              context.tr('try_different_search'),
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.edit_outlined),
              label: Text(context.tr('edit_search')),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedHotelCard extends StatefulWidget {
  const _AnimatedHotelCard({
    required this.index,
    required this.hotel,
    required this.nights,
    required this.onTap,
  });

  final int index;
  final Map<String, dynamic> hotel;
  final int nights;
  final VoidCallback onTap;

  @override
  State<_AnimatedHotelCard> createState() => _AnimatedHotelCardState();
}

class _AnimatedHotelCardState extends State<_AnimatedHotelCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    Future<void>.delayed(Duration(milliseconds: 40 * widget.index), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: _HotelResultCard(
            hotel: widget.hotel,
            nights: widget.nights,
            onTap: widget.onTap,
          ),
        ),
      ),
    );
  }
}

class _HotelResultCard extends StatelessWidget {
  const _HotelResultCard({
    required this.hotel,
    required this.nights,
    required this.onTap,
  });

  final Map<String, dynamic> hotel;
  final int nights;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = (hotel['name'] ?? 'Hotel').toString();
    final city = (hotel['city'] ?? hotel['location'] ?? '').toString();
    final region = (hotel['region'] ?? '').toString();
    final loc = [city, region].where((s) => s.isNotEmpty).join(' · ');
    final minPrice = (hotel['min_price'] as num?)?.toDouble() ?? 0;
    final available = (hotel['available_rooms'] as num?)?.toInt() ?? 0;
    final canAccommodate = hotel['can_accommodate'] != false && available > 0;
    final estStay = minPrice > 0 ? minPrice * nights : 0.0;
    final banner = ChatAttachment.resolveMediaUrl(
      (hotel['banner_url'] ?? '').toString(),
    );

    return Material(
      elevation: 3,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                SizedBox(
                  height: 160,
                  child: banner.isEmpty
                      ? Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                scheme.primaryContainer,
                                scheme.primary.withValues(alpha: 0.25),
                              ],
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Icon(Icons.apartment,
                              size: 52, color: scheme.primary),
                        )
                      : NetworkMediaImage(
                          url: banner,
                          fit: BoxFit.cover,
                          height: 160,
                          width: double.infinity,
                          error: Container(
                            color: scheme.surfaceContainerHighest,
                            alignment: Alignment.center,
                            child: const Icon(Icons.broken_image_outlined),
                          ),
                        ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: canAccommodate
                          ? const Color(0xFF2E7D32)
                          : Colors.orange.shade800,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      canAccommodate
                          ? context.tr('rooms_available', {'n': '$available'})
                          : context.tr('limited_availability'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  if (loc.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.place_outlined,
                            size: 14, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            loc,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (minPrice > 0) ...[
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.tr('from_price_php', {
                                'n': minPrice.toStringAsFixed(0),
                              }),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            if (estStay > 0)
                              Text(
                                context.tr('stay_estimate', {
                                  'total': estStay.toStringAsFixed(0),
                                  'n': '$nights',
                                }),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ],
                      const Spacer(),
                      FilledButton.tonalIcon(
                        onPressed: onTap,
                        icon: const Icon(Icons.arrow_forward, size: 18),
                        label: Text(context.tr('view_rooms')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
