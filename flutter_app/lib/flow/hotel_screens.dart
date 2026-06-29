import 'dart:convert';
import 'package:gloretto_mobile/widgets/app_notice.dart';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../auth_storage.dart';
import '../services/nearby_hotels.dart';
import '../branding/madyaw_logo_widget.dart';
import 'hotel_how_to.dart';
import '../dio_client.dart';
import '../ui/app_visual.dart';
import '../locale_controller.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/language_picker_button.dart';
import '../data/philippine_locations.dart';
import '../widgets/app_input.dart';
import '../widgets/chat_attachment.dart';
import '../widgets/philippine_address_picker.dart';
import 'flow_state.dart';
import 'dashboards.dart';
import 'hotel_property_login_screen.dart';
import 'system_access_screen.dart';
// --- Choose hotel (by city/region) → system access ---

/// Staff / property login: hotel gate credentials → system access.
class PropertyStaffEntryScreen extends StatelessWidget {
  const PropertyStaffEntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return HotelPropertyLoginScreen(
      onRegisterHotel: () {
        Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const HotelRegisterScreen(fromStaffEntry: true),
          ),
        );
      },
    );
  }
}

const _kHotelPriceFallbackMin = 0.0;
const _kHotelPriceFallbackMax = 50000.0;

class ChooseHotelScreen extends StatefulWidget {
  const ChooseHotelScreen({super.key, this.staffEntry = false});

  /// When true, selecting a hotel opens the property role menu (staff login flow).
  final bool staffEntry;

  @override
  State<ChooseHotelScreen> createState() => _ChooseHotelScreenState();
}

class _ChooseHotelScreenState extends State<ChooseHotelScreen> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _regions = const [];
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  RangeValues _priceRange =
      const RangeValues(_kHotelPriceFallbackMin, _kHotelPriceFallbackMax);
  double _catalogFloor = _kHotelPriceFallbackMin;
  double _catalogCeiling = _kHotelPriceFallbackMax;
  String? _selectedRegion;
  bool _onlyWithPrices = false;
  bool _nearMeActive = false;
  bool _locatingNearMe = false;
  final Map<String, double> _hotelDistanceKm = {};
  int _hotelsWithCoordinates = 0;
  String _sortBy = 'closest';

  static const _sortOptions = {
    'closest': 'sort_closest',
    'distance': 'sort_distance',
    'price_low': 'sort_price_low',
    'price_high': 'sort_price_high',
    'name': 'sort_name',
    'region': 'sort_region',
  };

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _hydrateFromCacheThenLoad();
  }

  List<Map<String, dynamic>> _parseRegions(dynamic raw) {
    return (raw as List<dynamic>?)
            ?.whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList() ??
        const [];
  }

  Future<void> _hydrateFromCacheThenLoad() async {
    final cached = await AuthStorage.hotelsDirectoryCache();
    if (cached != null && cached.isNotEmpty) {
      try {
        final decoded = jsonDecode(cached);
        if (decoded is Map<String, dynamic>) {
          final regions = _parseRegions(decoded['regions']);
          if (mounted && regions.isNotEmpty) {
            setState(() {
              _regions = regions;
              _loading = false;
              _error = null;
            });
            _syncCatalogPriceBounds(decoded['meta']);
            _hotelsWithCoordinates =
                (decoded['meta']?['hotels_with_coordinates'] as num?)?.toInt() ??
                    0;
            _hotelsWithCoordinates = _coordinateHotelCount;
            if (mounted) setState(() {});
          }
        }
      } catch (_) {
        await AuthStorage.clearHotelsDirectoryCache();
      }
    }
    await _load(silent: _regions.isNotEmpty);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() => _refreshing = true);
    }
    try {
      final data = await _fetchHotelsWithRetry();
      final regions = _parseRegions(data?['regions']);
      if (!mounted) return;
      if (data != null) {
        await AuthStorage.setHotelsDirectoryCache(jsonEncode(data));
      }
      setState(() {
        _regions = regions;
        _loading = false;
        _refreshing = false;
        _error = null;
      });
      _syncCatalogPriceBounds(data?['meta']);
      _hotelsWithCoordinates =
          (data?['meta']?['hotels_with_coordinates'] as num?)?.toInt() ?? 0;
      _hotelsWithCoordinates = _coordinateHotelCount;
      if (mounted) {
        setState(() {});
      }
    } on DioException catch (e) {
      if (!mounted) return;
      final msg = dioErrorMessage(e);
      setState(() {
        if (_regions.isEmpty) {
          _error = msg;
        } else {
          _error = null;
        }
        _loading = false;
        _refreshing = false;
      });
      if (_regions.isNotEmpty) {
        showAppMessage(context, msg);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
        _refreshing = false;
      });
    }
  }

  Future<void> _refreshHotels() => _load(silent: _regions.isNotEmpty);

  bool _isRetriableTimeout(DioException e) =>
      e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.connectionError;

  Future<Map<String, dynamic>?> _fetchHotelsWithRetry({int attempt = 0}) async {
    try {
      final res = await publicDio().get<Map<String, dynamic>>(
        '/hotels',
        options: Options(receiveTimeout: kPublicReceiveTimeout),
      );
      return res.data;
    } on DioException catch (e) {
      if (attempt < 2 && _isRetriableTimeout(e)) {
        await Future<void>.delayed(Duration(seconds: 4 * (attempt + 1)));
        return _fetchHotelsWithRetry(attempt: attempt + 1);
      }
      rethrow;
    }
  }

  String get _query => _search.text.trim().toLowerCase();

  List<String> get _queryTokens => _query
      .split(RegExp(r'\s+'))
      .where((t) => t.length >= 2)
      .toList();

  bool get _hasActiveFilters =>
      _query.isNotEmpty ||
      _selectedRegion != null ||
      _onlyWithPrices ||
      _nearMeActive ||
      _priceFilterIsNarrowed ||
      _sortBy != 'closest';

  int get _coordinateHotelCount {
    final fromList = NearbyHotelsService.countHotelsWithCoordinates(_allHotels);
    return math.max(fromList, _hotelsWithCoordinates);
  }

  bool get _priceFilterIsNarrowed =>
      _catalogCeiling > _catalogFloor &&
      (_priceRange.start > _catalogFloor + 0.5 ||
          _priceRange.end < _catalogCeiling - 0.5);

  bool get _catalogHasPricing => _catalogCeiling > _catalogFloor;

  int get _priceSliderDivisions {
    final span = _catalogCeiling - _catalogFloor;
    if (span <= 0) return 1;
    return math.min(100, math.max(12, (span / 100).round()));
  }

  List<Map<String, dynamic>> get _allHotels {
    final list = <Map<String, dynamic>>[];
    for (final region in _regions) {
      final regionName = (region['region'] ?? 'Other').toString();
      for (final raw in (region['hotels'] as List?) ?? const []) {
        if (raw is! Map) continue;
        final hotel = Map<String, dynamic>.from(raw);
        if ((hotel['city'] ?? '').toString().isEmpty) {
          hotel['city'] = regionName;
        }
        list.add(hotel);
      }
    }
    return list;
  }

  List<String> get _availableRegions {
    final names = <String>{};
    for (final region in _regions) {
      final name = (region['region'] ?? '').toString().trim();
      if (name.isNotEmpty) names.add(name);
    }
    for (final hotel in _allHotels) {
      final r = (hotel['region'] ?? '').toString().trim();
      if (r.isNotEmpty) names.add(r);
      final city = (hotel['city'] ?? '').toString().trim();
      if (city.isNotEmpty) names.add(city);
    }
    final sorted = names.toList()..sort();
    return sorted;
  }

  void _syncCatalogPriceBounds(dynamic meta) {
    double floor = (meta is Map ? (meta['price_floor'] as num?) : null)?.toDouble() ?? 0;
    double ceiling =
        (meta is Map ? (meta['price_ceiling'] as num?) : null)?.toDouble() ?? 0;

    if (ceiling <= floor) {
      for (final hotel in _allHotels) {
        final lo = (hotel['min_price'] as num?)?.toDouble() ?? 0;
        final hi = (hotel['max_price'] as num?)?.toDouble() ?? 0;
        if (hi <= 0 && lo <= 0) continue;
        final effectiveMin = lo > 0 ? lo : hi;
        final effectiveMax = hi > 0 ? hi : lo;
        floor = floor <= 0 ? effectiveMin : math.min(floor, effectiveMin);
        ceiling = math.max(ceiling, effectiveMax);
      }
    }

    if (ceiling > floor) {
      _catalogFloor = floor;
      _catalogCeiling = ceiling;
      if (!_priceFilterIsNarrowed) {
        _priceRange = RangeValues(floor, ceiling);
      } else {
        _priceRange = RangeValues(
          _priceRange.start.clamp(floor, ceiling),
          _priceRange.end.clamp(floor, ceiling),
        );
      }
    } else {
      _catalogFloor = _kHotelPriceFallbackMin;
      _catalogCeiling = _kHotelPriceFallbackMax;
    }
  }

  void _resetFilters() {
    setState(() {
      _search.clear();
      _selectedRegion = null;
      _onlyWithPrices = false;
      _nearMeActive = false;
      _hotelDistanceKm.clear();
      _sortBy = 'closest';
      _priceRange = RangeValues(_catalogFloor, _catalogCeiling);
    });
  }

  Future<void> _useNearMe() async {
    if (_locatingNearMe) return;
    setState(() => _locatingNearMe = true);
    try {
      final pos = await NearbyHotelsService.currentPosition();

      final distances = <String, double>{};
      var locatedCount = 0;

      for (final hotel in _allHotels) {
        final id = (hotel['id'] ?? '').toString();
        if (id.isEmpty) continue;

        final lat = NearbyHotelsService.hotelLatitude(hotel);
        final lng = NearbyHotelsService.hotelLongitude(hotel);
        if (lat == null || lng == null) continue;

        final km = NearbyHotelsService.distanceKm(pos.lat, pos.lng, lat, lng);
        distances[id] = km;
        if (km <= NearbyHotelsService.defaultRadiusKm) {
          locatedCount++;
        }
      }

      if (!mounted) return;

      if (distances.isEmpty) {
        showAppMessage(context, context.tr('near_me_no_coordinates'));
        setState(() {
          _locatingNearMe = false;
        });
        return;
      }

      setState(() {
        _hotelDistanceKm
          ..clear()
          ..addAll(distances);
        _nearMeActive = true;
        _sortBy = 'distance';
        _locatingNearMe = false;
      });

      showAppMessage(
        context,
        context.tr('near_me_found').replaceAll('{n}', '$locatedCount'),
      );
    } on NearbyHotelsException catch (e) {
      if (!mounted) return;
      final msg = switch (e.code) {
        'permission_denied' || 'permission_denied_forever' =>
          context.tr('near_me_permission_denied'),
        'location_services_disabled' => context.tr('near_me_location_disabled'),
        _ => context.tr('near_me_location_failed'),
      };
      showAppMessage(context, msg);
      if (e.code == 'permission_denied' ||
          e.code == 'permission_denied_forever' ||
          e.code == 'location_services_disabled') {
        final openSettings = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(context.tr('near_me_use')),
            content: Text(msg),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Open settings'),
              ),
            ],
          ),
        );
        if (openSettings == true) {
          if (e.code == 'location_services_disabled') {
            await Geolocator.openLocationSettings();
          } else {
            await Geolocator.openAppSettings();
          }
        }
      }
      setState(() => _locatingNearMe = false);
    } catch (_) {
      if (!mounted) return;
      showAppMessage(context, context.tr('near_me_location_failed'), isError: true);
      setState(() => _locatingNearMe = false);
    }
  }

  void _clearNearMe() {
    setState(() {
      _nearMeActive = false;
      _hotelDistanceKm.clear();
      if (_sortBy == 'distance') _sortBy = 'closest';
    });
  }

  bool _passesNearMeFilter(Map<String, dynamic> hotel) {
    if (!_nearMeActive) return true;
    final id = (hotel['id'] ?? '').toString();
    final km = _hotelDistanceKm[id];
    if (km == null) return false;
    return km <= NearbyHotelsService.defaultRadiusKm;
  }

  static String _formatPeso(num value) {
    final n = value.round();
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return '₱$buf';
  }

  static String _priceLabelForHotel(
    BuildContext context,
    Map<String, dynamic> hotel,
  ) {
    final minPrice = (hotel['min_price'] as num?)?.toDouble() ?? 0;
    final maxPrice = (hotel['max_price'] as num?)?.toDouble() ?? 0;
    if (minPrice <= 0 && maxPrice <= 0) {
      return context.tr('price_not_listed');
    }
    final lo = minPrice > 0 ? minPrice : maxPrice;
    final hi = maxPrice > 0 ? maxPrice : lo;
    if (hi > lo) {
      return '${_formatPeso(lo)} – ${_formatPeso(hi)} / ${context.tr('night')}';
    }
    return '${context.tr('from_price')} ${_formatPeso(lo)} / ${context.tr('night')}';
  }

  int _matchScore(Map<String, dynamic> hotel, String query) {
    if (query.isEmpty) return 0;
    var score = 0;
    final name = (hotel['name'] ?? '').toString().toLowerCase();
    final city = (hotel['city'] ?? '').toString().toLowerCase();
    final loc = (hotel['location'] ?? '').toString().toLowerCase();
    if (city == query) {
      score += 120;
    } else if (city.startsWith(query)) {
      score += 90;
    } else if (city.contains(query)) {
      score += 60;
    }
    if (name.startsWith(query)) {
      score += 50;
    } else if (name.contains(query)) {
      score += 35;
    }
    if (loc.contains(query)) score += 25;
    return score;
  }

  bool _passesTextFilter(Map<String, dynamic> hotel, String regionName) {
    if (_query.isEmpty) return true;
    final hotelName = (hotel['name'] ?? '').toString().toLowerCase();
    final loc = (hotel['location'] ?? '').toString().toLowerCase();
    final city = (hotel['city'] ?? regionName).toString().toLowerCase();
    final region = regionName.toLowerCase();
    final haystack = '$region $city $hotelName $loc';
    if (_queryTokens.isEmpty) {
      return haystack.contains(_query);
    }
    return _queryTokens.every((token) => haystack.contains(token));
  }

  bool _passesRegionFilter(Map<String, dynamic> hotel, String regionName) {
    if (_selectedRegion == null) return true;
    final key = _selectedRegion!.toLowerCase();
    final hotelRegion = (hotel['region'] ?? '').toString().toLowerCase();
    final city = (hotel['city'] ?? regionName).toString().toLowerCase();
    final blockRegion = regionName.toLowerCase();
    return hotelRegion == key ||
        city == key ||
        blockRegion == key;
  }

  bool _hotelHasListedPrice(Map<String, dynamic> hotel) {
    final minPrice = (hotel['min_price'] as num?)?.toDouble() ?? 0;
    final maxPrice = (hotel['max_price'] as num?)?.toDouble() ?? 0;
    return minPrice > 0 || maxPrice > 0;
  }

  bool _passesPriceFilter(Map<String, dynamic> hotel) {
    if (_onlyWithPrices && !_hotelHasListedPrice(hotel)) {
      return false;
    }
    if (!_catalogHasPricing || !_priceFilterIsNarrowed) {
      return true;
    }
    final lo = (hotel['min_price'] as num?)?.toDouble() ?? 0;
    final hi = (hotel['max_price'] as num?)?.toDouble() ?? lo;
    if (hi <= 0 && lo <= 0) {
      return !_onlyWithPrices;
    }
    final minVal = hi > 0 ? math.min(lo > 0 ? lo : hi, hi) : lo;
    final maxVal = hi > 0 ? hi : lo;
    return maxVal >= _priceRange.start && minVal <= _priceRange.end;
  }

  List<Map<String, dynamic>> get _filteredHotels {
    var list = <Map<String, dynamic>>[];
    for (final region in _regions) {
      final regionName = (region['region'] ?? 'Other').toString();
      for (final raw in (region['hotels'] as List?) ?? const []) {
        if (raw is! Map) continue;
        final hotel = Map<String, dynamic>.from(raw);
        if (!_passesRegionFilter(hotel, regionName)) continue;
        if (!_passesTextFilter(hotel, regionName)) continue;
        if (!_passesPriceFilter(hotel)) continue;
        if (!_passesNearMeFilter(hotel)) continue;
        list.add(hotel);
      }
    }

    switch (_sortBy) {
      case 'distance':
        list.sort((a, b) {
          final ak = _hotelDistanceKm[(a['id'] ?? '').toString()] ?? 99999;
          final bk = _hotelDistanceKm[(b['id'] ?? '').toString()] ?? 99999;
          return ak.compareTo(bk);
        });
      case 'price_low':
        list.sort((a, b) {
          final av = (a['min_price'] as num?)?.toDouble() ?? 0;
          final bv = (b['min_price'] as num?)?.toDouble() ?? 0;
          return av.compareTo(bv);
        });
      case 'price_high':
        list.sort((a, b) {
          final av = (a['max_price'] as num?)?.toDouble() ?? 0;
          final bv = (b['max_price'] as num?)?.toDouble() ?? 0;
          return bv.compareTo(av);
        });
      case 'name':
        list.sort(
          (a, b) => (a['name'] ?? '')
              .toString()
              .toLowerCase()
              .compareTo((b['name'] ?? '').toString().toLowerCase()),
        );
      case 'region':
        list.sort((a, b) {
          final ac = (a['city'] ?? '').toString().toLowerCase();
          final bc = (b['city'] ?? '').toString().toLowerCase();
          final c = ac.compareTo(bc);
          if (c != 0) return c;
          return (a['name'] ?? '')
              .toString()
              .toLowerCase()
              .compareTo((b['name'] ?? '').toString().toLowerCase());
        });
      case 'closest':
      default:
        if (_query.isNotEmpty) {
          list.sort(
            (a, b) => _matchScore(b, _query).compareTo(_matchScore(a, _query)),
          );
        } else {
          list.sort((a, b) => (a['city'] ?? '')
              .toString()
              .compareTo((b['city'] ?? '').toString()));
        }
    }
    return list;
  }

  List<Map<String, dynamic>> get _filteredRegions {
    if (_sortBy == 'price_low' ||
        _sortBy == 'price_high' ||
        _sortBy == 'distance' ||
        (_sortBy == 'closest' && _queryTokens.isNotEmpty) ||
        _selectedRegion != null ||
        _nearMeActive) {
      if (_filteredHotels.isEmpty) return const [];
      return [
        {'region': '', 'hotels': _filteredHotels},
      ];
    }

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final h in _filteredHotels) {
      final city = (h['city'] ?? 'Other').toString();
      grouped.putIfAbsent(city, () => []).add(h);
    }
    final keys = grouped.keys.toList()..sort();
    return keys
        .map((k) => {'region': k, 'hotels': grouped[k]!})
        .toList();
  }

  Future<void> _selectHotel(Map<String, dynamic> hotel) async {
    final hid = (hotel['id'] ?? '').toString();
    final hname = (hotel['name'] ?? 'Hotel').toString();
    if (hid.isEmpty) return;
    HapticFeedback.lightImpact();
    final previousId = await AuthStorage.hotelId();
    await AuthStorage.setHotelContext(id: hid, name: hname);
    if (previousId != hid) {
      await AuthStorage.clearPortalAuth();
      await AuthStorage.clearGuestAuth();
    }
    if (!mounted) return;
    final session = HotelSession(hotelId: hid, hotelName: hname);
    hotelSessionNotifier.value = session;
    if (widget.staffEntry) {
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => SystemAccessScreen(session: session),
        ),
      );
    }
  }

  int get _totalHotels {
    var n = 0;
    for (final r in _filteredRegions) {
      n += ((r['hotels'] as List<dynamic>?) ?? const []).length;
    }
    return n;
  }

  Future<void> _openRegister() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => HotelRegisterScreen(fromStaffEntry: widget.staffEntry),
      ),
    );
    if (mounted) await _refreshHotels();
  }

  List<Widget> _buildHotelPickerSlivers(
    BuildContext context, {
    required ThemeData theme,
    required AppVisual visual,
    required ColorScheme scheme,
    required List<Map<String, dynamic>> regions,
  }) {
    if (_loading && _regions.isEmpty) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }

    if (_error != null && _regions.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off_outlined, size: 48, color: scheme.error),
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.error),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _refreshHotels,
                    icon: const Icon(Icons.refresh),
                    label: Text(context.tr('retry')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ];
    }

    final slivers = <Widget>[
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: _ChooseHotelHero(
            hotelCount: _totalHotels,
            regionCount: regions.length,
            isRefreshing: _refreshing,
            staffEntry: widget.staffEntry,
            onRegister: _openRegister,
          ),
        ),
      ),
      if (widget.staffEntry)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: _RegisterHotelCard(onTap: _openRegister),
          ),
        ),
      SliverPersistentHeader(
        pinned: true,
        delegate: _HotelSearchHeaderDelegate(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Material(
              elevation: 0,
              color: scheme.surface,
              child: TextField(
                controller: _search,
                decoration: InputDecoration(
                  hintText: context.tr('search_hotels'),
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor:
                      scheme.surfaceContainerHighest.withValues(alpha: 0.65),
                  border: OutlineInputBorder(
                    borderRadius: visual.radiusMd,
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: visual.radiusMd,
                    borderSide: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: 0.35),
                    ),
                  ),
                  isDense: true,
                ),
              ),
            ),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: FilledButton.tonalIcon(
            onPressed: _locatingNearMe
                ? null
                : (_nearMeActive ? _clearNearMe : _useNearMe),
            icon: _locatingNearMe
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.primary,
                    ),
                  )
                : Icon(
                    _nearMeActive
                        ? Icons.near_me_disabled_outlined
                        : Icons.near_me_rounded,
                  ),
            label: Text(
              _nearMeActive
                  ? context.tr('near_me_clear')
                  : context.tr('near_me_use'),
            ),
          ),
        ),
      ),
    ];

    if (!_nearMeActive && _coordinateHotelCount == 0 && !_loading) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(
              context.tr('near_me_no_coordinates'),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    if (_nearMeActive) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(
              context.tr('near_me_active_hint'),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    if (_regions.isNotEmpty && _error == null) {
      slivers.add(
        SliverToBoxAdapter(
          child: _HotelFilterPanel(
            priceRange: _priceRange,
            catalogFloor: _catalogFloor,
            catalogCeiling: _catalogCeiling,
            catalogHasPricing: _catalogHasPricing,
            priceDivisions: _priceSliderDivisions,
            sortBy: _sortBy,
            sortOptions: _sortOptions,
            regions: _availableRegions,
            selectedRegion: _selectedRegion,
            onlyWithPrices: _onlyWithPrices,
            hasActiveFilters: _hasActiveFilters,
            onPriceChanged: (v) => setState(() => _priceRange = v),
            onSortChanged: (v) => setState(() => _sortBy = v),
            onRegionChanged: (v) => setState(() => _selectedRegion = v),
            onOnlyWithPricesChanged: (v) =>
                setState(() => _onlyWithPrices = v),
            onClearFilters: _resetFilters,
          ),
        ),
      );
    }

    if (regions.isEmpty) {
      slivers.add(
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.travel_explore_outlined,
                      size: 56, color: scheme.outline),
                  const SizedBox(height: 16),
                  Text(
                    _queryTokens.isEmpty && !_hasActiveFilters
                        ? context.tr('no_hotels')
                        : context.tr('no_search_results'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                  if (_hasActiveFilters) ...[
                    const SizedBox(height: 16),
                    FilledButton.tonalIcon(
                      onPressed: _resetFilters,
                      icon: const Icon(Icons.filter_alt_off),
                      label: Text(context.tr('clear_filters')),
                    ),
                  ],
                  if (_queryTokens.isEmpty && !_hasActiveFilters) ...[
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _openRegister,
                      icon: const Icon(Icons.add_business_outlined),
                      label: Text(context.tr('register_hotel_cta')),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
      return slivers;
    }

    if (_error == null) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Icon(Icons.apartment, size: 16, color: scheme.primary),
                const SizedBox(width: 6),
                Text(
                  context.tr('hotels_found').replaceAll('{n}', '$_totalHotels'),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    for (var i = 0; i < regions.length; i++) {
      final block = regions[i];
      final region = (block['region'] ?? 'Other').toString();
      final hotels = (block['hotels'] as List<dynamic>?) ?? const [];
      final showRegionHeader = region.isNotEmpty;

      if (showRegionHeader) {
        slivers.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, i == 0 ? 4 : 16, 16, 10),
              child: _RegionHeader(name: region, count: hotels.length),
            ),
          ),
        );
      } else if (i == 0) {
        slivers.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Text(
                context.tr('search_results'),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        );
      }

      for (final raw in hotels.whereType<Map>()) {
        final hotel = Map<String, dynamic>.from(raw);
        final hid = (hotel['id'] ?? '').toString();
        slivers.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: _HotelSelectTile(
                hotel: hotel,
                region: region,
                onTap: () => _selectHotel(hotel),
                distanceKm: _hotelDistanceKm[hid],
              ),
            ),
          ),
        );
      }
    }

    slivers.add(const SliverPadding(padding: EdgeInsets.only(bottom: 108)));
    return slivers;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visual = AppVisual.of(context);
    final regions = _filteredRegions;
    final scheme = theme.colorScheme;

    return AppScaffold(
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 2,
        leading: widget.staffEntry ? const BackButton() : null,
        title: Text(
          widget.staffEntry
              ? context.tr('property_sign_in')
              : context.tr('choose_hotel'),
        ),
        actions: [
          IconButton(
            tooltip: context.tr('refresh_hotels'),
            onPressed: (_loading || _refreshing) ? null : _refreshHotels,
            icon: _refreshing
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.primary,
                    ),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
          const LanguagePickerButton(),
          IconButton(
            tooltip: context.tr('how_to'),
            onPressed: () => HotelHowToGuide.show(context),
            icon: const Icon(Icons.help_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshHotels,
          color: scheme.primary,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: _buildHotelPickerSlivers(
              context,
              theme: theme,
              visual: visual,
              scheme: scheme,
              regions: regions,
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        elevation: 4,
        onPressed: _openRegister,
        icon: const Icon(Icons.add_business_outlined),
        label: Text(context.tr('register_hotel')),
      ),
    );
  }
}

class _HotelFilterPanel extends StatelessWidget {
  const _HotelFilterPanel({
    required this.priceRange,
    required this.catalogFloor,
    required this.catalogCeiling,
    required this.catalogHasPricing,
    required this.priceDivisions,
    required this.sortBy,
    required this.sortOptions,
    required this.regions,
    required this.selectedRegion,
    required this.onlyWithPrices,
    required this.hasActiveFilters,
    required this.onPriceChanged,
    required this.onSortChanged,
    required this.onRegionChanged,
    required this.onOnlyWithPricesChanged,
    required this.onClearFilters,
  });

  final RangeValues priceRange;
  final double catalogFloor;
  final double catalogCeiling;
  final bool catalogHasPricing;
  final int priceDivisions;
  final String sortBy;
  final Map<String, String> sortOptions;
  final List<String> regions;
  final String? selectedRegion;
  final bool onlyWithPrices;
  final bool hasActiveFilters;
  final ValueChanged<RangeValues> onPriceChanged;
  final ValueChanged<String> onSortChanged;
  final ValueChanged<String?> onRegionChanged;
  final ValueChanged<bool> onOnlyWithPricesChanged;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visual = AppVisual.of(context);
    final clampedRange = RangeValues(
      priceRange.start.clamp(catalogFloor, catalogCeiling),
      priceRange.end.clamp(catalogFloor, catalogCeiling),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: visual.radiusMd,
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            initiallyExpanded: hasActiveFilters,
            leading: Icon(Icons.tune, size: 20, color: scheme.primary),
            title: Text(
              context.tr('filter_sort'),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            trailing: SizedBox(
              width: 200,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (hasActiveFilters)
                    TextButton(
                      onPressed: onClearFilters,
                      child: Text(context.tr('clear_filters')),
                    ),
                  Flexible(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: sortBy,
                        isDense: true,
                        isExpanded: true,
                        items: sortOptions.entries
                            .map(
                              (e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(
                                  context.tr(e.value),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) onSortChanged(v);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            children: [
              if (regions.isNotEmpty) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    context.tr('filter_by_region'),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(context.tr('all_regions')),
                          selected: selectedRegion == null,
                          onSelected: (_) => onRegionChanged(null),
                        ),
                      ),
                      ...regions.map(
                        (name) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(name),
                            selected: selectedRegion == name,
                            onSelected: (on) =>
                                onRegionChanged(on ? name : null),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(context.tr('only_with_prices')),
                subtitle: Text(
                  context.tr('only_with_prices_hint'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                value: onlyWithPrices,
                onChanged: onOnlyWithPricesChanged,
              ),
              if (catalogHasPricing) ...[
                const SizedBox(height: 4),
                Text(
                  context.tr('price_range'),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                RangeSlider(
                  values: clampedRange,
                  min: catalogFloor,
                  max: catalogCeiling,
                  divisions: priceDivisions,
                  labels: RangeLabels(
                    _ChooseHotelScreenState._formatPeso(clampedRange.start),
                    _ChooseHotelScreenState._formatPeso(clampedRange.end),
                  ),
                  onChanged: onPriceChanged,
                ),
                Text(
                  '${context.tr('catalog_range')}: '
                  '${_ChooseHotelScreenState._formatPeso(catalogFloor)} – '
                  '${_ChooseHotelScreenState._formatPeso(catalogCeiling)} · '
                  '${context.tr('selected')}: '
                  '${_ChooseHotelScreenState._formatPeso(clampedRange.start)} – '
                  '${_ChooseHotelScreenState._formatPeso(clampedRange.end)}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    context.tr('no_catalog_prices'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HotelSearchHeaderDelegate extends SliverPersistentHeaderDelegate {
  _HotelSearchHeaderDelegate({required this.child});

  final Widget child;

  @override
  double get minExtent => 64;

  @override
  double get maxExtent => 64;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _HotelSearchHeaderDelegate oldDelegate) {
    return true;
  }
}

class _RegisterHotelCard extends StatelessWidget {
  const _RegisterHotelCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visual = AppVisual.of(context);

    return Material(
      elevation: 0,
      color: scheme.primaryContainer.withValues(alpha: 0.45),
      borderRadius: visual.radiusMd,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: visual.radiusSm,
                ),
                child: const Icon(Icons.add_business_outlined, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('register_hotel_cta'),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.tr('register_hotel_hint'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChooseHotelHero extends StatelessWidget {
  const _ChooseHotelHero({
    this.hotelCount,
    this.regionCount,
    this.isRefreshing = false,
    this.staffEntry = false,
    this.onRegister,
  });

  final int? hotelCount;
  final int? regionCount;
  final bool isRefreshing;
  final bool staffEntry;
  final VoidCallback? onRegister;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final visual = AppVisual.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: visual.radiusLg,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer.withValues(alpha: 0.85),
            scheme.surface,
          ],
        ),
        boxShadow: visual.cardShadow,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: visual.radiusMd,
                boxShadow: [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const MadyawLogoWidget(
                size: 72,
                drawProgress: 1,
                showWordmark: false,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('select_property'),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.tr('choose_hotel_hint'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  if (hotelCount != null) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _StatChip(
                          icon: Icons.apartment_outlined,
                          label: '$hotelCount',
                        ),
                        if (regionCount != null && regionCount! > 0)
                          _StatChip(
                            icon: Icons.map_outlined,
                            label: '$regionCount ${context.tr('regions')}',
                          ),
                        if (isRefreshing)
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: scheme.primary,
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: scheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _RegionHeader extends StatelessWidget {
  const _RegionHeader({required this.name, required this.count});

  final String name;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.location_city_rounded,
              size: 18, color: scheme.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            name,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$count',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _HotelSelectTile extends StatelessWidget {
  const _HotelSelectTile({
    required this.hotel,
    required this.region,
    required this.onTap,
    this.distanceKm,
  });

  final Map<String, dynamic> hotel;
  final String region;
  final VoidCallback onTap;
  final double? distanceKm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final visual = AppVisual.of(context);
    final name = (hotel['name'] ?? 'Hotel').toString();
    final displayAddress = hotelDisplayAddress(hotel);
    final city = (hotel['city'] ?? region).toString();
    final hotelRegion = (hotel['region'] ?? '').toString();
    final roomCount = (hotel['room_count'] as num?)?.toInt() ?? 0;
    final priceLabel = _ChooseHotelScreenState._priceLabelForHotel(context, hotel);
    final minP = (hotel['min_price'] as num?)?.toDouble() ?? 0;
    final maxP = (hotel['max_price'] as num?)?.toDouble() ?? 0;
    final hasPrice = minP > 0 || maxP > 0;
    final rawBanner = (hotel['banner_url'] ?? '').toString().trim();
    final bannerUrl =
        rawBanner.isNotEmpty ? ChatAttachment.resolveMediaUrl(rawBanner) : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: visual.radiusMd,
          boxShadow: visual.cardShadow,
        ),
        child: Material(
          color: scheme.surface,
          borderRadius: visual.radiusMd,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (bannerUrl.isNotEmpty)
                  SizedBox(
                    height: 120,
                    child: Image.network(
                      bannerUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => ColoredBox(
                        color: scheme.surfaceContainerHighest,
                        child: Icon(Icons.apartment_rounded,
                            size: 40, color: scheme.outline),
                      ),
                    ),
                  ),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: 5,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              scheme.primary,
                              scheme.primary.withValues(alpha: 0.5),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
                          child: Row(
                            children: [
                              if (bannerUrl.isEmpty)
                                CircleAvatar(
                                  radius: 26,
                                  backgroundColor: scheme.primaryContainer,
                                  child: Icon(Icons.apartment_rounded,
                                      color: scheme.primary, size: 28),
                                )
                              else
                                const SizedBox(width: 0),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        name,
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    if (distanceKm != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: scheme.secondaryContainer,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          formatDistanceKm(distanceKm!),
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                            color: scheme.onSecondaryContainer,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                if (hotelRegion.isNotEmpty || city.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      hotelRegion.isNotEmpty
                                          ? '$hotelRegion · $city'
                                          : city,
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                        color: scheme.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 8),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: scheme.surfaceContainerHigh,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: scheme.outlineVariant
                                          .withValues(alpha: 0.45),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.location_on_outlined,
                                        size: 18,
                                        color: scheme.primary,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          displayAddress,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            height: 1.35,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: hasPrice
                                            ? scheme.tertiaryContainer
                                            : scheme.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.payments_outlined,
                                            size: 14,
                                            color: hasPrice
                                                ? scheme.onTertiaryContainer
                                                : scheme.onSurfaceVariant,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            priceLabel,
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              color: hasPrice
                                                  ? scheme.onTertiaryContainer
                                                  : scheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (roomCount > 0)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: scheme.primaryContainer
                                              .withValues(alpha: 0.65),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.bed_outlined,
                                              size: 14,
                                              color: scheme.onPrimaryContainer,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              context.tr('rooms_count')
                                                  .replaceAll(
                                                      '{n}', '$roomCount'),
                                              style: theme.textTheme.labelSmall
                                                  ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                                color:
                                                    scheme.onPrimaryContainer,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios_rounded,
                              size: 16, color: scheme.outline),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HotelRegisterScreen extends StatefulWidget {
  const HotelRegisterScreen({super.key, this.fromStaffEntry = false});

  /// Opened from property sign-in / staff hotel picker.
  final bool fromStaffEntry;

  @override
  State<HotelRegisterScreen> createState() => _HotelRegisterScreenState();
}

class _HotelRegisterScreenState extends State<HotelRegisterScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();
  final _hotelName = TextEditingController();
  final _contact = TextEditingController();
  PhilippineAddressSelection _address = const PhilippineAddressSelection();
  final _adminEmail = TextEditingController();
  final _totalRooms = TextEditingController(text: '1');
  bool _busy = false;
  bool _locatingGps = false;
  String? _error;
  ({double lat, double lng})? _previewCoords;

  int _estimatedWelcomeCredits() {
    final n = int.tryParse(_totalRooms.text.trim()) ?? 0;
    if (n < 1) return 0;
    return ((n + 19) ~/ 20) * 10000;
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _password2.dispose();
    _hotelName.dispose();
    _contact.dispose();
    _adminEmail.dispose();
    _totalRooms.dispose();
    super.dispose();
  }

  Future<({double lat, double lng})?> _resolveRegistrationCoordinates() async {
    try {
      return await NearbyHotelsService.currentPosition();
    } on NearbyHotelsException catch (e) {
      if (!mounted) return null;
      final message = switch (e.code) {
        'permission_denied' || 'permission_denied_forever' =>
          'Location permission lets guests find your hotel with Near me.',
        'location_services_disabled' =>
          'Turn on location services to save your hotel GPS pin.',
        _ => 'Could not read your GPS right now.',
      };
      final continueWithout = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Hotel GPS location'),
          content: Text(
            '$message\n\nYou can register without GPS, but your hotel will not '
            'appear in Near me searches until coordinates are saved.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Try again'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Continue without GPS'),
            ),
          ],
        ),
      );
      if (continueWithout == true) return null;
      if (e.code == 'permission_denied' || e.code == 'permission_denied_forever') {
        await Geolocator.openAppSettings();
      }
      rethrow;
    }
  }

  Future<void> _previewLocation() async {
    if (_locatingGps) return;
    HapticFeedback.lightImpact();
    setState(() {
      _locatingGps = true;
      _error = null;
    });
    try {
      final pos = await NearbyHotelsService.currentPosition();
      if (!mounted) return;
      setState(() {
        _previewCoords = pos;
        _locatingGps = false;
      });
      showAppMessage(context, 'GPS location saved for this hotel.');
    } on NearbyHotelsException catch (e) {
      if (!mounted) return;
      final message = switch (e.code) {
        'permission_denied' || 'permission_denied_forever' =>
          'Location permission is required to save GPS coordinates.',
        'location_services_disabled' =>
          'Turn on location services, then try again.',
        _ => 'Could not read GPS. Try again.',
      };
      setState(() {
        _locatingGps = false;
        _error = message;
      });
      final openSettings = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Hotel GPS location'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Open settings'),
            ),
          ],
        ),
      );
      if (openSettings == true) {
        if (e.code == 'location_services_disabled') {
          await Geolocator.openLocationSettings();
        } else {
          await Geolocator.openAppSettings();
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _locatingGps = false;
        _error = 'Could not read GPS. Try again.';
      });
    }
  }

  String? _validateForm() {
    final hotelName = _hotelName.text.trim();
    if (hotelName.isEmpty) return 'Enter your hotel name.';
    final rooms = int.tryParse(_totalRooms.text.trim()) ?? 0;
    if (rooms < 1) return 'Enter the total number of rooms (at least 1).';
    if (!_address.isComplete) {
      return 'Select region, province, city, and barangay.';
    }
    final contact = _contact.text.trim();
    if (contact.isEmpty) return 'Enter a contact number.';
    final email = _adminEmail.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      return 'Enter a valid admin email address.';
    }
    final username = _username.text.trim();
    if (username.isEmpty) return 'Choose an owner username.';
    if (username.contains(' ')) {
      return 'Username cannot contain spaces.';
    }
    if (_password.text.length < 6) {
      return 'Password must be at least 6 characters.';
    }
    if (_password.text != _password2.text) {
      return 'Passwords do not match.';
    }
    return null;
  }

  Future<Map<String, dynamic>> _buildRegistrationPayload() async {
    final coords = _previewCoords ?? await _resolveRegistrationCoordinates();
    if (mounted && coords != null) {
      setState(() => _previewCoords = coords);
    }

    final payload = <String, dynamic>{
      'username': _username.text.trim(),
      'password': _password.text,
      'password_confirmation': _password2.text,
      'hotel_name': _hotelName.text.trim(),
      ..._address.toRegisterPayload(),
      'contact_number': _contact.text.trim(),
      'admin_email': _adminEmail.text.trim().toLowerCase(),
      'total_rooms': int.tryParse(_totalRooms.text.trim()) ?? 1,
    };
    if (coords != null) {
      payload['latitude'] = coords.lat;
      payload['longitude'] = coords.lng;
    }
    return payload;
  }

  Future<void> _finishRegistration(Map<String, dynamic>? data) async {
    final hid = data?['hotel_id']?.toString();
    final token = data?['token']?.toString();
    if (hid == null || hid.isEmpty || token == null || token.isEmpty) {
      setState(() {
        _error = 'Unexpected response from server.';
        _busy = false;
      });
      return;
    }
    final name = _hotelName.text.trim();
    await AuthStorage.setHotelContext(id: hid, name: name);
    await AuthStorage.setPortalAuth(token: token, role: 'admin');
    await AuthStorage.clearGuestAuth();
    await AuthStorage.clearHotelsDirectoryCache();
    if (!mounted) return;
    await showHotelRegistrationCredentialsDialog(
      context,
      hotelName: name,
      portalAccounts: data?['portal_accounts'] as Map<String, dynamic>?,
      welcomeCredits: data?['welcome_credits'] as Map<String, dynamic>?,
      verifiedEmail: (data?['email_verified'] == true) ? _adminEmail.text.trim() : null,
      registrationUsername: _username.text.trim(),
      registrationPassword: _password.text,
    );
    if (!mounted) return;
    final session = HotelSession(hotelId: hid, hotelName: name);
    hotelSessionNotifier.value = session;
    await Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => const AdminDashboardScreen(isSuperAdmin: false),
      ),
      (_) => false,
    );
    if (!mounted) return;
    showAppMessage(
      context,
      'Hotel ready. Add rooms under Settings → Categories & rooms, then use Walk-in to book guests.',
    );
  }

  Future<void> _submitWithEmailOtp(Map<String, dynamic> payload) async {
    final sendRes = await publicDio().post<Map<String, dynamic>>(
      '/hotel/register/send-code',
      data: payload,
    );
    final token = (sendRes.data?['registration_token'] ?? '').toString();
    if (token.isEmpty) {
      setState(() {
        _error = 'Could not start email verification.';
        _busy = false;
      });
      return;
    }
    final masked = (sendRes.data?['email_masked'] ?? _adminEmail.text.trim()).toString();
    if (!mounted) return;

    final otpCtrl = TextEditingController();
    var resendBusy = false;
    final verified = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          Future<void> resendCode() async {
            if (resendBusy) return;
            setLocal(() => resendBusy = true);
            try {
              await publicDio().post<Map<String, dynamic>>(
                '/hotel/register/resend-code',
                data: {'registration_token': token},
              );
              if (ctx.mounted) {
                showAppMessage(ctx, 'A new verification code was sent.');
              }
            } on DioException catch (e) {
              if (ctx.mounted) {
                showAppMessage(ctx, dioErrorMessage(e), isError: true);
              }
            } finally {
              if (ctx.mounted) setLocal(() => resendBusy = false);
            }
          }

          return AlertDialog(
            title: const Text('Verify your email'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Enter the 6-digit code sent to $masked.'),
                const SizedBox(height: 12),
                TextField(
                  controller: otpCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: 'Verification code',
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: resendBusy ? null : resendCode,
                child: const Text('Resend code'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (otpCtrl.text.trim().length != 6) {
                    showAppMessage(ctx, 'Enter the 6-digit code.');
                    return;
                  }
                  Navigator.of(ctx).pop(true);
                },
                child: const Text('Verify & create hotel'),
              ),
            ],
          );
        },
      ),
    );
    final code = otpCtrl.text.trim();
    otpCtrl.dispose();
    if (verified != true || !mounted) {
      setState(() => _busy = false);
      return;
    }

    final verifyRes = await publicDio().post<Map<String, dynamic>>(
      '/hotel/register/verify',
      data: {
        'registration_token': token,
        'code': code,
      },
    );
    await _finishRegistration(verifyRes.data);
  }

  Future<void> _submit() async {
    final validationError = _validateForm();
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final payload = await _buildRegistrationPayload();

      try {
        final res = await publicDio().post<Map<String, dynamic>>(
          '/hotel/register',
          data: payload,
        );
        await _finishRegistration(res.data);
      } on DioException catch (e) {
        if (e.response?.statusCode == 400) {
          final msg = (e.response?.data is Map
                  ? (e.response!.data as Map)['message']
                  : '')
              .toString();
          if (msg.toLowerCase().contains('send-code') ||
              msg.toLowerCase().contains('verification')) {
            await _submitWithEmailOtp(payload);
            return;
          }
        }
        rethrow;
      }
    } on NearbyHotelsException {
      if (mounted) setState(() => _busy = false);
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          _error = dioErrorMessage(e);
          _busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppScaffold(
      appBar: AppBar(
        title: Text(
          widget.fromStaffEntry ? 'Register your property' : 'Create hotel',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
      if (widget.fromStaffEntry) ...[
        Text(
          'Your hotel will appear in the property list after registration. '
          'All details are saved to your MADYAWPH account.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 16),
      ],
      TextField(
        controller: _hotelName,
        decoration: const InputDecoration(labelText: 'Hotel name', border: OutlineInputBorder()),
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _totalRooms,
        decoration: InputDecoration(
          labelText: 'Total number of rooms *',
          border: const OutlineInputBorder(),
          helperText:
              'Welcome credits: 1–20 rooms → ₱10,000; 21–40 → ₱20,000; '
              '41–60 → ₱30,000 (+₱10,000 per 20 rooms). '
              'Estimated: ₱${_estimatedWelcomeCredits()}.',
        ),
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.next,
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 12),
      PhilippineAddressPicker(
        onChanged: (v) => setState(() => _address = v),
      ),
      const SizedBox(height: 12),
      Card(
        elevation: 0,
        color: scheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.location_on_outlined, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Hotel GPS pin',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'We use your phone GPS so guests can find your hotel with Near me. '
                'Your typed address is still saved.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              if (_previewCoords != null) ...[
                const SizedBox(height: 8),
                Text(
                  'GPS: ${_previewCoords!.lat.toStringAsFixed(5)}, '
                  '${_previewCoords!.lng.toStringAsFixed(5)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: (_busy || _locatingGps) ? null : _previewLocation,
                  icon: _locatingGps
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.primary,
                          ),
                        )
                      : const Icon(Icons.my_location_outlined, size: 18),
                  label: Text(
                    _locatingGps
                        ? 'Getting GPS…'
                        : (_previewCoords == null
                            ? 'Use current location'
                            : 'Refresh GPS'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _contact,
        decoration: const InputDecoration(labelText: 'Contact number', border: OutlineInputBorder()),
        keyboardType: TextInputType.phone,
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _adminEmail,
        decoration: const InputDecoration(
          labelText: 'Admin email',
          border: OutlineInputBorder(),
        ),
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: 16),
      const Divider(),
      const SizedBox(height: 8),
      TextField(
        controller: _username,
        decoration: const InputDecoration(
          labelText: 'Owner username (internal)',
          border: OutlineInputBorder(),
          helperText: 'For super admin sign-in; not used on the hotel picker',
        ),
        autocorrect: false,
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: 12),
      AppPasswordField(
        controller: _password,
        labelText: 'Password',
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: 12),
      AppPasswordField(
        controller: _password2,
        labelText: 'Confirm password',
      ),
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ],
      const SizedBox(height: 20),
      FilledButton(
        onPressed: _busy ? null : _submit,
        child: _busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Create hotel'),
      ),
        ],
      ),
    );
  }
}

// --- Role menu ---

/// Legacy alias — property staff now use [SystemAccessScreen].
class RoleMenuScreen extends StatelessWidget {
  const RoleMenuScreen({super.key, required this.session});

  final HotelSession session;

  @override
  Widget build(BuildContext context) => SystemAccessScreen(session: session);
}

class PortalLoginScreen extends StatefulWidget {
  const PortalLoginScreen({super.key, required this.role});

  final String role;

  @override
  State<PortalLoginScreen> createState() => _PortalLoginScreenState();
}

class _PortalLoginScreenState extends State<PortalLoginScreen> {
  final _id = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _id.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final hotelId = await AuthStorage.hotelId();
    if (hotelId == null || hotelId.isEmpty) {
      setState(() => _error = context.tr('sign_in_property_first'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final trimmed = _id.text.trim();
      final body = <String, dynamic>{
        'role': widget.role,
        'password': _pass.text,
        'hotel_id': hotelId,
      };
      if (trimmed.contains('@')) {
        body['email'] = trimmed;
      } else {
        body['username'] = trimmed;
      }
      final res = await publicDio().post<Map<String, dynamic>>('/auth/portal-login', data: body);
      final token = res.data?['token'] as String?;
      if (token == null || token.isEmpty) {
        setState(() {
          _error = 'No token returned.';
          _busy = false;
        });
        return;
      }
      final serverRole = res.data?['role'] as String?;
      await AuthStorage.setPortalAuth(
        token: token,
        role: (serverRole != null && serverRole.isNotEmpty) ? serverRole : widget.role,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on DioException catch (e) {
      setState(() {
        _error = dioErrorMessage(e);
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = switch (widget.role) {
      'super_admin' => 'Super administrator',
      'admin' => 'Admin / Front desk',
      'owner' => 'Hotel owner',
      _ => 'Staff',
    };
    return AppScaffold(
      appBar: AppBar(title: Text('$label sign-in')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            widget.role == 'owner'
                ? 'Use your owner or super-admin username and registration password.'
                : widget.role == 'admin'
                ? 'Use your administrator username (often ends with _admin), '
                    'or your super-admin username, and the password from hotel registration.'
                : widget.role == 'super_admin'
                    ? 'Use your hotel registration username (property login name) and password.'
                    : 'Use your $label account (name or email) and password for this hotel.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _id,
            decoration: const InputDecoration(
              labelText: 'Username or email',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
          ),
          const SizedBox(height: 12),
          AppPasswordField(
            controller: _pass,
            labelText: 'Password',
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Sign in'),
          ),
        ],
      ),
    );
  }
}

class GuestRoomLoginScreen extends StatefulWidget {
  const GuestRoomLoginScreen({
    super.key,
    required this.hotelId,
    this.hotelName,
  });

  final String hotelId;
  final String? hotelName;

  @override
  State<GuestRoomLoginScreen> createState() => _GuestRoomLoginScreenState();
}

class _GuestRoomLoginScreenState extends State<GuestRoomLoginScreen> {
  final _room = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _room.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pwd = _password.text.trim();
    if (pwd.length != 4) {
      setState(() => _error = 'Room password must be exactly 4 characters.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await publicDio().post<Map<String, dynamic>>(
        '/guest/login',
        data: {
          'hotel_id': widget.hotelId,
          'room': _room.text.trim(),
          'password': pwd,
        },
      );
      final token = res.data?['guest_token'] as String?;
      if (token == null || token.isEmpty) {
        setState(() {
          _error = 'No guest_token in response.';
          _busy = false;
        });
        return;
      }
      await AuthStorage.setGuestToken(token);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on DioException catch (e) {
      setState(() {
        _error = dioErrorMessage(e);
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hotelLabel = (widget.hotelName ?? '').trim();

    return AppScaffold(
      appBar: AppBar(title: const Text('Guest sign-in')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (hotelLabel.isNotEmpty) ...[
            Text(
              hotelLabel,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Enter your room number and the 4-character password from the front desk.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _room,
            decoration: const InputDecoration(labelText: 'Room number', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          AppPasswordField(
            controller: _password,
            labelText: 'Room password (4 characters)',
            helperText: 'Exactly 4 letters or numbers (e.g. 1234, a1b2)',
            counterText: '',
            maxLength: 4,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Continue'),
          ),
        ],
      ),
    );
  }
}
