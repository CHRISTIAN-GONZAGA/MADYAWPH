import 'package:flutter_test/flutter_test.dart';
import 'package:gloretto_mobile/flow/admin/admin_dashboard_models.dart';

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

  test('vacant and occupied rooms share the same detail navigation entry', () {
    const vacant = {
      'id': 'room-vac-1',
      'room_number': '202',
      'status': 'available',
    };
    const occupied = {
      'id': 'room-occ-2',
      'room_number': '303',
      'status': 'checked_in',
      'current_guest_name': 'Guest',
    };
    expect(AdminDashboardModels.roomIdOf(vacant), isNotEmpty);
    expect(AdminDashboardModels.roomIdOf(occupied), isNotEmpty);
    expect(AdminDashboardModels.isWalkInBookable(vacant), isTrue);
    expect(AdminDashboardModels.isSummaryOccupied(occupied), isTrue);
  });
}
