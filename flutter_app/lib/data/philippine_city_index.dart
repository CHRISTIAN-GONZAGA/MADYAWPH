import 'philippine_locations.dart';

/// Searchable Philippine cities for the public destination field.
class PhilippineCityEntry {
  const PhilippineCityEntry({
    required this.city,
    required this.province,
    required this.region,
  });

  final String city;
  final String province;
  final String region;

  String get label => '$city · $province';
  String get searchQuery => city;
}

class PhilippineCityIndex {
  PhilippineCityIndex._(this.cities);

  static PhilippineCityIndex? _cache;

  final List<PhilippineCityEntry> cities;

  static Future<PhilippineCityIndex> load() async {
    if (_cache != null) return _cache!;
    final data = await PhilippineLocations.load();
    final out = <PhilippineCityEntry>[];
    for (final region in data.regions) {
      for (final province in region.provinces) {
        for (final city in province.cities) {
          if (city.name.trim().isEmpty) continue;
          out.add(PhilippineCityEntry(
            city: city.name,
            province: province.name,
            region: region.name,
          ));
        }
      }
    }
    out.sort((a, b) => a.city.compareTo(b.city));
    _cache = PhilippineCityIndex._(out);
    return _cache!;
  }

  List<PhilippineCityEntry> search(String query, {int limit = 80}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return cities.take(limit).toList();
    }
    final tokens = q.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    final scored = <({PhilippineCityEntry entry, int score})>[];
    for (final entry in cities) {
      final hay = '${entry.city} ${entry.province} ${entry.region}'.toLowerCase();
      var ok = true;
      var score = 0;
      for (final token in tokens) {
        if (!hay.contains(token)) {
          ok = false;
          break;
        }
        if (entry.city.toLowerCase().startsWith(token)) {
          score += 3;
        } else if (entry.city.toLowerCase().contains(token)) {
          score += 2;
        } else {
          score += 1;
        }
      }
      if (ok) scored.add((entry: entry, score: score));
    }
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.entry.city.compareTo(b.entry.city);
    });
    return scored.take(limit).map((e) => e.entry).toList();
  }
}
