import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gloretto_mobile/flow/admin/admin_dashboard_models.dart';
import 'package:gloretto_mobile/flow/admin/admin_room_detail_screen.dart';
import 'package:gloretto_mobile/flow/admin/widgets/admin_dashboard_routes.dart';
import 'package:gloretto_mobile/flow/admin/widgets/admin_room_navigation.dart';

import 'test_helpers.dart';

void main() {
  setUp(initWidgetTestBindings);

  test('occupied summary room resolves id for detail navigation', () {
    const room = {
      'id': 'room-occ-1',
      'room_number': '101',
      'status': 'checked_in',
      'current_guest_name': 'Guest 1',
    };
    expect(AdminDashboardModels.roomIdOf(room), 'room-occ-1');
    expect(AdminDashboardModels.isSummaryOccupied(room), isTrue);
  });

  testWidgets('summary occupied tap opens in-shell room details', (tester) async {
    String? openedId;

    await tester.pumpWidget(
      MaterialApp(
        home: AdminDashboardRoutes(
          openDetail: (id) => openedId = id,
          closeFullScreen: () {},
          isFullScreenOpen: false,
          child: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => AdminRoomNavigation.openDetailById(
                    'room-occ-1',
                    snackContext: context,
                  ),
                  child: const Text('Open occupied'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open occupied'));
    await tester.pump();

    expect(openedId, 'room-occ-1');
    expect(find.byType(AdminRoomDetailScreen), findsNothing);
  });
}
