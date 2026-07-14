import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';

import '../auth_storage.dart';
import '../branding/madyaw_logo_widget.dart';
import '../data/philippine_destination_presets.dart';
import '../dio_client.dart';
import '../locale_controller.dart';
import '../ui/app_visual.dart';
import '../widgets/app_install_share_dialog.dart';
import '../widgets/language_picker_button.dart';
import '../widgets/philippine_destination_field.dart';
import 'customer_browse_layout.dart';
import 'customer_search_context.dart';
import 'hotel_search_results_screen.dart';
import 'guest_portal_qr_scan_screen.dart';
import 'hotel_screens.dart';
import 'member_login_screen.dart';

/// Agoda-style public landing: search hotels, then browse/book as a guest.
class PublicHotelSearchScreen extends StatefulWidget {
  const PublicHotelSearchScreen({
    super.key,
    this.embeddedInMemberDashboard = false,
  });

  /// When true, renders as a member-dashboard tab (no outer scaffold / no member login CTA).
  final bool embeddedInMemberDashboard;

  @override
  State<PublicHotelSearchScreen> createState() => _PublicHotelSearchScreenState();
}

class _PublicHotelSearchScreenState extends State<PublicHotelSearchScreen>
    with WidgetsBindingObserver {
  final _destinationCtrl = TextEditingController();
  List<Map<String, dynamic>> _allHotels = const [];
  bool _loading = false;
  bool _refreshingDirectory = false;
  bool _searching = false;
  String? _error;
  String? _selectedPresetQuery;
  DateTime _checkIn = DateTime.now();
  DateTime _checkOut = DateTime.now().add(const Duration(days: 1));
  int _rooms = 1;
  int _adults = 2;
  int _children = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _destinationCtrl.addListener(_onDestinationEdited);
    _bootstrapHotels();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Recover if a hung network call left the search spinner active.
    if (state == AppLifecycleState.resumed && _searching && mounted) {
      setState(() => _searching = false);
    }
  }

  void _onDestinationEdited() {
    final text = _destinationCtrl.text.trim();
    if (_selectedPresetQuery != null && text != _selectedPresetQuery) {
      setState(() => _selectedPresetQuery = null);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _destinationCtrl.removeListener(_onDestinationEdited);
    _destinationCtrl.dispose();
    super.dispose();
  }

  static const _directoryTimeout = Duration(seconds: 90);
  static const _searchTimeout = Duration(seconds: 95);

  Future<void> _bootstrapHotels() async {
    final cached = await AuthStorage.hotelsDirectoryCache();
    if (cached != null && cached.isNotEmpty) {
      try {
        _parseDirectory(jsonDecode(cached));
      } catch (_) {}
    }
    if (mounted) setState(() => _error = null);
    unawaited(_refreshHotelsDirectory(showSpinner: false));
  }

  Future<void> _loadHotels() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    await _refreshHotelsDirectory(showSpinner: true);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _refreshHotelsDirectory({required bool showSpinner}) async {
    if (showSpinner && mounted) {
      setState(() => _refreshingDirectory = true);
    }
    try {
      final res = await publicDio()
          .get<Map<String, dynamic>>('/hotels')
          .timeout(_directoryTimeout);
      final data = res.data;
      if (data != null && mounted) {
        await AuthStorage.setHotelsDirectoryCache(jsonEncode(data));
        _parseDirectory(data);
      }
    } on TimeoutException {
      if (_allHotels.isEmpty && mounted) {
        setState(() {
          _error =
              'Loading properties timed out. You can still search — pull down to retry.';
        });
      }
    } on DioException catch (e) {
      if (_allHotels.isEmpty && mounted) {
        setState(() => _error = dioErrorMessage(e));
      }
    } catch (e) {
      if (_allHotels.isEmpty && mounted) {
        setState(() => _error = '$e');
      }
    } finally {
      if (mounted) setState(() => _refreshingDirectory = false);
    }
  }

  void _parseDirectory(dynamic data, {bool notify = true}) {
    if (data is! Map<String, dynamic>) return;
    final regions = data['regions'] as List<dynamic>? ?? const [];
    final flat = <Map<String, dynamic>>[];
    for (final region in regions) {
      if (region is! Map) continue;
      final hotels = region['hotels'] as List<dynamic>? ?? const [];
      for (final h in hotels) {
        if (h is Map) {
          flat.add(Map<String, dynamic>.from(h));
        }
      }
    }
    if (notify && mounted) {
      setState(() => _allHotels = flat);
    } else {
      _allHotels = flat;
    }
  }

  Future<void> _ensureHotelsLoaded() async {
    if (_allHotels.isNotEmpty) return;
    final cached = await AuthStorage.hotelsDirectoryCache();
    if (cached != null && cached.isNotEmpty) {
      try {
        _parseDirectory(jsonDecode(cached), notify: false);
      } catch (_) {}
    }
    if (_allHotels.isNotEmpty) return;
    try {
      final res = await publicDio()
          .get<Map<String, dynamic>>('/hotels')
          .timeout(_directoryTimeout);
      final data = res.data;
      if (data != null) {
        await AuthStorage.setHotelsDirectoryCache(jsonEncode(data));
        _parseDirectory(data, notify: false);
      }
    } on TimeoutException {
      return;
    } on DioException {
      return;
    }
  }

  int get _nightCount {
    final nights = _checkOut.difference(_checkIn).inDays;
    return nights > 0 ? nights : 1;
  }

  String _fmtDate(DateTime d) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${days[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}';
  }

  void _selectPreset(PhDestinationPreset preset) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedPresetQuery = preset.searchQuery;
      _destinationCtrl.text = preset.searchQuery;
    });
  }

  Future<void> _openDestinationPicker() async {
    final grouped = PhilippineDestinationPresets.byRegion;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          maxChildSize: 0.92,
          minChildSize: 0.45,
          builder: (_, scroll) => SafeArea(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                Text(
                  context.tr('philippine_destinations'),
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  context.tr('tap_city_search'),
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                ...grouped.entries.map((entry) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8, top: 4),
                        child: Text(
                          entry.key,
                          style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: Theme.of(ctx).colorScheme.primary,
                              ),
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: entry.value.map((preset) {
                          final selected =
                              _selectedPresetQuery == preset.searchQuery;
                          return FilterChip(
                            label: Text('${preset.icon} ${preset.label}'),
                            selected: selected,
                            onSelected: (_) {
                              _selectPreset(preset);
                              Navigator.pop(ctx);
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                    ],
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickDate({required bool checkIn}) async {
    final initial = checkIn ? _checkIn : _checkOut;
    final first = checkIn
        ? DateTime.now().subtract(const Duration(days: 1))
        : _checkIn;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (checkIn) {
        _checkIn = picked;
        if (!_checkOut.isAfter(_checkIn)) {
          _checkOut = _checkIn.add(const Duration(days: 1));
        }
      } else {
        _checkOut = picked.isAfter(_checkIn)
            ? picked
            : _checkIn.add(const Duration(days: 1));
      }
    });
  }

  Future<void> _pickGuests() async {
    var rooms = _rooms;
    var adults = _adults;
    var children = _children;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.tr('rooms_guests'),
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 16),
                _GuestCounterRow(
                  label: context.tr('rooms_label'),
                  subtitle: context.tr('rooms_sub'),
                  value: rooms,
                  min: 1,
                  onChanged: (v) => setLocal(() => rooms = v),
                ),
                const Divider(height: 24),
                _GuestCounterRow(
                  label: context.tr('adults'),
                  subtitle: context.tr('adults_sub'),
                  value: adults,
                  min: 1,
                  onChanged: (v) => setLocal(() => adults = v),
                ),
                const Divider(height: 24),
                _GuestCounterRow(
                  label: context.tr('children'),
                  subtitle: context.tr('children_sub'),
                  value: children,
                  onChanged: (v) => setLocal(() => children = v),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _rooms = rooms;
                      _adults = adults;
                      _children = children;
                    });
                    Navigator.pop(ctx);
                  },
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(context.tr('apply')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _guestPartyLine(BuildContext context) => context.tr('guest_party_line', {
        'rooms': '$_rooms',
        'adults': '$_adults',
        'children': '$_children',
      });

  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static const _locationStopWords = {
    'city',
    'municipality',
    'province',
    'region',
    'of',
    'the',
    'and',
  };

  List<String> _significantLocationTokens(String query) {
    return query
        .toLowerCase()
        .replaceAll(RegExp(r'[-_,./()]'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.length >= 2 && !_locationStopWords.contains(t))
        .toList();
  }

  bool _hotelMatchesDestination(Map<String, dynamic> hotel, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final hay = [
      hotel['name'],
      hotel['city'],
      hotel['province'],
      hotel['region'],
      hotel['barangay'],
      hotel['location'],
    ].map((v) => (v ?? '').toString().toLowerCase()).join(' ');
    if (hay.contains(q)) return true;
    final tokens = _significantLocationTokens(q);
    if (tokens.isEmpty) return hay.contains(q);
    return tokens.every((t) => hay.contains(t));
  }

  List<Map<String, dynamic>> _fallbackDirectorySearch({bool usedLegacyApi = false}) {
    final q = _destinationCtrl.text.trim();
    var list = _allHotels;
    if (q.isNotEmpty) {
      list = list.where((h) => _hotelMatchesDestination(h, q)).toList();
    }
    return list.map((h) {
      final roomCount = (h['room_count'] as num?)?.toInt() ?? 0;
      return {
        ...h,
        'available_rooms': roomCount,
        'min_price': (h['min_price'] as num?)?.toDouble() ?? 0,
        if (usedLegacyApi) 'legacy_search': true,
      };
    }).toList();
  }

  Map<String, dynamic> _searchQueryParams({bool includeDestination = true}) {
    return {
      if (includeDestination && _destinationCtrl.text.trim().isNotEmpty)
        'q': _destinationCtrl.text.trim(),
      'check_in': _isoDate(_checkIn),
      'check_out': _isoDate(_checkOut),
      'rooms': _rooms,
      'adults': _adults,
      'children': _children,
    };
  }

  Future<({List<Map<String, dynamic>> hotels, bool usedLegacy, bool broadened})>
      _fetchSearchResults() async {
    try {
      final res = await publicDio().get<Map<String, dynamic>>(
        '/hotels/search',
        queryParameters: _searchQueryParams(),
      );
      var raw = res.data?['hotels'] as List<dynamic>? ?? const [];
      var hotels =
          raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      var broadened = false;
      if (hotels.isEmpty && _destinationCtrl.text.trim().isNotEmpty) {
        final retry = await publicDio().get<Map<String, dynamic>>(
          '/hotels/search',
          queryParameters: _searchQueryParams(includeDestination: false),
        );
        raw = retry.data?['hotels'] as List<dynamic>? ?? const [];
        hotels = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        broadened = hotels.isNotEmpty;
      }
      if (hotels.isEmpty) {
        if (_allHotels.isEmpty) {
          await _ensureHotelsLoaded();
        }
        final fallback = _fallbackDirectorySearch(usedLegacyApi: true);
        if (fallback.isNotEmpty) {
          return (hotels: fallback, usedLegacy: true, broadened: false);
        }
      }
      return (hotels: hotels, usedLegacy: false, broadened: broadened);
    } on DioException catch (e) {
      if (e.response?.statusCode != 404 && e.response?.statusCode != 501) {
        rethrow;
      }
      if (_allHotels.isEmpty) {
        await _ensureHotelsLoaded();
      }
      return (
        hotels: _fallbackDirectorySearch(usedLegacyApi: true),
        usedLegacy: true,
        broadened: false,
      );
    }
  }

  Future<void> _search() async {
    if (_searching) return;
    HapticFeedback.mediumImpact();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _searching = true);
    try {
      final result = await _fetchSearchResults().timeout(
        _searchTimeout,
        onTimeout: () {
          throw TimeoutException('Hotel search timed out');
        },
      );
      final hotels = result.hotels;
      final usedLegacy = result.usedLegacy;
      final broadened = result.broadened;
      final search = CustomerSearchContext(
        checkIn: _checkIn,
        checkOut: _checkOut,
        rooms: _rooms,
        adults: _adults,
        children: _children,
        destinationQuery: _destinationCtrl.text.trim(),
      );
      if (!mounted) return;
      if (usedLegacy) {
        showAppMessage(context, context.tr('legacy_search_hint'));
      } else if (broadened) {
        showAppMessage(context, context.tr('broadened_search_hint'));
      }
      await Navigator.of(context).push<void>(
        PageRouteBuilder<void>(
          pageBuilder: (_, animation, __) => FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: HotelSearchResultsScreen(
              hotels: hotels,
              search: search,
            ),
          ),
          transitionDuration: const Duration(milliseconds: 280),
        ),
      );
    } on TimeoutException {
      if (!mounted) return;
      showAppMessage(
        context,
        'Search took too long. Check your connection, then try again.',
        isError: true,
        actionLabel: 'Retry',
        onAction: _search,
      );
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(
        context,
        dioErrorMessage(e),
        isError: true,
        actionLabel: 'Retry',
        onAction: _search,
      );
    } catch (e) {
      if (!mounted) return;
      showAppMessage(context, '$e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _openStaffPropertyLogin() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const PropertyStaffEntryScreen(),
      ),
    );
  }

  void _openGuestQrScanner() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const GuestPortalQrScanScreen(),
      ),
    );
  }

  void _openShareAppInstallQr() {
    showAppInstallShareDialog(context);
  }

  void _openMemberLogin() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const MemberLoginScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visual = AppVisual.of(context);
    final size = MediaQuery.sizeOf(context);
    final wideLandscape = customerUseWideBrowseLayout(context) && size.width >= 640;
    final embedded = widget.embeddedInMemberDashboard;

    final content = Column(
      children: [
        if (!embedded)
          Padding(
            padding: EdgeInsets.fromLTRB(16, wideLandscape ? 6 : 10, 12, 0),
            child: Row(
              children: [
                MadyawLogoWidget(
                  size: wideLandscape ? 44 : 52,
                  glowStrength: 0.15,
                  showWordmark: true,
                  showBrandLine: false,
                  brandReveal: 1,
                ),
                const Spacer(),
                const LanguagePickerButton(),
                IconButton(
                  tooltip: 'Share app — install QR',
                  onPressed: _openShareAppInstallQr,
                  icon: const Icon(Icons.share_outlined),
                ),
                IconButton(
                  tooltip: 'Scan hotel guest QR',
                  onPressed: _openGuestQrScanner,
                  icon: const Icon(Icons.qr_code_scanner_outlined),
                ),
                IconButton(
                  tooltip: context.tr('property_sign_in'),
                  onPressed: _openStaffPropertyLogin,
                  icon: const Icon(Icons.badge_outlined),
                ),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 12, 0),
            child: Row(
              children: [
                Icon(Icons.card_membership, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Member browse',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                const LanguagePickerButton(),
              ],
            ),
          ),
        if (wideLandscape)
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 12, 16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('where_to_go'),
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                                height: 1.15,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          context.tr('search_stays_sub'),
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                                height: 1.35,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: RefreshIndicator(
                    onRefresh: _loadHotels,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(12, 8, 20, 28),
                      child: _buildSearchScrollContent(
                        context,
                        scheme,
                        visual,
                        showMemberLogin: !embedded,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadHotels,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer
                                  .withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: scheme.primary.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.travel_explore,
                                    size: 18, color: scheme.primary),
                                const SizedBox(width: 8),
                                Text(
                                  context.tr('book_a_stay'),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: scheme.onPrimaryContainer,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            context.tr('where_to_go'),
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.5,
                                  height: 1.15,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            context.tr('search_stays_sub'),
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  height: 1.35,
                                ),
                          ),
                        ],
                      ),
                    ),
                    _buildSearchScrollContent(
                      context,
                      scheme,
                      visual,
                      showMemberLogin: !embedded,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );

    if (embedded) {
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: visual.scaffoldGradient(scheme),
        ),
        child: content,
      );
    }

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: visual.scaffoldGradient(scheme),
        ),
        child: SafeArea(child: content),
      ),
    );
  }

  Widget _buildSearchScrollContent(
    BuildContext context,
    ColorScheme scheme,
    AppVisual visual, {
    bool showMemberLogin = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: visual.radiusLg,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                scheme.surfaceContainerLow,
                scheme.surfaceContainerHighest.withValues(alpha: 0.55),
              ],
            ),
            boxShadow: visual.elevatedShadow,
            border: Border.all(
              color: scheme.primary.withValues(alpha: 0.12),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.map_outlined, color: scheme.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr('find_your_room'),
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            context.tr('tap_city_search'),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                PhilippineDestinationField(
                  controller: _destinationCtrl,
                  hintText: context.tr('browse_ph_cities'),
                  onSelected: (entry) {
                    setState(() {
                      _selectedPresetQuery = entry.searchQuery;
                    });
                  },
                ),
                const SizedBox(height: 14),
                Text(
                  context.tr('popular_destinations'),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 42,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: PhilippineDestinationPresets.popular.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      if (i == PhilippineDestinationPresets.popular.length) {
                        return ActionChip(
                          avatar: const Icon(Icons.grid_view, size: 18),
                          label: Text(context.tr('all_cities')),
                          onPressed: _openDestinationPicker,
                        );
                      }
                      final preset = PhilippineDestinationPresets.popular[i];
                      final selected =
                          _selectedPresetQuery == preset.searchQuery;
                      return FilterChip(
                        label: Text(
                          '${preset.icon} ${preset.label}',
                          style: TextStyle(
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                        selected: selected,
                        selectedColor: scheme.primaryContainer,
                        checkmarkColor: scheme.primary,
                        onSelected: (_) => _selectPreset(preset),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _DateTile(
                        label: context.tr('check_in'),
                        value: _fmtDate(_checkIn),
                        onTap: () => _pickDate(checkIn: true),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              context.tr('nights_count', {
                                'n': '$_nightCount',
                              }),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: scheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Icon(Icons.arrow_forward,
                              size: 16, color: scheme.outline),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _DateTile(
                        label: context.tr('check_out'),
                        value: _fmtDate(_checkOut),
                        onTap: () => _pickDate(checkIn: false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                InkWell(
                  onTap: _pickGuests,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: scheme.outlineVariant),
                      color: scheme.surfaceContainerLowest,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.people_outline, color: scheme.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                context.tr('guests'),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                              Text(
                                _guestPartyLine(context),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: scheme.outline),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      colors: [
                        scheme.primary,
                        scheme.primary.withValues(alpha: 0.82),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: 0.28),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: SizedBox(
                    height: 54,
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _searching ? null : _search,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: _searching
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  context.tr('search_hotels_btn'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.search, size: 22),
                                const SizedBox(width: 10),
                                Text(
                                  context.tr('search_hotels_btn'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.1,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Material(
            color: scheme.errorContainer.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.cloud_off_outlined,
                      color: scheme.error, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _error!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
          TextButton(
            onPressed: _loadHotels,
            child: Text(context.tr('retry')),
          ),
        ],
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.apartment, size: 20, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _allHotels.isEmpty && (_loading || _refreshingDirectory)
                      ? 'Loading properties…'
                      : context.tr('properties_nationwide', {
                          'n': '${_allHotels.length}',
                        }),
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (_refreshingDirectory && _allHotels.isNotEmpty)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.primary,
                  ),
                )
              else
                Icon(Icons.verified_outlined,
                    size: 18, color: scheme.tertiary),
            ],
          ),
        ),
        if (showMemberLogin) ...[
          const SizedBox(height: 28),
          const Divider(),
          const SizedBox(height: 16),
          Text(
            'Already a MADYAWPH member?',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Log in to open your member dashboard, browse hotels, and show your membership QR for discounts.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _openMemberLogin,
            icon: const Icon(Icons.login),
            label: const Text('Log in as member'),
          ),
        ],
      ],
    );
  }
}

class _GuestCounterRow extends StatelessWidget {
  const _GuestCounterRow({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.min = 0,
  });

  final String label;
  final String subtitle;
  final int value;
  final int min;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        IconButton.filledTonal(
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            '$value',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ),
        IconButton.filledTonal(
          onPressed: () => onChanged(value + 1),
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.calendar_today_outlined,
                      size: 16, color: scheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      value,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      softWrap: true,
                      maxLines: 2,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
