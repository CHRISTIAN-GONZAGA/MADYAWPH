import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gloretto_mobile/flow/public_hotel_search_screen.dart';
import 'package:gloretto_mobile/locale_controller.dart';
import 'package:gloretto_mobile/ui/app_theme.dart';

void main() {
  testWidgets('Public landing builds', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: AppTheme.light(const Color(0xFF1A2B4A)),
        home: LocaleScope(
          builder: (context, _) => const PublicHotelSearchScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.textContaining('Where would you like to go'), findsOneWidget);
    expect(find.textContaining('Book a stay'), findsOneWidget);
    expect(find.byIcon(Icons.badge_outlined), findsWidgets);
  });
}
