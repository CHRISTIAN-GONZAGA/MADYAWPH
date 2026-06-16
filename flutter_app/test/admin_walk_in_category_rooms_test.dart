import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gloretto_mobile/flow/admin/sections/admin_walk_in_category_rooms_screen.dart';
import 'package:gloretto_mobile/navigation_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'auth_storage_migrated_v2': true,
    });
  });

  testWidgets('walk-in category room tap opens customer-style booking dialog',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: appNavigatorKey,
        home: AdminWalkInCategoryRoomsScreen(
          hotelId: 'hotel-1',
          categoryName: 'Standard',
          onBooked: () async {},
          rooms: const [
            {
              'id': 'room-1',
              'room_number': '101',
              'display_name': 'Queen',
              'status': 'available',
              'price_per_night': 1500,
              'billing_mode': 'nightly',
            },
          ],
        ),
      ),
    );

    await tester.tap(find.textContaining('Room 101'));
    await tester.pumpAndSettle();

    expect(find.text('Complete your booking'), findsOneWidget);
    expect(find.text('Submit booking'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });
}
