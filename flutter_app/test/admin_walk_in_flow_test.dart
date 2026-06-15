import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gloretto_mobile/flow/admin/sections/manual_booking_section.dart';
import 'package:gloretto_mobile/flow/admin/sections/room_board_section.dart';
import 'package:gloretto_mobile/flow/admin/widgets/admin_room_navigation.dart';
import 'package:gloretto_mobile/navigation_keys.dart';
import 'package:gloretto_mobile/widgets/dashboard_exit_guard.dart';

/// Every path that opens walk-in booking must render the complete booking dialog.
void main() {
  group('dashboard nested navigator (walk-in tab)', () {
    testWidgets('room board gray tile opens complete booking dialog',
        (tester) async {
      await tester.pumpWidget(_productionDashboardApp(
        child: ManualBookingSection(
          rooms: _sampleRooms,
          hotelName: 'Test Hotel',
          onChanged: () async {},
        ),
      ));

      await tester.tap(find.text('101'));
      await tester.pumpAndSettle();

      expect(find.text('Complete your booking'), findsOneWidget);
      expect(find.text('Submit booking'), findsOneWidget);
      expect(find.byType(TextField), findsWidgets);
    });

    testWidgets('room board gray tile opens complete booking dialog (legacy harness)',
        (tester) async {
      await tester.pumpWidget(_dashboardApp(
        child: RoomBoardSection(
          rooms: _sampleRooms,
          hotelName: 'Test Hotel',
          onChanged: () async {},
        ),
      ));

      await tester.tap(find.text('101'));
      await tester.pumpAndSettle();

      expect(find.text('Complete your booking'), findsOneWidget);
      expect(find.text('Submit booking'), findsOneWidget);
    });

    testWidgets('bottom sheet vacant room opens dialog after dismiss',
        (tester) async {
      late BuildContext hostContext;

      await tester.pumpWidget(_dashboardApp(
        child: Builder(
          builder: (context) {
            hostContext = context;
            return Center(
              child: FilledButton(
                onPressed: () {
                  showModalBottomSheet<void>(
                    context: context,
                    builder: (sheetContext) => ListTile(
                      title: const Text('Room 101'),
                      onTap: () => AdminRoomNavigation.openRoom(
                        hostContext,
                        room: _sampleRooms.first,
                        onSuccess: () async {},
                        sheetContext: sheetContext,
                      ),
                    ),
                  );
                },
                child: const Text('Vacant list'),
              ),
            );
          },
        ),
      ));

      await tester.tap(find.text('Vacant list'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Room 101'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Complete your booking'), findsOneWidget);
    });
  });

  group('edge cases', () {
    testWidgets('missing room id shows snackbar not blank screen',
        (tester) async {
      await tester.pumpWidget(_dashboardApp(
        child: RoomBoardSection(
          rooms: const [
            {
              'room_number': '999',
              'status': 'available',
            },
          ],
          hotelName: 'Test Hotel',
          onChanged: () async {},
        ),
      ));

      await tester.tap(find.text('999'));
      await tester.pumpAndSettle();

      expect(find.text('Complete your booking'), findsNothing);
      expect(
        find.textContaining('Room ID missing'),
        findsOneWidget,
      );
    });
  });
}

const _sampleRooms = [
  {
    'id': 'room-1',
    'room_number': '101',
    'status': 'available',
    'price_per_night': 1500,
    'category_name': 'Standard',
    'billing_mode': 'nightly',
  },
];

Widget _dashboardApp({required Widget child}) {
  return MaterialApp(
    navigatorKey: appNavigatorKey,
    home: Navigator(
      onGenerateRoute: (settings) {
        return MaterialPageRoute<void>(
          builder: (_) => Scaffold(body: child),
        );
      },
    ),
  );
}

/// Mirrors [AdminDashboardScreen] nested navigator + exit guard.
Widget _productionDashboardApp({required Widget child}) {
  return MaterialApp(
    navigatorKey: appNavigatorKey,
    home: DashboardExitGuard(
      navigatorKey: adminDashboardNavigatorKey,
      child: Scaffold(
        body: Navigator(
          key: adminDashboardNavigatorKey,
          onGenerateRoute: (settings) {
            return MaterialPageRoute<void>(
              builder: (_) => Scaffold(body: child),
            );
          },
        ),
      ),
    ),
  );
}
