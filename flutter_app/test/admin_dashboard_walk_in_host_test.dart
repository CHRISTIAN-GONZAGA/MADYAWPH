import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gloretto_mobile/flow/admin/sections/room_board_section.dart';
import 'package:gloretto_mobile/flow/admin/widgets/admin_dashboard_routes.dart';
import 'package:gloretto_mobile/flow/admin/widgets/admin_room_navigation.dart';
import 'package:gloretto_mobile/flow/admin/widgets/manual_booking_dialog.dart';

void main() {
  testWidgets('walk-in tab uses dashboard full-screen host', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: _DashboardHostHarness(
          child: RoomBoardSection(
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

    await tester.tap(find.text('101'));
    await tester.pumpAndSettle();

    expect(find.text('Guest details'), findsOneWidget);
    expect(find.textContaining('Walk-in'), findsOneWidget);
  });
}

class _DashboardHostHarness extends StatefulWidget {
  const _DashboardHostHarness({required this.child});

  final Widget child;

  @override
  State<_DashboardHostHarness> createState() => _DashboardHostHarnessState();
}

class _DashboardHostHarnessState extends State<_DashboardHostHarness> {
  Map<String, dynamic>? _walkInRoom;
  Future<void> Function()? _onSuccess;
  Completer<bool>? _completer;

  void _openWalkIn(
    Map<String, dynamic> room,
    Future<void> Function() onSuccess,
    Completer<bool> completer,
  ) {
    setState(() {
      _walkInRoom = room;
      _onSuccess = onSuccess;
      _completer = completer;
    });
  }

  void _closeWalkIn({required bool success}) {
    _completer?.complete(success);
    setState(() {
      _walkInRoom = null;
      _onSuccess = null;
      _completer = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_walkInRoom != null) {
      return AdminDashboardRoutes(
        openWalkIn: _openWalkIn,
        openDetail: (_) {},
        closeFullScreen: () => _closeWalkIn(success: false),
        isFullScreenOpen: true,
        child: AdminWalkInBookingScreen(
          room: _walkInRoom!,
          onSuccess: () async {
            await _onSuccess?.call();
            _closeWalkIn(success: true);
          },
          onClose: (success) {
            if (!success) _closeWalkIn(success: false);
          },
        ),
      );
    }

    return AdminDashboardRoutes(
      openWalkIn: _openWalkIn,
      openDetail: (_) {},
      closeFullScreen: () => false,
      isFullScreenOpen: false,
      child: Scaffold(body: widget.child),
    );
  }
}
