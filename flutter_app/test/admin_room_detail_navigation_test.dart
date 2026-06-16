import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gloretto_mobile/flow/admin/widgets/admin_dashboard_routes.dart';
import 'package:gloretto_mobile/flow/admin/widgets/admin_room_navigation.dart';
import 'package:gloretto_mobile/navigation_keys.dart';
import 'package:gloretto_mobile/widgets/dashboard_exit_guard.dart';

import 'test_helpers.dart';

void main() {
  setUp(initWidgetTestBindings);

  testWidgets('occupied room opens in-shell detail instead of blank push',
      (tester) async {
    String? openedRoomId;

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
                  child: const Scaffold(
                    body: Center(child: Text('Dashboard home')),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final context = tester.element(find.text('Dashboard home'));
    await AdminRoomNavigation.openDetailById(context, 'room-occupied-1');
    await tester.pump();

    expect(openedRoomId, 'room-occupied-1');
  });
}
