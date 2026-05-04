import 'package:flutter/foundation.dart';

/// After hotel gate or register — drives navigation to the role menu.
class HotelSession {
  const HotelSession({required this.hotelId, required this.hotelName});

  final String hotelId;
  final String hotelName;
}

final ValueNotifier<HotelSession?> hotelSessionNotifier = ValueNotifier(null);
