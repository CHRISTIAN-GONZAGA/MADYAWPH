import 'package:flutter_test/flutter_test.dart';
import 'package:gloretto_mobile/flow/admin/widgets/hourly_billing.dart';

void main() {
  test('nightly walk-in checkout is 11:00 on checkout day', () {
    final room = {'billing_mode': 'nightly', 'price_per_night': 1500};
    final checkIn = DateTime(2026, 5, 30);
    final checkOut = DateTime(2026, 5, 31);

    final inAt = HourlyBilling.customerStayCheckIn(checkIn);
    final outAt = HourlyBilling.customerStayCheckOut(room, checkIn, checkOut);

    expect(inAt.hour, 14);
    expect(outAt.hour, 11);
    expect(outAt.isAfter(inAt), isTrue);
    expect(outAt.difference(inAt).inHours, greaterThanOrEqualTo(20));
  });

  test('hourly same-day checkout adds block hours after check-in', () {
    final room = {
      'billing_mode': 'hourly',
      'block_hours': 3,
      'price_per_block': 500,
    };
    final day = DateTime(2026, 5, 30);

    final inAt = HourlyBilling.customerStayCheckIn(day);
    final outAt = HourlyBilling.customerStayCheckOut(room, day, day);

    expect(outAt.difference(inAt).inHours, 3);
  });
}
