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

  test('roomIdOf falls back to room_id field', () {
    expect(
      AdminDashboardModels.roomIdOf({
        'room_id': 'mongo-id-99',
        'status': 'checked_in',
      }),
      'mongo-id-99',
    );
  });
}
