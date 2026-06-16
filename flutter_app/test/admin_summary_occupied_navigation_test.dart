import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gloretto_mobile/flow/admin/widgets/admin_dashboard_routes.dart';
import 'package:gloretto_mobile/flow/admin/widgets/admin_room_navigation.dart';
import 'package:gloretto_mobile/navigation_keys.dart';
import 'package:gloretto_mobile/widgets/dashboard_exit_guard.dart';

import 'test_helpers.dart';

void main() {
  setUp(initWidgetTestBindings);

  testWidgets('summary-style occupied room tap opens in-shell room details',
      (tester) async {
    String? openedRoomId;
    const occupiedRoom = {
      'id': 'room-occ-1',
      'room_number': '101',
      'status': 'checked_in',
      'current_guest_name': 'Guest 1',
    };

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: appNavigatorKey,
        home: DashboardExitGuard(
          navigatorKey: adminDashboardNavigatorKey,
          child: Scaffold(
            body: Navigator(
              key: adminDashboardNavigatorKey,
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (_) => AdminDashboardRoutes(
                  openDetail: (id) => openedRoomId = id,
                  closeFullScreen: () {},
                  isFullScreenOpen: false,
                  child: Builder(
                    builder: (hostContext) => Scaffold(
                      body: Center(
                        child: FilledButton(
                          onPressed: () => AdminRoomNavigation.openRoom(
                            hostContext,
                            room: occupiedRoom,
                            onSuccess: () async {},
                            mode: AdminRoomOpenMode.manageOnly,
                          ),
                          child: const Text('Open occupied room'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open occupied room'));
    await tester.pump();

    expect(openedRoomId, 'room-occ-1');
  });
}
