import 'package:flutter/material.dart';

import 'public_hotel_search_screen.dart';

/// App home after intro: public hotel search (Agoda-style). Staff use the badge icon.
class FlowRoot extends StatelessWidget {
  const FlowRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return const PublicHotelSearchScreen();
  }
}
