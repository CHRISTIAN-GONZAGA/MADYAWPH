import 'dart:convert';

import 'package:flutter/services.dart';

/// Philippine region → province → city/municipality → barangay hierarchy.
class PhilippineLocations {
  PhilippineLocations._loaded(this.regions);

  static PhilippineLocations? _instance;

  static Future<PhilippineLocations> load() async {
    if (_instance != null) return _instance!;
    final raw = await rootBundle.loadString('assets/data/philippine_locations.json');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    _instance = PhilippineLocations._fromJson(decoded);
    return _instance!;
  }

  factory PhilippineLocations._fromJson(Map<String, dynamic> json) {
    final regions = <PhRegion>[];
    for (final r in (json['regions'] as List? ?? const [])) {
      if (r is! Map) continue;
      regions.add(PhRegion.fromJson(Map<String, dynamic>.from(r)));
    }
    return PhilippineLocations._loaded(regions);
  }

  final List<PhRegion> regions;

  List<String> get regionNames =>
      regions.map((r) => r.name).where((n) => n.isNotEmpty).toList();

  PhRegion? regionNamed(String name) {
    final key = name.trim().toLowerCase();
    for (final r in regions) {
      if (r.name.toLowerCase() == key) return r;
    }
    return null;
  }
}

class PhRegion {
  PhRegion({required this.name, required this.provinces});

  factory PhRegion.fromJson(Map<String, dynamic> json) {
    final provinces = <PhProvince>[];
    for (final p in (json['provinces'] as List? ?? const [])) {
      if (p is! Map) continue;
      provinces.add(PhProvince.fromJson(Map<String, dynamic>.from(p)));
    }
    return PhRegion(
      name: (json['name'] ?? '').toString(),
      provinces: provinces,
    );
  }

  final String name;
  final List<PhProvince> provinces;
}

class PhProvince {
  PhProvince({required this.name, required this.cities});

  factory PhProvince.fromJson(Map<String, dynamic> json) {
    final cities = <PhCity>[];
    for (final c in (json['cities'] as List? ?? const [])) {
      if (c is! Map) continue;
      cities.add(PhCity.fromJson(Map<String, dynamic>.from(c)));
    }
    return PhProvince(
      name: (json['name'] ?? '').toString(),
      cities: cities,
    );
  }

  final String name;
  final List<PhCity> cities;
}

class PhCity {
  PhCity({required this.name, required this.barangays});

  factory PhCity.fromJson(Map<String, dynamic> json) {
    return PhCity(
      name: (json['name'] ?? '').toString(),
      barangays: (json['barangays'] as List? ?? const [])
          .map((b) => b.toString())
          .where((b) => b.isNotEmpty)
          .toList(),
    );
  }

  final String name;
  final List<String> barangays;
}

/// User selection for hotel registration.
class PhilippineAddressSelection {
  const PhilippineAddressSelection({
    this.region = '',
    this.province = '',
    this.city = '',
    this.barangay = '',
    this.streetAddress = '',
  });

  final String region;
  final String province;
  final String city;
  final String barangay;
  final String streetAddress;

  bool get isComplete =>
      region.isNotEmpty &&
      province.isNotEmpty &&
      city.isNotEmpty &&
      barangay.isNotEmpty;

  String get formattedLocation {
    final parts = <String>[];
    if (streetAddress.trim().isNotEmpty) parts.add(streetAddress.trim());
    if (barangay.isNotEmpty) parts.add('Brgy $barangay');
    if (city.isNotEmpty) parts.add(city);
    if (province.isNotEmpty && province != city) parts.add(province);
    if (region.isNotEmpty && !parts.contains(region)) parts.add(region);
    return parts.join(', ');
  }

  Map<String, dynamic> toRegisterPayload() => {
        'region': region,
        'province': province,
        'city': city,
        'barangay': barangay,
        if (streetAddress.trim().isNotEmpty) 'street_address': streetAddress.trim(),
        'location': formattedLocation,
      };

  PhilippineAddressSelection copyWith({
    String? region,
    String? province,
    String? city,
    String? barangay,
    String? streetAddress,
  }) {
    return PhilippineAddressSelection(
      region: region ?? this.region,
      province: province ?? this.province,
      city: city ?? this.city,
      barangay: barangay ?? this.barangay,
      streetAddress: streetAddress ?? this.streetAddress,
    );
  }
}
