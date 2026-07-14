import 'package:flutter/material.dart';

import '../data/philippine_locations.dart';

/// Cascading pickers for Philippine region, province, city, and barangay.
class PhilippineAddressPicker extends StatefulWidget {
  const PhilippineAddressPicker({
    super.key,
    required this.onChanged,
    this.initial,
  });

  final ValueChanged<PhilippineAddressSelection> onChanged;
  final PhilippineAddressSelection? initial;

  @override
  State<PhilippineAddressPicker> createState() =>
      _PhilippineAddressPickerState();
}

class _PhilippineAddressPickerState extends State<PhilippineAddressPicker> {
  PhilippineLocations? _data;
  String? _error;
  String _region = '';
  String _province = '';
  String _city = '';
  String _barangay = '';
  final _street = TextEditingController();
  int _cityFieldKey = 0;
  int _barangayFieldKey = 0;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    if (init != null) {
      _region = init.region;
      _province = init.province;
      _city = init.city;
      _barangay = init.barangay;
      _street.text = init.streetAddress;
    }
    _load();
  }

  @override
  void dispose() {
    _street.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await PhilippineLocations.load();
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
      });
      _emit();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  void _emit() {
    widget.onChanged(
      PhilippineAddressSelection(
        region: _region,
        province: _province,
        city: _city,
        barangay: _barangay,
        streetAddress: _street.text,
      ),
    );
  }

  PhRegion? get _selectedRegion => _data?.regionNamed(_region);

  PhProvince? get _selectedProvince {
    final region = _selectedRegion;
    if (region == null) return null;
    final key = _province.trim().toLowerCase();
    for (final p in region.provinces) {
      if (p.name.toLowerCase() == key) return p;
    }
    return null;
  }

  PhCity? get _selectedCity {
    final province = _selectedProvince;
    if (province == null) return null;
    final key = _city.trim().toLowerCase();
    for (final c in province.cities) {
      if (c.name.toLowerCase() == key) return c;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Text(
        _error!,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    }
    if (_data == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final provinces = _selectedRegion?.provinces ?? const <PhProvince>[];
    final cities = _selectedProvince?.cities ?? const <PhCity>[];
    final cityNames = cities.map((c) => c.name).toList();
    final barangays = _selectedCity?.barangays ?? const <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Property location',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'Official PSGC list — all Philippine cities/municipalities and barangays. '
          'Type to search city or barangay.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 12),
        _LocationDropdown(
          label: 'Region *',
          value: _region.isEmpty ? null : _region,
          items: _data!.regionNames,
          onChanged: (v) {
            setState(() {
              _region = v ?? '';
              _province = '';
              _city = '';
              _barangay = '';
              _cityFieldKey++;
              _barangayFieldKey++;
            });
            _emit();
          },
        ),
        const SizedBox(height: 10),
        _LocationDropdown(
          label: 'Province *',
          value: _province.isEmpty ? null : _province,
          items: provinces.map((p) => p.name).toList(),
          enabled: _region.isNotEmpty,
          onChanged: (v) {
            setState(() {
              _province = v ?? '';
              _city = '';
              _barangay = '';
              _cityFieldKey++;
              _barangayFieldKey++;
            });
            _emit();
          },
        ),
        const SizedBox(height: 10),
        _SearchableLocationField(
          key: ValueKey('city-$_cityFieldKey-$_city'),
          label: 'City / municipality *',
          initialValue: _city,
          enabled: _province.isNotEmpty,
          options: cityNames,
          onSelected: (v) {
            setState(() {
              _city = v;
              _barangay = '';
              _barangayFieldKey++;
            });
            _emit();
          },
          onCleared: () {
            setState(() {
              _city = '';
              _barangay = '';
              _barangayFieldKey++;
            });
            _emit();
          },
        ),
        const SizedBox(height: 10),
        _SearchableLocationField(
          key: ValueKey('brgy-$_barangayFieldKey-$_barangay'),
          label: 'Barangay *',
          initialValue: _barangay,
          enabled: _city.isNotEmpty,
          options: barangays,
          onSelected: (v) {
            setState(() => _barangay = v);
            _emit();
          },
          onCleared: () {
            setState(() => _barangay = '');
            _emit();
          },
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _street,
          decoration: const InputDecoration(
            labelText: 'Street / building (optional)',
            border: OutlineInputBorder(),
            hintText: 'e.g. National Highway, near city hall',
          ),
          textInputAction: TextInputAction.next,
          onChanged: (_) => _emit(),
        ),
        if (_region.isNotEmpty && _barangay.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              PhilippineAddressSelection(
                region: _region,
                province: _province,
                city: _city,
                barangay: _barangay,
                streetAddress: _street.text,
              ).formattedLocation,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ],
    );
  }
}

class _LocationDropdown extends StatelessWidget {
  const _LocationDropdown({
    required this.label,
    required this.items,
    required this.onChanged,
    this.value,
    this.enabled = true,
  });

  final String label;
  final List<String> items;
  final String? value;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: value != null && items.contains(value) ? value : null,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      isExpanded: true,
      items: items
          .map(
            (name) => DropdownMenuItem(
              value: name,
              child: Text(name, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: enabled ? onChanged : null,
    );
  }
}

class _SearchableLocationField extends StatefulWidget {
  const _SearchableLocationField({
    super.key,
    required this.label,
    required this.options,
    required this.onSelected,
    required this.onCleared,
    this.initialValue = '',
    this.enabled = true,
  });

  final String label;
  final String initialValue;
  final List<String> options;
  final ValueChanged<String> onSelected;
  final VoidCallback onCleared;
  final bool enabled;

  @override
  State<_SearchableLocationField> createState() =>
      _SearchableLocationFieldState();
}

class _SearchableLocationFieldState extends State<_SearchableLocationField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<String> _matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return widget.options.take(80).toList();
    final starts = <String>[];
    final contains = <String>[];
    for (final item in widget.options) {
      final lower = item.toLowerCase();
      if (lower.startsWith(q)) {
        starts.add(item);
      } else if (lower.contains(q)) {
        contains.add(item);
      }
      if (starts.length + contains.length >= 80) break;
    }
    return [...starts, ...contains].take(80).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      optionsBuilder: (textEditingValue) {
        if (!widget.enabled) return const Iterable<String>.empty();
        return _matches(textEditingValue.text);
      },
      onSelected: (v) {
        _controller.text = v;
        widget.onSelected(v);
      },
      fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
        // Prefer Autocomplete's controller; seed once from ours.
        if (textController.text.isEmpty && _controller.text.isNotEmpty) {
          textController.text = _controller.text;
        }
        return TextField(
          controller: textController,
          focusNode: focusNode,
          enabled: widget.enabled,
          decoration: InputDecoration(
            labelText: widget.label,
            border: const OutlineInputBorder(),
            hintText: widget.enabled ? 'Type to search…' : null,
            suffixIcon: IconButton(
              tooltip: 'Clear',
              onPressed: !widget.enabled
                  ? null
                  : () {
                      textController.clear();
                      _controller.clear();
                      widget.onCleared();
                    },
              icon: const Icon(Icons.clear),
            ),
          ),
          onChanged: (v) {
            _controller.text = v;
            if (widget.options.contains(v)) {
              widget.onSelected(v);
            } else {
              widget.onCleared();
            }
          },
          onSubmitted: (_) => onFieldSubmitted(),
        );
      },
      optionsViewBuilder: (context, onSelectedOption, optionsIterable) {
        final opts = optionsIterable.toList();
        if (opts.isEmpty) {
          return const SizedBox.shrink();
        }
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, maxWidth: 520),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: opts.length,
                itemBuilder: (context, index) {
                  final option = opts[index];
                  return ListTile(
                    dense: true,
                    title: Text(option),
                    onTap: () => onSelectedOption(option),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
