import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gloretto_mobile/flow/admin/sections/room_board_section.dart';
import 'package:gloretto_mobile/flow/admin/widgets/admin_dashboard_routes.dart';
import 'package:gloretto_mobile/navigation_keys.dart';

import 'test_helpers.dart';

void main() {
  setUp(initWidgetTestBindings);

  testWidgets('walk-in tab opens complete booking dialog on root navigator',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: appNavigatorKey,
        home: Navigator(
          onGenerateRoute: (settings) {
            return MaterialPageRoute<void>(
              builder: (_) => AdminDashboardRoutes(
                openDetail: (_) {},
                closeFullScreen: () => false,
                isFullScreenOpen: false,
                child: Scaffold(
                  body: RoomBoardSection(
                    rooms: const [
                      {
                        'id': 'room-1',
                        'room_number': '101',
                        'status': 'available',
                        'price_per_night': 1500,
                        'category_name': 'Standard',
                        'billing_mode': 'nightly',
                      },
                    ],
                    hotelName: 'Test Hotel',
                    onChanged: () async {},
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('101'));
    await tester.pumpAndSettle();

    expect(find.text('Complete your booking'), findsOneWidget);
    expect(find.textContaining('Upload government ID'), findsOneWidget);
    expect(find.text('Submit booking'), findsOneWidget);
  });
}
