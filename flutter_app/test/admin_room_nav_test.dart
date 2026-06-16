import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gloretto_mobile/flow/widgets/complete_guest_booking_dialog.dart';
import 'package:gloretto_mobile/navigation_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'auth_storage_migrated_v2': true,
    });
  });

  testWidgets('navigation opens complete booking dialog', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: appNavigatorKey,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  showCompleteGuestBookingDialog(
                    context: context,
                    room: const {
                      'id': 'room-1',
                      'room_number': '101',
                      'status': 'available',
                      'price_per_night': 1500,
                    },
                    config: CompleteGuestBookingConfig.adminWalkIn(const {
                      'room_number': '101',
                    }),
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
