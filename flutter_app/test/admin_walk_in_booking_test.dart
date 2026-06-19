import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gloretto_mobile/flow/admin/widgets/admin_walk_in_stay_calendar_dialog.dart';
import 'package:gloretto_mobile/navigation_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'auth_storage_migrated_v2': true,
    });
  });

  testWidgets('walk-in calendar opens before guest details', (tester) async {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final dayAfter = tomorrow.add(const Duration(days: 1));

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: appNavigatorKey,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  await showWalkInRoomStayCalendar(
                    context: context,
                    room: const {
                      'id': 'room-1',
                      'room_number': '101',
                      'status': 'available',
                      'billing_mode': 'nightly',
                    },
                    prefetchedStays: const [],
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Select dates'), findsOneWidget);

    final tomorrowDay = '${tomorrow.day}';
    await tester.tap(find.text(tomorrowDay).first);
    await tester.pumpAndSettle();

    final dayAfterDay = '${dayAfter.day}';
    await tester.tap(find.text(dayAfterDay).first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Select dates'), findsNothing);
  });
}
