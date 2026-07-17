import 'package:flutter_test/flutter_test.dart';
import 'package:gloretto_mobile/flow/admin/widgets/hourly_billing.dart';

void main() {
  test('nightly clock-based checkout is 11:00 on checkout day', () {
    final room = {'billing_mode': 'nightly', 'price_per_night': 1500};
    final checkIn = DateTime(2026, 5, 30);
    final checkOut = DateTime(2026, 5, 31);
    final now = DateTime(2026, 5, 30, 14, 5, 0);

    final window = HourlyBilling.clockBasedStayWindow(
      room,
      checkIn,
      checkOutDate: checkOut,
      now: now,
    );

    expect(window.checkIn.hour, 14);
    expect(window.checkIn.minute, 5);
    expect(window.checkOut.hour, 11);
    expect(window.checkOut.isAfter(window.checkIn), isTrue);
  });

  test('hourly same-day checkout adds block hours after clock check-in', () {
    final room = {
      'billing_mode': 'hourly',
      'block_hours': 3,
      'price_per_block': 500,
    };
    final day = DateTime(2026, 5, 30);
    final now = DateTime(2026, 5, 30, 15, 2, 0);

    final window = HourlyBilling.clockBasedStayWindow(
      room,
      day,
      checkOutDate: day,
      now: now,
    );

    expect(window.checkIn.hour, 15);
    expect(window.checkIn.minute, 2);
    expect(window.checkOut.hour, 18);
    expect(window.checkOut.minute, 2);
    expect(window.checkOut.difference(window.checkIn).inHours, 3);
  });

  test('per-hour extension fee is hours times category rate', () {
    expect(HourlyBilling.customHoursExtensionFee(200, 24), 4800);
    expect(HourlyBilling.customHoursExtensionFee(200, 5), 1000);
    expect(HourlyBilling.customHoursExtensionFee(200, 1), 200);
  });

  test('block extension fee uses price per block', () {
    final room = {
      'billing_mode': 'hourly',
      'block_hours': 3,
      'price_per_block': 1000,
    };
    expect(HourlyBilling.blockExtensionFee(room), 1000);
  });
}
