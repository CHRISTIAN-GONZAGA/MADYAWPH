import 'package:flutter_test/flutter_test.dart';
import 'package:gloretto_mobile/utils/money_format.dart';

void main() {
  test('parseJsonDouble handles num and string amounts', () {
    expect(parseJsonDouble(150), 150);
    expect(parseJsonDouble(99.5), 99.5);
    expect(parseJsonDouble('2500.00'), 2500);
    expect(parseJsonDouble(' 100 '), 100);
    expect(parseJsonDouble(null), 0);
    expect(parseJsonDouble(''), 0);
    expect(parseJsonDouble('not-a-number'), 0);
  });

  test('formatBillLineAmount accepts string charge amounts', () {
    expect(
      formatBillLineAmount({'amount': '150.50', 'type': 'manual'}),
      '₱150.50',
    );
    expect(
      formatBillLineAmount({'amount': '25', 'type': 'refund'}),
      '−₱25.00',
    );
  });
}
