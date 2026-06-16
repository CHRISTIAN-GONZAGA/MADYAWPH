import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gloretto_mobile/flow/admin/admin_room_detail_screen.dart';
import 'package:gloretto_mobile/flow/admin/widgets/admin_hotel_totals_room_panel.dart';

import 'test_helpers.dart';

void main() {
  setUp(initWidgetTestBindings);

  testWidgets('hotel totals panel slides up list then room details', (tester) async {
    const occupiedRoom = {
      'id': 'room-occ-1',
      'room_number': '101',
      'status': 'checked_in',
      'current_guest_name': 'Guest One',
    };

    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    late BuildContext hostContext;

    await tester.pumpWidget(
      MaterialApp(
        home: HotelTotalsRoomPanelHost(
          child: Builder(
            builder: (context) {
              hostContext = context;
              return const Scaffold(body: SizedBox());
            },
          ),
        ),
      ),
    );

    openHotelTotalsRoomList(
      hostContext,
      title: 'Occupied rooms',
      rooms: [occupiedRoom],
      showGuest: true,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Occupied rooms'), findsOneWidget);
    expect(find.text('101'), findsOneWidget);

    openHotelTotalsRoomDetail(hostContext, room: occupiedRoom);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Room details'), findsOneWidget);
    expect(find.byType(AdminRoomDetailScreen), findsOneWidget);
  });
}
