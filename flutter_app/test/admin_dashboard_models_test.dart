import 'package:flutter_test/flutter_test.dart';
import 'package:gloretto_mobile/flow/admin/admin_dashboard_models.dart';

void main() {
  group('isAwaitingCheckIn', () {
    test('includes reserved with check-in tomorrow', () {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final room = {
        'status': 'reserved',
        'latest_booking': {
          'check_in_date': tomorrow.toIso8601String().split('T').first,
        },
      };
      expect(AdminDashboardModels.isAwaitingCheckIn(room), isTrue);
    });

    test('includes available room with tomorrow booking', () {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final room = {
        'status': 'available',
        'latest_booking': {
          'check_in_date': tomorrow.toIso8601String().split('T').first,
        },
      };
      expect(AdminDashboardModels.isAwaitingCheckIn(room), isTrue);
      expect(
        AdminDashboardModels.isSummaryReserved(room, maxDaysAhead: 1),
        isTrue,
      );
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

    test('excludes reserved with check-in beyond tomorrow', () {
      final dayAfterTomorrow = DateTime.now().add(const Duration(days: 2));
      final room = {
        'status': 'reserved',
        'latest_booking': {
          'check_in_date': dayAfterTomorrow.toIso8601String().split('T').first,
        },
      };
      expect(AdminDashboardModels.isAwaitingCheckIn(room), isFalse);
    });
  });

  group('walkInTileStatus', () {
    test('available room is green status', () {
      expect(
        AdminDashboardModels.walkInTileStatus({'status': 'available'}),
        'available',
      );
    });

    test('available room with future latest_booking is reserved status', () {
      final future = DateTime.now().add(const Duration(days: 3));
      expect(
        AdminDashboardModels.walkInTileStatus({
          'status': 'available',
          'latest_booking': {
            'check_in_date': future.toIso8601String().split('T').first,
          },
        }),
        'reserved',
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

  group('isSummaryOccupied', () {
    test('checked_in room is occupied', () {
      expect(
        AdminDashboardModels.isSummaryOccupied({
          'status': 'checked_in',
          'current_guest_name': 'Guest 1',
        }),
        isTrue,
      );
    });

    test('maintenance with guest is occupied', () {
      expect(
        AdminDashboardModels.isSummaryOccupied({
          'status': 'maintenance',
          'current_guest_name': 'Guest 1',
        }),
        isTrue,
      );
    });

    test('vacant available room is not occupied', () {
      expect(
        AdminDashboardModels.isSummaryOccupied({'status': 'available'}),
        isFalse,
      );
    });
  });

  group('guestName', () {
    test('maintenance without guest does not show completed booking guest', () {
      expect(
        AdminDashboardModels.guestName({
          'status': 'maintenance',
          'latest_booking': {'guest_name': 'Old Guest'},
        }),
        '—',
      );
    });

    test('falls back to latest_booking for checked-in room', () {
      expect(
        AdminDashboardModels.guestName({
          'status': 'checked_in',
          'latest_booking': {'guest_name': 'In House Guest'},
        }),
        'In House Guest',
      );
    });

    test('checked_out room is walk-in bookable', () {
      expect(
        AdminDashboardModels.isWalkInBookable({'status': 'checked_out'}),
        isTrue,
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

  group('breakfastPrepSummary', () {
    test('counts pending and fulfilled breakfast quantities', () {
      final summary = AdminDashboardModels.breakfastPrepSummary([
        {
          'amenityName': 'Continental Breakfast',
          'quantity': 2,
          'status': 'pending',
        },
        {
          'amenity_type': 'Breakfast',
          'amenityName': 'Filipino Breakfast',
          'quantity': 1,
          'status': 'fulfilled',
        },
        {
          'amenityName': 'Extra Towels',
          'quantity': 3,
          'status': 'pending',
        },
      ]);
      expect(summary['to_prepare'], 2);
      expect(summary['done'], 1);
      expect(summary['pending_orders'], 1);
      expect(summary['fulfilled_orders'], 1);
    });

    test('formatFreeBreakfast shows quantities', () {
      expect(
        AdminDashboardModels.formatFreeBreakfast([
          {'name': 'Continental Breakfast', 'quantity': 2},
          'Filipino Breakfast',
        ]),
        '2× Continental Breakfast, Filipino Breakfast',
      );
    });
  });

  group('floor helpers', () {
    test('sortRoomsByNumber orders numerically', () {
      final sorted = AdminDashboardModels.sortRoomsByNumber([
        {'room_number': '102'},
        {'room_number': '2'},
        {'room_number': '11'},
      ]);
      expect(
        sorted.map((r) => r['room_number']).toList(),
        ['2', '11', '102'],
      );
    });

    test('distinctFloors and roomsOnFloor', () {
      final rooms = [
        {'room_number': '201', 'floor': 2},
        {'room_number': '101', 'floor': 1},
        {'room_number': '102', 'floor': 1},
      ];
      expect(AdminDashboardModels.distinctFloors(rooms), [1, 2]);
      expect(
        AdminDashboardModels.roomsOnFloor(rooms, 1)
            .map((r) => r['room_number'])
            .toList(),
        ['101', '102'],
      );
    });

    test('bookingRecordStatusLabel uses checked in when room is occupied', () {
      expect(
        AdminDashboardModels.bookingRecordStatusLabel(
          {'status': 'booked', 'room_status': 'checked_in'},
        ),
        'Checked in',
      );
      expect(
        AdminDashboardModels.bookingRecordStatusLabel(
          {'status': 'booked'},
          room: {'status': 'checked_in'},
        ),
        'Checked in',
      );
      expect(
        AdminDashboardModels.bookingRecordStatusLabel({'status': 'booked'}),
        'Booked',
      );
      expect(
        AdminDashboardModels.bookingRecordStatusLabel({'status': 'reserved'}),
        'Reserved',
      );
    });
  });
}
