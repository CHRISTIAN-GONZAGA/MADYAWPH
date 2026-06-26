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

    expect(find.textContaining('Edit room 101'), findsOneWidget);
    expect(find.text('Display name'), findsOneWidget);
    expect(find.text('Price per night (PHP)'), findsOneWidget);
    expect(find.text('Save'), findsWidgets);
  });

  testWidgets('multi-room category shows picker sheet then editor',
      (tester) async {
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
                        'id': 'cat-family',
                        'name': 'Family Room',
                        'default_price': 2000,
                        'billing_mode': 'nightly',
                        'floor_count': 1,
                      },
                    ],
                  },
                ),
              );
              return;
            }
            if (path.endsWith('/admin/rooms/room-202')) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'room': {
                      'id': 'room-202',
                      'room_number': '202',
                      'display_name': 'Family 202',
                      'category_id': 'cat-family',
                      'price_per_night': 2000,
                      'billing_mode': 'nightly',
                      'status': 'checked_in',
                      'room_type': 'Suite',
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
                        'id': 'room-201',
                        'room_number': '201',
                        'category_id': 'cat-family',
                        'price_per_night': 1800,
                        'status': 'available',
                        'room_type': 'Double',
                      },
                      {
                        'id': 'room-202',
                        'room_number': '202',
                        'category_id': 'cat-family',
                        'price_per_night': 2000,
                        'status': 'available',
                        'room_type': 'Suite',
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

    await tester.tap(find.text('Family Room'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit a room in this category'));
    await tester.pumpAndSettle();

    expect(find.text('Select room · Family Room'), findsOneWidget);
    expect(find.text('Room 201'), findsOneWidget);
    expect(find.text('Room 202'), findsOneWidget);

    await tester.tap(find.text('Room 202'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Edit room 202'), findsOneWidget);
    expect(find.text('Display name'), findsOneWidget);
    expect(find.text('Price per night (PHP)'), findsOneWidget);
  });
}
