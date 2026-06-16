import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gloretto_mobile/flow/admin/admin_room_detail_screen.dart';
import 'package:gloretto_mobile/flow/admin/widgets/admin_room_detail_navigation.dart';
import 'package:gloretto_mobile/navigation_keys.dart';

import 'test_helpers.dart';

void main() {
  setUp(initWidgetTestBindings);

  testWidgets('occupied room opens as slide-up bottom sheet', (tester) async {
    const occupiedRoom = {
      'id': 'room-occ-1',
      'room_number': '101',
      'status': 'checked_in',
      'current_guest_name': 'Guest One',
    };

    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: appNavigatorKey,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () {
                  AdminRoomDetailNavigation.showRoomDetailSheet(
                    roomId: 'room-occ-1',
                    context: context,
                  );
                },
                child: const Text('Open detail'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open detail'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Room details'), findsOneWidget);
    expect(find.byType(AdminRoomDetailScreen), findsOneWidget);
    expect(AdminRoomDetailNavigation.isRoomOverlayOpen, isTrue);
  });

  testWidgets('occupied room list opens as slide-up sheet', (tester) async {
    const occupiedRoom = {
      'id': 'room-occ-1',
      'room_number': '101',
      'status': 'checked_in',
      'current_guest_name': 'Guest One',
    };

    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: appNavigatorKey,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () {
                  AdminRoomDetailNavigation.showRoomListSheet(
                    context: context,
                    title: 'Occupied rooms',
                    rooms: [occupiedRoom],
                    showGuest: true,
                  );
                },
                child: const Text('Open list'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open list'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Occupied rooms'), findsOneWidget);
    expect(find.text('101'), findsOneWidget);
  });
}
