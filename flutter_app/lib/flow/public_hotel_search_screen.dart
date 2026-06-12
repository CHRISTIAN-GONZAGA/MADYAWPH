import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../auth_storage.dart';
import '../branding/madyaw_logo_widget.dart';
import '../dio_client.dart';
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
  DateTime _checkIn = DateTime.now();
  DateTime _checkOut = DateTime.now().add(const Duration(days: 1));
  int _rooms = 1;
  int _adults = 2;
  int _children = 0;

  @override
  void initState() {
    super.initState();
    _loadHotels();
  }

  @override
  void dispose() {
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

  String _fmtDate(DateTime d) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${days[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}';
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
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Rooms & guests'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _counterRow('Rooms', rooms, (v) => setLocal(() => rooms = v), min: 1),
              _counterRow('Adults', adults, (v) => setLocal(() => adults = v), min: 1),
              _counterRow(
                'Children',
                children,
                (v) => setLocal(() => children = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                setState(() {
                  _rooms = rooms;
                  _adults = adults;
                  _children = children;
                });
                Navigator.pop(ctx);
              },
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _counterRow(
    String label,
    int value,
    ValueChanged<int> onChanged, {
    int min = 0,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          IconButton(
            onPressed: value > min ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Text('$value', style: const TextStyle(fontWeight: FontWeight.w700)),
          IconButton(
            onPressed: () => onChanged(value + 1),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
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
        MaterialPageRoute<void>(
          builder: (_) => HotelSearchResultsScreen(
            hotels: hotels,
            search: search,
          ),
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

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF1565C0),
                  Color(0xFF0D47A1),
                  Color(0xFF083A7A),
                ],
              ),
            ),
            child: SizedBox.expand(),
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
                        child: Center(child: MadyawLogoWidget(size: 72)),
                      ),
                      const LanguagePickerButton(),
                      IconButton(
                        tooltip: 'Hotel staff sign in',
                        onPressed: _openStaffPropertyLogin,
                        icon: const Icon(Icons.badge_outlined, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Hotels',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: Column(
                      children: [
                        Material(
                          elevation: 8,
                          shadowColor: Colors.black38,
                          borderRadius: BorderRadius.circular(16),
                          color: Colors.white,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                TextField(
                                  controller: _destinationCtrl,
                                  decoration: InputDecoration(
                                    hintText: 'Where would you like to go?',
                                    prefixIcon: const Icon(Icons.search),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    filled: true,
                                    fillColor: scheme.surfaceContainerLowest,
                                  ),
                                  textInputAction: TextInputAction.search,
                                  onSubmitted: (_) => _search(),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _DateTile(
                                        label: 'Check-in',
                                        value: _fmtDate(_checkIn),
                                        onTap: () => _pickDate(checkIn: true),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _DateTile(
                                        label: 'Check-out',
                                        value: _fmtDate(_checkOut),
                                        onTap: () => _pickDate(checkIn: false),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                InkWell(
                                  onTap: _pickGuests,
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 14,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: scheme.outlineVariant,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.person_outline,
                                            color: scheme.primary),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            '$_rooms Room${_rooms == 1 ? '' : 's'}, '
                                            '$_adults Adult${_adults == 1 ? '' : 's'}, '
                                            '$_children Child${_children == 1 ? '' : 'ren'}',
                                          ),
                                        ),
                                        Icon(Icons.chevron_right,
                                            color: scheme.outline),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  height: 52,
                                  child: FilledButton(
                                    onPressed:
                                        (_loading || _searching) ? null : _search,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFF1565C0),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: (_loading || _searching)
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Text(
                                            'SEARCH',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 1.2,
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
                        Text(
                          '${_allHotels.length} properties in the Philippines',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.white70,
                              ),
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
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
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

