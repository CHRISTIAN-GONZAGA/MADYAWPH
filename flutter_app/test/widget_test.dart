import 'package:flutter_test/flutter_test.dart';
import 'package:gloretto_mobile/main.dart';

void main() {
  testWidgets('App builds', (WidgetTester tester) async {
    await tester.pumpWidget(const GlorettoApp());
    await tester.pump();
    expect(find.textContaining('Tap anywhere'), findsOneWidget);
    await tester.tap(find.textContaining('Tap anywhere'));
    await tester.pumpAndSettle();
    expect(find.text('Hotel sign-in'), findsOneWidget);
  });
}
