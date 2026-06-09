import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

/// Device GPS distance sorting for the hotel picker (no external geocoding APIs).
class NearbyHotelsService {
  NearbyHotelsService._();

  static const defaultRadiusKm = 75.0;

  static Future<({double lat, double lng})> currentPosition() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw const NearbyHotelsException('location_services_disabled');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const NearbyHotelsException('permission_denied');
    }
    if (permission == LocationPermission.deniedForever) {
      throw const NearbyHotelsException('permission_denied_forever');
    }

    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 25),
      ),
    );

    return (lat: pos.latitude, lng: pos.longitude);
  }

  static double? hotelLatitude(Map<String, dynamic> hotel) {
    final v = hotel['latitude'];
    if (v is num && v != 0) return v.toDouble();
    return null;
  }

  static double? hotelLongitude(Map<String, dynamic> hotel) {
    final v = hotel['longitude'];
    if (v is num && v != 0) return v.toDouble();
    return null;
  }

  static bool hasCoordinates(Map<String, dynamic> hotel) =>
      hotelLatitude(hotel) != null && hotelLongitude(hotel) != null;

  static int countHotelsWithCoordinates(Iterable<Map<String, dynamic>> hotels) =>
      hotels.where(hasCoordinates).length;

  static double distanceKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadiusKm = 6371.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLng = _degToRad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  static double _degToRad(double deg) => deg * math.pi / 180.0;
}

class NearbyHotelsException implements Exception {
  const NearbyHotelsException(this.code);

  final String code;

  @override
  String toString() => code;
}

/// Build a display address for hotel cards.
String hotelDisplayAddress(Map<String, dynamic> hotel) {
  final formatted = (hotel['formatted_address'] ?? '').toString().trim();
  if (formatted.isNotEmpty) return formatted;

  final parts = <String>[];
  final street = (hotel['street_address'] ?? '').toString().trim();
  final barangay = (hotel['barangay'] ?? '').toString().trim();
  final city = (hotel['city'] ?? '').toString().trim();
  final province = (hotel['province'] ?? '').toString().trim();
  final region = (hotel['region'] ?? '').toString().trim();
  final loc = (hotel['location'] ?? '').toString().trim();

  if (street.isNotEmpty) parts.add(street);
  if (barangay.isNotEmpty) parts.add('Brgy $barangay');
  if (city.isNotEmpty) parts.add(city);
  if (province.isNotEmpty && province != city) parts.add(province);
  if (region.isNotEmpty && !parts.contains(region)) parts.add(region);

  if (parts.isNotEmpty) return parts.join(', ');
  return loc.isNotEmpty ? loc : 'Address not listed';
}

String formatDistanceKm(double km) {
  if (km < 1) return '${(km * 1000).round()} m';
  if (km < 10) return '${km.toStringAsFixed(1)} km';
  return '${km.round()} km';
}
