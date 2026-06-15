import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gloretto_mobile/flow/admin/sections/room_board_section.dart';

void main() {
  testWidgets('walk-in tab room tap opens booking form via navigator push',
      (tester) async {
    final rooms = [
      {
        'id': '674a1b2c3d4e5f6789012345',
        'room_number': '101',
        'status': 'available',
        'price_per_night': 1500,
        'category_name': 'Deluxe',
        'billing_mode': 'nightly',
        'room_type': 'deluxe',
      },
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Navigator(
          onGenerateRoute: (settings) {
            return MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                body: RoomBoardSection(
                  rooms: rooms,
                  hotelName: 'Test Hotel',
                  onChanged: () async {},
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('101'));
    await tester.pumpAndSettle();

    expect(find.text('Guest details'), findsOneWidget);
  });
}
