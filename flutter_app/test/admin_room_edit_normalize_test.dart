import 'package:flutter_test/flutter_test.dart';
import 'package:gloretto_mobile/flow/admin/widgets/admin_room_editor.dart';
import 'package:gloretto_mobile/flow/admin/widgets/admin_room_form_constants.dart';

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

    test('coerces string prices from API', () {
      final normalized = normalizeAdminRoomForEdit({
        'id': 'room-3',
        'price_per_night': '1500.00',
        'price_per_block': '500',
        'block_hours': '3',
        'floor': '2',
      });

      expect(normalized['price_per_night'], 1500.0);
      expect(normalized['price_per_block'], 500.0);
      expect(normalized['block_hours'], 3);
      expect(normalized['floor'], 2);
    });
  });

  group('safeAdminRoomRateLabel', () {
    test('formats nightly rate when price is a string', () {
      expect(
        safeAdminRoomRateLabel({
          'billing_mode': 'nightly',
          'price_per_night': '2000',
        }),
        '₱2000 / night',
      );
    });
  });
}
