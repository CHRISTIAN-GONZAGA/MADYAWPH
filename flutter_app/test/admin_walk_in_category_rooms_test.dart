import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gloretto_mobile/flow/admin/sections/admin_booking_section.dart';
import 'package:gloretto_mobile/navigation_keys.dart';

void main() {
  testWidgets('admin booking section shows message when hotel id missing',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: appNavigatorKey,
        home: AdminBookingSection(
          hotelId: '',
          hotelName: 'Test Hotel',
          onChanged: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Hotel ID missing'), findsOneWidget);
  });
}
