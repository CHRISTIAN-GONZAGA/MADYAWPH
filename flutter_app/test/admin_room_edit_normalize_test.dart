import 'package:flutter_test/flutter_test.dart';
import 'package:gloretto_mobile/flow/admin/widgets/admin_room_editor.dart';

void main() {
  group('normalizeAdminRoomForEdit', () {
    test('maps unknown room type and enum-like status', () {
      final normalized = normalizeAdminRoomForEdit({
        'id': 'room-1',
        'room_type': 'Family',
        'status': 'RoomStatus.checked_in',
        'billing_mode': 'nightly',
      });

      expect(normalized['room_type'], 'Single');
      expect(normalized['status'], 'checked_in');
    });

    test('preserves valid deluxe room type', () {
      final normalized = normalizeAdminRoomForEdit({
        'id': 'room-2',
        'room_type': 'deluxe',
        'status': 'reserved',
      });

      expect(normalized['room_type'], 'Deluxe');
      expect(normalized['status'], 'reserved');
    });
  });
}
