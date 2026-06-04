import 'package:flutter/material.dart';

import '../auth_storage.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/app_state_views.dart';
import 'flow_state.dart';
import 'hotel_screens.dart';

/// Restores saved hotel context, then: choose hotel → role menu → dashboards.
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
    final results = await Future.wait<String?>([
      AuthStorage.hotelId(),
      AuthStorage.hotelName(),
    ]);
    final id = results[0];
    final name = results[1];
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
      return const AppScaffold(
        body: AppLoadingView(),
      );
    }
    return ValueListenableBuilder<HotelSession?>(
      valueListenable: hotelSessionNotifier,
      builder: (context, session, _) {
        if (session == null) {
          return const ChooseHotelScreen();
        }
        return RoleMenuScreen(session: session);
      },
    );
  }
}
