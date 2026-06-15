import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gloretto_mobile/flow/admin/sections/room_board_section.dart';
import 'package:gloretto_mobile/flow/admin/widgets/admin_dashboard_routes.dart';
import 'package:gloretto_mobile/flow/widgets/complete_guest_booking_dialog.dart';

void main() {
  testWidgets('walk-in tab uses complete booking dialog via dashboard host',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: _DashboardHostHarness(
          child: RoomBoardSection(
            rooms: const [
              {
                'id': 'room-1',
                'room_number': '101',
                'status': 'available',
                'price_per_night': 1500,
                'category_name': 'Standard',
                'billing_mode': 'nightly',
              },
            ],
            hotelName: 'Test Hotel',
            onChanged: () async {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('101'));
    await tester.pumpAndSettle();

    expect(find.text('Complete your booking'), findsOneWidget);
    expect(find.text('Upload government ID *'), findsOneWidget);
    expect(find.text('Submit booking'), findsOneWidget);
  });
}

class _DashboardHostHarness extends StatefulWidget {
  const _DashboardHostHarness({required this.child});

  final Widget child;

  @override
  State<_DashboardHostHarness> createState() => _DashboardHostHarnessState();
}

class _DashboardHostHarnessState extends State<_DashboardHostHarness> {
  @override
  Widget build(BuildContext context) {
    return AdminDashboardRoutes(
      openWalkIn: (room, onSuccess, completer) async {
        final payload = await showCompleteGuestBookingDialog(
          context: context,
          room: room,
          config: CompleteGuestBookingConfig.adminWalkIn(room),
        );
        completer.complete(payload != null);
      },
      openDetail: (_) {},
      closeFullScreen: () => false,
      isFullScreenOpen: false,
      child: Scaffold(body: widget.child),
    );
  }
}
