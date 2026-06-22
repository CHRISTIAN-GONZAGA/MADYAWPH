import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gloretto_mobile/dio_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mocks [AuthStorage] prefs and portal HTTP for widget tests.
void initWidgetTestBindings() {
  SharedPreferences.setMockInitialValues({
    'auth_storage_migrated_v2': true,
  });
  portalDioTestOverride = _mockPortalDio;
}

void clearWidgetTestBindings() {
  portalDioTestOverride = null;
}

Dio _mockPortalDio() {
  final dio = Dio(BaseOptions(baseUrl: 'http://test'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final path = options.uri.path;
        if (path.contains('stay-calendar')) {
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {'stays': <dynamic>[]},
            ),
          );
          return;
        }
        if (path.contains('amenity-menu')) {
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {'data': <dynamic>[]},
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
}

/// Walk-in booking shows a stay calendar before the guest form.
Future<void> advanceWalkInThroughCalendar(WidgetTester tester) async {
  await tester.pumpAndSettle();

  if (find.textContaining('Select dates').evaluate().isEmpty) {
    return;
  }

  final tomorrow = DateTime.now().add(const Duration(days: 1));
  await tester.tap(find.text('${tomorrow.day}').first);
  await tester.pumpAndSettle();

  final continueButton = find.widgetWithText(FilledButton, 'Continue');
  expect(tester.widget<FilledButton>(continueButton).onPressed, isNotNull);
  await tester.tap(continueButton);
  await tester.pumpAndSettle();
}
