import 'package:flutter/material.dart';

import '../auth_storage.dart';
import 'flow_state.dart';
import 'hotel_screens.dart';

/// Restores saved hotel context, then: hotel gate → role menu → dashboards.
class FlowRoot extends StatefulWidget {
  const FlowRoot({super.key});

  @override
  State<FlowRoot> createState() => _FlowRootState();
}

class _FlowRootState extends State<FlowRoot> {
  bool _hydrating = true;

  @override
  void initState() {
    super.initState();
    _hydrateHotelSession();
  }

  Future<void> _hydrateHotelSession() async {
    final id = await AuthStorage.hotelId();
    final name = await AuthStorage.hotelName();
    if (mounted && id != null && id.isNotEmpty) {
      hotelSessionNotifier.value = HotelSession(hotelId: id, hotelName: name ?? 'Hotel');
    }
    if (mounted) {
      setState(() => _hydrating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hydrating) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return ValueListenableBuilder<HotelSession?>(
      valueListenable: hotelSessionNotifier,
      builder: (context, session, _) {
        if (session == null) {
          return const HotelGateScreen();
        }
        return RoleMenuScreen(session: session);
      },
    );
  }
}
