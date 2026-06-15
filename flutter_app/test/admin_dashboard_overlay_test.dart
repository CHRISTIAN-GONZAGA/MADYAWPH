import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gloretto_mobile/flow/admin/widgets/admin_room_navigation.dart';
import 'package:gloretto_mobile/flow/admin/widgets/admin_room_overlay.dart';

void main() {
  testWidgets('overlay host shows walk-in booking UI', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _OverlayHarness()));

    await tester.tap(find.text('Open walk-in'));
    await tester.pump();

    expect(find.text('Guest details'), findsOneWidget);
    expect(find.textContaining('Walk-in'), findsOneWidget);
  });
}

class _OverlayHarness extends StatefulWidget {
  const _OverlayHarness();

  @override
  State<_OverlayHarness> createState() => _OverlayHarnessState();
}

class _OverlayHarnessState extends State<_OverlayHarness> {
  AdminWalkInOverlayRequest? _walkIn;
  String? _detailId;

  @override
  void initState() {
    super.initState();
    AdminRoomOverlayHost.instance.bind(
      showWalkIn: (request) => setState(() {
        _walkIn = request;
        _detailId = null;
      }),
      showDetail: (id) => setState(() {
        _detailId = id;
        _walkIn = null;
      }),
      hide: () => setState(() {
        _walkIn = null;
        _detailId = null;
      }),
    );
  }

  @override
  void dispose() {
    AdminRoomOverlayHost.instance.unbind();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Center(
          child: FilledButton(
            onPressed: () {
              AdminRoomNavigation.openWalkInBooking(
                context,
                room: const {
                  'id': 'room-1',
                  'room_number': '101',
                  'status': 'available',
                  'price_per_night': 1500,
                },
                onSuccess: () async {},
              );
            },
            child: const Text('Open walk-in'),
          ),
        ),
        if (_walkIn != null || _detailId != null)
          Positioned.fill(
            child: AdminRoomOverlayLayer(
              walkIn: _walkIn,
              detailRoomId: _detailId,
              onClose: () => setState(() {
                _walkIn = null;
                _detailId = null;
              }),
            ),
          ),
      ],
    );
  }
}
