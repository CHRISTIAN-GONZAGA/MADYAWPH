import 'package:flutter_test/flutter_test.dart';
import 'package:gloretto_mobile/main.dart';

void main() {
  testWidgets('App builds', (WidgetTester tester) async {
    await tester.pumpWidget(const GlorettoApp());
    expect(find.text('Gloretto'), findsOneWidget);
  });
}
