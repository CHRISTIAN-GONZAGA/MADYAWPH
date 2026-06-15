import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gloretto_mobile/flow/admin/widgets/manual_booking_dialog.dart';
import 'package:gloretto_mobile/navigation_keys.dart';

void main() {
  testWidgets('showAdminWalkInBookingDialog opens complete booking popup',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: appNavigatorKey,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () {
                  showAdminWalkInBookingDialog(
                    context: context,
                    room: const {
                      'id': 'room-1',
                      'room_number': '101',
                      'status': 'available',
                      'price_per_night': 1500,
                      'category_name': 'Standard',
                      'billing_mode': 'nightly',
                    },
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Complete your booking'), findsOneWidget);
    expect(find.text('Submit booking'), findsOneWidget);
  });
}
