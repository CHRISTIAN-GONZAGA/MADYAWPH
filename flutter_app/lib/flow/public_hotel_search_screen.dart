import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth_storage.dart';
import '../branding/madyaw_logo_widget.dart';
import '../data/philippine_destination_presets.dart';
import '../dio_client.dart';
import '../locale_controller.dart';
import '../widgets/language_picker_button.dart';
import 'customer_search_context.dart';
import 'hotel_search_results_screen.dart';
import 'hotel_screens.dart';

/// Agoda-style public landing: search hotels, then browse/book as a guest.
class PublicHotelSearchScreen extends StatefulWidget {
  const PublicHotelSearchScreen({super.key});

  @override
  State<PublicHotelSearchScreen> createState() => _PublicHotelSearchScreenState();
}

class _PublicHotelSearchScreenState extends State<PublicHotelSearchScreen> {
  final _destinationCtrl = TextEditingController();
  List<Map<String, dynamic>> _allHotels = const [];
  bool _loading = true;
  bool _searching = false;
  String? _error;
  String? _selectedPresetQuery;
  DateTime _checkIn = DateTime.now();
  DateTime _checkOut = DateTime.now().add(const Duration(days: 1));
  int _rooms = 1;
  int _adults = 2;
  int _children = 0;

  static const _heroBlue = Color(0xFF1565C0);
  static const _heroDeep = Color(0xFF083A7A);

  @override
  void initState() {
    super.initState();
    _destinationCtrl.addListener(_onDestinationEdited);
    _loadHotels();
  }

  void _onDestinationEdited() {
    final text = _destinationCtrl.text.trim();
    if (_selectedPresetQuery != null && text != _selectedPresetQuery) {
      setState(() => _selectedPresetQuery = null);
    }
  }

  @override
  void dispose() {
    _destinationCtrl.removeListener(_onDestinationEdited);
    _destinationCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHotels() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cached = await AuthStorage.hotelsDirectoryCache();
      if (cached != null && cached.isNotEmpty) {
        _parseDirectory(jsonDecode(cached));
      }
      final res = await publicDio().get<Map<String, dynamic>>('/hotels');
      final data = res.data;
      if (data != null) {
        await AuthStorage.setHotelsDirectoryCache(jsonEncode(data));
        _parseDirectory(data);
      }
    } on DioException catch (e) {
      if (_allHotels.isEmpty) {
        setState(() => _error = dioErrorMessage(e));
      }
    } catch (e) {
      if (_allHotels.isEmpty) {
        setState(() => _error = '$e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
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
    final res = await publicDio().get<Map<String, dynamic>>('/hotels');
    final data = res.data;
    if (data != null) {
      await AuthStorage.setHotelsDirectoryCache(jsonEncode(data));
      _parseDirectory(data, notify: false);
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
                  'Philippine destinations',
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tap a city to set your search',
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
                                color: _heroBlue,
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
                  'Rooms & guests',
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 16),
                _GuestCounterRow(
                  label: 'Rooms',
                  subtitle: 'How many rooms do you need?',
                  value: rooms,
                  min: 1,
                  onChanged: (v) => setLocal(() => rooms = v),
                ),
                const Divider(height: 24),
                _GuestCounterRow(
                  label: 'Adults',
                  subtitle: 'Ages 18+',
                  value: adults,
                  min: 1,
                  onChanged: (v) => setLocal(() => adults = v),
                ),
                const Divider(height: 24),
                _GuestCounterRow(
                  label: 'Children',
                  subtitle: 'Ages 0–17',
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
                    backgroundColor: _heroBlue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Apply'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  List<Map<String, dynamic>> _fallbackDirectorySearch({bool usedLegacyApi = false}) {
    final q = _destinationCtrl.text.trim().toLowerCase();
    var list = _allHotels;
    if (q.isNotEmpty) {
      list = list.where((h) {
        final name = (h['name'] ?? '').toString().toLowerCase();
        final city = (h['city'] ?? h['location'] ?? '').toString().toLowerCase();
        final region = (h['region'] ?? '').toString().toLowerCase();
        return name.contains(q) || city.contains(q) || region.contains(q);
      }).toList();
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

  Future<({List<Map<String, dynamic>> hotels, bool usedLegacy})>
      _fetchSearchResults() async {
    try {
      final res = await publicDio().get<Map<String, dynamic>>(
        '/hotels/search',
        queryParameters: {
          if (_destinationCtrl.text.trim().isNotEmpty)
            'q': _destinationCtrl.text.trim(),
          'check_in': _isoDate(_checkIn),
          'check_out': _isoDate(_checkOut),
          'rooms': _rooms,
          'adults': _adults,
          'children': _children,
        },
      );
      final raw = res.data?['hotels'] as List<dynamic>? ?? const [];
      final hotels =
          raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      return (hotels: hotels, usedLegacy: false);
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
      );
    }
  }

  Future<void> _search() async {
    HapticFeedback.mediumImpact();
    setState(() => _searching = true);
    try {
      final result = await _fetchSearchResults();
      final hotels = result.hotels;
      final usedLegacy = result.usedLegacy;
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Showing hotels by location. Date availability is checked when you pick a room.',
            ),
            duration: Duration(seconds: 4),
          ),
        );
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
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dioErrorMessage(e))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final destination = _destinationCtrl.text.trim();

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF1976D2),
                  _heroBlue,
                  Color(0xFF0D47A1),
                  _heroDeep,
                ],
                stops: [0.0, 0.35, 0.7, 1.0],
              ),
            ),
            child: SizedBox.expand(),
          ),
          Positioned(
            top: -80,
            right: -40,
            child: Icon(
              Icons.travel_explore,
              size: 220,
              color: Colors.white.withValues(alpha: 0.06),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Center(child: MadyawLogoWidget(size: 68)),
                      ),
                      const LanguagePickerButton(),
                      IconButton(
                        tooltip: context.tr('property_sign_in'),
                        onPressed: _openStaffPropertyLogin,
                        icon: const Icon(Icons.badge_outlined, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Column(
                    children: [
                      Text(
                        'Where would you like to go?',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Search stays across the Philippines',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Material(
                          elevation: 12,
                          shadowColor: Colors.black38,
                          borderRadius: BorderRadius.circular(20),
                          color: Colors.white,
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextField(
                                  controller: _destinationCtrl,
                                  decoration: InputDecoration(
                                    hintText: 'City, region, or hotel name',
                                    prefixIcon: const Icon(Icons.location_on_outlined),
                                    suffixIcon: destination.isNotEmpty
                                        ? IconButton(
                                            onPressed: () {
                                              setState(() {
                                                _destinationCtrl.clear();
                                                _selectedPresetQuery = null;
                                              });
                                            },
                                            icon: const Icon(Icons.close, size: 20),
                                          )
                                        : IconButton(
                                            onPressed: _openDestinationPicker,
                                            icon: const Icon(Icons.map_outlined),
                                            tooltip: 'Browse cities',
                                          ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    filled: true,
                                    fillColor: scheme.surfaceContainerLowest,
                                  ),
                                  textInputAction: TextInputAction.search,
                                  onSubmitted: (_) => _search(),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  'Popular destinations',
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
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(width: 8),
                                    itemBuilder: (context, i) {
                                      if (i == PhilippineDestinationPresets.popular.length) {
                                        return ActionChip(
                                          avatar: const Icon(Icons.grid_view, size: 18),
                                          label: const Text('All cities'),
                                          onPressed: _openDestinationPicker,
                                        );
                                      }
                                      final preset =
                                          PhilippineDestinationPresets.popular[i];
                                      final selected = _selectedPresetQuery ==
                                          preset.searchQuery;
                                      return FilterChip(
                                        label: Text(
                                          '${preset.icon} ${preset.label}',
                                          style: TextStyle(
                                            fontWeight: selected
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                          ),
                                        ),
                                        selected: selected,
                                        selectedColor:
                                            _heroBlue.withValues(alpha: 0.15),
                                        checkmarkColor: _heroBlue,
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
                                        label: 'Check-in',
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
                                              color: _heroBlue.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              '$_nightCount night${_nightCount == 1 ? '' : 's'}',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: _heroBlue,
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
                                        label: 'Check-out',
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
                                      border: Border.all(
                                        color: scheme.outlineVariant,
                                      ),
                                      color: scheme.surfaceContainerLowest,
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.people_outline,
                                            color: scheme.primary),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Guests',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(
                                                      color: scheme.onSurfaceVariant,
                                                    ),
                                              ),
                                              Text(
                                                '$_rooms room${_rooms == 1 ? '' : 's'} · '
                                                '$_adults adult${_adults == 1 ? '' : 's'} · '
                                                '$_children child${_children == 1 ? '' : 'ren'}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Icon(Icons.chevron_right,
                                            color: scheme.outline),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 18),
                                SizedBox(
                                  height: 54,
                                  child: FilledButton(
                                    onPressed:
                                        (_loading || _searching) ? null : _search,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: _heroBlue,
                                      disabledBackgroundColor:
                                          _heroBlue.withValues(alpha: 0.5),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      elevation: 2,
                                    ),
                                    child: (_loading || _searching)
                                        ? const SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.5,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.search, size: 22),
                                              SizedBox(width: 10),
                                              Text(
                                                'SEARCH HOTELS',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  letterSpacing: 1.1,
                                                  fontSize: 15,
                                                ),
                                              ),
                                            ],
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70),
                          ),
                          TextButton(
                            onPressed: _loadHotels,
                            child: const Text(
                              'Retry',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.apartment,
                                size: 16, color: Colors.white.withValues(alpha: 0.7)),
                            const SizedBox(width: 6),
                            Text(
                              '${_allHotels.length} properties nationwide',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.75),
                                  ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.outlineVariant),
          color: scheme.surfaceContainerLowest,
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
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
