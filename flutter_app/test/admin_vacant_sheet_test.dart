import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gloretto_mobile/flow/admin/widgets/admin_room_navigation.dart';
import 'package:gloretto_mobile/navigation_keys.dart';

void main() {
  testWidgets('bottom sheet room tap opens walk-in after dismiss', (tester) async {
    late BuildContext hostContext;

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: appNavigatorKey,
        home: Builder(
          builder: (context) {
            hostContext = context;
            return Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () {
                    showModalBottomSheet<void>(
                      context: context,
                      builder: (sheetContext) {
                        return SafeArea(
                          child: ListTile(
                            title: const Text('Room 101'),
                            onTap: () {
                              AdminRoomNavigation.openRoom(
                                hostContext,
                                room: const {
                                  'id': 'room-1',
                                  'room_number': '101',
                                  'status': 'available',
                                  'price_per_night': 1500,
                                  'category_name': 'Standard',
                                },
                                onSuccess: () async {},
                                sheetContext: sheetContext,
                              );
                            },
                          ),
                        );
                      },
                    );
                  },
                  child: const Text('Open vacant list'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open vacant list'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Room 101'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Guest details'), findsOneWidget);
    expect(find.textContaining('Walk-in'), findsOneWidget);
  });
}
