import 'package:flutter_test/flutter_test.dart';
import 'package:gloretto_mobile/flow/admin/admin_dashboard_models.dart';

void main() {
  group('isAwaitingCheckIn', () {
    test('includes reserved with future check-in', () {
      final tomorrow = DateTime.now().add(const Duration(days: 2));
      final room = {
        'status': 'reserved',
        'latest_booking': {
          'check_in_date': tomorrow.toIso8601String().split('T').first,
        },
      };
      expect(AdminDashboardModels.isAwaitingCheckIn(room), isTrue);
    });

    test('excludes reserved with past check-in', () {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final room = {
        'status': 'reserved',
        'latest_booking': {
          'check_in_date': yesterday.toIso8601String().split('T').first,
        },
      };
      expect(AdminDashboardModels.isAwaitingCheckIn(room), isFalse);
    });

    test('includes booked with check-in today', () {
      final today = DateTime.now();
      final room = {
        'status': 'booked',
        'latest_booking': {
          'check_in_date': today.toIso8601String().split('T').first,
        },
      };
      expect(AdminDashboardModels.isAwaitingCheckIn(room), isTrue);
    });
  });

  group('walkInTileStatus', () {
    test('available room is green status', () {
      expect(
        AdminDashboardModels.walkInTileStatus({'status': 'available'}),
        'available',
      );
    });

    test('future booked room is reserved status', () {
      final future = DateTime.now().add(const Duration(days: 3));
      expect(
        AdminDashboardModels.walkInTileStatus({
          'status': 'booked',
          'latest_booking': {
            'check_in_date': future.toIso8601String().split('T').first,
          },
        }),
        'reserved',
      );
    });

    test('checked in room is occupied', () {
      expect(
        AdminDashboardModels.walkInTileStatus({'status': 'checked_in'}),
        'occupied',
      );
    });
  });

  group('roomsForCategory', () {
    const rooms = [
      {
        'room_number': '101',
        'category_id': 'cat-1',
        'category_name': 'Deluxe',
      },
      {
        'room_number': '102',
        'category_id': 'cat-2',
        'category_name': 'Standard',
      },
    ];

    test('filters by category id', () {
      final filtered = AdminDashboardModels.roomsForCategory(
        rooms,
        categoryId: 'cat-1',
        categoryName: 'Deluxe',
      );
      expect(filtered.length, 1);
      expect(filtered.first['room_number'], '101');
    });
  });
}
