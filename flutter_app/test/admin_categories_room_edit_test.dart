import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gloretto_mobile/dio_client.dart';
import 'package:gloretto_mobile/flow/admin_categories.dart';
import 'package:gloretto_mobile/navigation_keys.dart';
import 'package:gloretto_mobile/ui/app_theme.dart';

import 'test_helpers.dart';

void main() {
  setUp(() {
    initWidgetTestBindings();
    portalDioTestOverride = () {
      final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final path = options.uri.path;
            if (path.endsWith('/room-categories')) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': [
                      {
                        'id': 'cat-1',
                        'name': 'Deluxe',
                        'default_price': 1500,
                        'billing_mode': 'nightly',
                        'floor_count': 2,
                      },
                    ],
                  },
                ),
              );
              return;
            }
            if (path.contains('/admin/rooms/cat-1') ||
                path.endsWith('/admin/rooms/room-101')) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'room': {
                      'id': 'room-101',
                      'room_number': '101',
                      'display_name': 'Deluxe 101',
                      'category_id': 'cat-1',
                      'price_per_night': 1500,
                      'billing_mode': 'nightly',
                      'status': 'available',
                      'room_type': 'Deluxe',
                      'floor': 1,
                    },
                  },
                ),
              );
              return;
            }
            if (path.endsWith('/admin/rooms')) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': [
                      {
                        'id': 'room-101',
                        'room_number': '101',
                        'display_name': 'Deluxe 101',
                        'category_id': 'cat-1',
                        'price_per_night': 1500,
                        'billing_mode': 'nightly',
                        'status': 'available',
                        'room_type': 'Deluxe',
                        'floor': 1,
                      },
                    ],
                  },
                ),
              );
              return;
            }
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: <String, dynamic>{},
              ),
            );
          },
        ),
      );
      return dio;
    };
  });

  tearDown(clearWidgetTestBindings);

  testWidgets('room categories edit opens full-screen editor on nested navigator',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: appNavigatorKey,
        theme: AppTheme.light(const Color(0xFF2563EB)),
        home: Navigator(
          key: adminDashboardNavigatorKey,
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => const AdminCategoriesScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Deluxe'), findsOneWidget);
    await tester.tap(find.text('Deluxe'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit a room in this category'));
    await tester.pumpAndSettle();

    expect(find.text('Edit room 101'), findsOneWidget);
    expect(find.text('Display name'), findsOneWidget);
    expect(find.text('Price per night (PHP)'), findsOneWidget);
    expect(find.text('Save'), findsWidgets);
  });
}
