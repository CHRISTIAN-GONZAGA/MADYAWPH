import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gloretto_mobile/flow/admin/widgets/manual_booking_dialog.dart';

void main() {
  testWidgets('AdminWalkInBookingScreen builds with app bar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdminWalkInBookingScreen(
          room: const {
            'id': 'room-1',
            'room_number': '101',
            'status': 'available',
            'price_per_night': 1500,
            'category_name': 'Standard',
            'billing_mode': 'nightly',
          },
          onSuccess: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Walk-in'), findsOneWidget);
    expect(find.text('Guest details'), findsOneWidget);
  });
}
