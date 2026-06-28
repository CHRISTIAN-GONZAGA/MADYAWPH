import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gloretto_mobile/flow/admin/widgets/admin_room_navigation.dart';

import 'test_helpers.dart';

void main() {
  setUp(initWidgetTestBindings);
  tearDown(clearWidgetTestBindings);

  testWidgets('bottom sheet room tap opens walk-in route after dismiss',
      (tester) async {
    late BuildContext hostContext;

    await tester.pumpWidget(
      MaterialApp(
        home: Navigator(
          onGenerateRoute: (settings) {
            return MaterialPageRoute<void>(
              builder: (navContext) {
                return Scaffold(
                  body: Builder(
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
                                  room: const {
                                    'id': 'room-1',
                                    'room_number': '101',
                                    'status': 'available',
                                    'price_per_night': 1500,
                                  },
                                  onSuccess: () async {},
                                  sheetContext: sheetContext,
                                ),
                              ),
                            );
                          },
                          child: const Text('Open vacant list'),
                        ),
                      );
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open vacant list'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Room 101'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Book this room'));
    await tester.pump();
    await advanceWalkInThroughCalendar(tester);

    expect(find.text('Complete your booking'), findsOneWidget);
  });
}
