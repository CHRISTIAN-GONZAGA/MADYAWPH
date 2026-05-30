import 'package:flutter/foundation.dart';

/// After choosing a hotel or registering — drives navigation to the role menu.
class HotelSession {
  const HotelSession({required this.hotelId, required this.hotelName});

  final String hotelId;
  final String hotelName;
}

final ValueNotifier<HotelSession?> hotelSessionNotifier = ValueNotifier(null);
