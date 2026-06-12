/// Popular Philippine destinations for the public hotel search landing screen.
class PhDestinationPreset {
  const PhDestinationPreset({
    required this.label,
    required this.searchQuery,
    required this.region,
    this.icon = '🏙️',
  });

  final String label;
  /// Passed to `/hotels/search?q=` and local directory filter.
  final String searchQuery;
  final String region;
  final String icon;
}

class PhilippineDestinationPresets {
  PhilippineDestinationPresets._();

  static const popular = <PhDestinationPreset>[
    PhDestinationPreset(
      label: 'Manila',
      searchQuery: 'Manila',
      region: 'NCR',
      icon: '🏙️',
    ),
    PhDestinationPreset(
      label: 'Cebu',
      searchQuery: 'Cebu',
      region: 'Central Visayas',
      icon: '🌴',
    ),
    PhDestinationPreset(
      label: 'Davao',
      searchQuery: 'Davao',
      region: 'Davao Region',
      icon: '🌺',
    ),
    PhDestinationPreset(
      label: 'Baguio',
      searchQuery: 'Baguio',
      region: 'Cordillera',
      icon: '🌲',
    ),
    PhDestinationPreset(
      label: 'Bohol',
      searchQuery: 'Bohol',
      region: 'Central Visayas',
      icon: '🐚',
    ),
    PhDestinationPreset(
      label: 'Palawan',
      searchQuery: 'Palawan',
      region: 'MIMAROPA',
      icon: '🏝️',
    ),
    PhDestinationPreset(
      label: 'Iloilo',
      searchQuery: 'Iloilo',
      region: 'Western Visayas',
      icon: '⛵',
    ),
    PhDestinationPreset(
      label: 'Butuan',
      searchQuery: 'Butuan',
      region: 'Caraga',
      icon: '🌊',
    ),
    PhDestinationPreset(
      label: 'Tagaytay',
      searchQuery: 'Tagaytay',
      region: 'Calabarzon',
      icon: '🌋',
    ),
    PhDestinationPreset(
      label: 'Bacolod',
      searchQuery: 'Bacolod',
      region: 'Western Visayas',
      icon: '🎭',
    ),
    PhDestinationPreset(
      label: 'Cagayan de Oro',
      searchQuery: 'Cagayan de Oro',
      region: 'Northern Mindanao',
      icon: '🌉',
    ),
    PhDestinationPreset(
      label: 'Boracay',
      searchQuery: 'Aklan',
      region: 'Western Visayas',
      icon: '🏖️',
    ),
  ];

  static Map<String, List<PhDestinationPreset>> get byRegion {
    final map = <String, List<PhDestinationPreset>>{};
    for (final d in popular) {
      map.putIfAbsent(d.region, () => []).add(d);
    }
    final keys = map.keys.toList()..sort();
    return {for (final k in keys) k: map[k]!};
  }
}
