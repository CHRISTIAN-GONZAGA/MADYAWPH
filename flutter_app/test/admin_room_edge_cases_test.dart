import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gloretto_mobile/flow/admin/sections/room_board_section.dart';

void main() {
  testWidgets('room without id shows snackbar not gray screen', (tester) async {
    final rooms = [
      {
        'room_number': '101',
        'status': 'available',
        'price_per_night': 1500,
      },
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoomBoardSection(
            rooms: rooms,
            hotelName: 'Test Hotel',
            onChanged: () async {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('101'));
    await tester.pumpAndSettle();

    expect(find.text('Guest details'), findsNothing);
    expect(find.textContaining('Room ID missing'), findsOneWidget);
  });

  testWidgets('hourly available room opens booking form', (tester) async {
    final rooms = [
      {
        'id': 'room-hourly',
        'room_number': '202',
        'status': 'available',
        'billing_mode': 'hourly',
        'block_hours': 3,
        'price_per_block': 500,
      },
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoomBoardSection(
            rooms: rooms,
            hotelName: 'Test Hotel',
            onChanged: () async {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('202'));
    await tester.pumpAndSettle();

    expect(find.text('Guest details'), findsOneWidget);
  });
}
