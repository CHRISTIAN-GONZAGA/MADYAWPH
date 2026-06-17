import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gloretto_mobile/flow/admin/admin_room_detail_screen.dart';
import 'package:gloretto_mobile/flow/admin/widgets/admin_hotel_totals_room_panel.dart';

import 'test_helpers.dart';

void main() {
  setUp(initWidgetTestBindings);

  testWidgets('hotel totals panel shows list title and room grid', (tester) async {
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
    expect(find.textContaining('tap a tile'), findsOneWidget);
  });

  testWidgets('hotel totals panel lays out on phone-sized screen', (tester) async {
    const occupiedRoom = {
      'id': 'room-occ-1',
      'room_number': '101',
      'status': 'checked_in',
      'current_guest_name': 'Guest One',
    };

    await tester.binding.setSurfaceSize(const Size(360, 800));
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
    expect(find.textContaining('tap a tile'), findsOneWidget);
  });

  testWidgets('hotel totals panel shows room detail body with app bar',
      (tester) async {
    const occupiedRoom = {
      'id': 'room-occ-1',
      'room_number': '101',
      'status': 'checked_in',
      'current_guest_name': 'Guest One',
    };

    await tester.binding.setSurfaceSize(const Size(360, 800));
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

    openHotelTotalsRoomDetail(hostContext, room: occupiedRoom);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Room details'), findsOneWidget);
    expect(find.byType(AdminRoomDetailScreen), findsOneWidget);
    expect(find.text('Room 101'), findsOneWidget);
    expect(find.text('Booking info'), findsOneWidget);
  });

  testWidgets('room detail stays visible after panel host rebuild', (tester) async {
    const occupiedRoom = {
      'id': 'room-occ-1',
      'room_number': '101',
      'status': 'checked_in',
      'current_guest_name': 'Guest One',
    };

    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    late BuildContext hostContext;
    late VoidCallback rebuildHost;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setHostState) {
            rebuildHost = () => setHostState(() {});
            return HotelTotalsRoomPanelHost(
              child: Builder(
                builder: (context) {
                  hostContext = context;
                  return const Scaffold(body: SizedBox());
                },
              ),
            );
          },
        ),
      ),
    );

    openHotelTotalsRoomDetail(hostContext, room: occupiedRoom);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Room details'), findsOneWidget);
    expect(find.text('Room 101'), findsOneWidget);

    rebuildHost();
    await tester.pump();

    expect(find.text('Room details'), findsOneWidget);
    expect(find.text('Room 101'), findsOneWidget);
    expect(find.text('Booking info'), findsOneWidget);
  });
}
