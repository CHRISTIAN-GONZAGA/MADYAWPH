import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gloretto_mobile/flow/admin/sections/room_board_section.dart';
import 'package:gloretto_mobile/navigation_keys.dart';

import 'test_helpers.dart';

void main() {
  setUp(initWidgetTestBindings);

  testWidgets('room without id shows snackbar not blank screen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: appNavigatorKey,
        home: Scaffold(
          body: RoomBoardSection(
            rooms: const [
              {
                'room_number': '999',
                'status': 'available',
              },
            ],
            hotelName: 'Test Hotel',
            onChanged: () async {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('999'));
    await tester.pumpAndSettle();

    expect(find.text('Complete your booking'), findsNothing);
    expect(find.textContaining('Room ID missing'), findsOneWidget);
  });

  testWidgets('hourly available room opens complete booking dialog',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: appNavigatorKey,
        home: Scaffold(
          body: RoomBoardSection(
            rooms: const [
              {
                'id': 'room-hourly',
                'room_number': '202',
                'status': 'available',
                'billing_mode': 'hourly',
                'block_hours': 3,
                'price_per_block': 500,
              },
            ],
            hotelName: 'Test Hotel',
            onChanged: () async {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('202'));
    await tester.pumpAndSettle();

    expect(find.text('Complete your booking'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });
}
