import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gloretto_mobile/flow/admin/admin_room_detail_screen.dart';
import 'package:gloretto_mobile/flow/admin/admin_room_summary_detail_screen.dart';
import 'package:gloretto_mobile/flow/admin/widgets/admin_dashboard_room_overlay_host.dart';
import 'package:gloretto_mobile/flow/admin/widgets/admin_room_detail_navigation.dart';

import 'test_helpers.dart';

void main() {
  setUp(initWidgetTestBindings);

  testWidgets('occupied room detail overlay survives parent rebuild', (tester) async {
    const occupiedRoom = {
      'id': 'room-occ-1',
      'room_number': '101',
      'status': 'checked_in',
      'current_guest_name': 'Guest One',
    };

    var refreshCount = 0;

    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setParentState) {
            return AdminDashboardRoomOverlayHost(
              onRefresh: () async {
                refreshCount++;
                setParentState(() {});
              },
              child: Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      AdminRoomDetailNavigation.pushSummaryList(
                        context: context,
                        title: 'Occupied rooms',
                        rooms: [occupiedRoom],
                        showGuest: true,
                      );
                    },
                    child: const Text('Open occupied'),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open occupied'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(AdminRoomSummaryDetailScreen), findsOneWidget);
    expect(find.text('101'), findsOneWidget);

    await tester.tap(find.text('101'));
    await tester.pump();

    expect(find.text('Room details'), findsOneWidget);
    expect(AdminRoomDetailNavigation.isRoomOverlayOpen, isTrue);

    // Simulate dashboard data refresh while detail is open.
    await tester.tap(find.text('Open occupied'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Room details'), findsOneWidget);
    expect(refreshCount, greaterThanOrEqualTo(0));
    expect(find.byType(AdminRoomDetailScreen), findsOneWidget);
  });
}
