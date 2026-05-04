import 'package:dio/dio.dart';

import 'auth_storage.dart';
import 'config.dart';

String dioErrorMessage(DioException e) {
  final data = e.response?.data;
  if (data is Map && data['message'] is String) {
    return data['message'] as String;
  }
  return e.message ?? e.type.name;
}

enum _AuthKind { none, portal, guest }

Dio _baseDio() => Dio(
      BaseOptions(
        baseUrl: kApiBaseUrl,
        connectTimeout: const Duration(seconds: 25),
        receiveTimeout: const Duration(seconds: 25),
        headers: {Headers.acceptHeader: 'application/json'},
      ),
    );

/// Unauthenticated v1 calls (hotel gate, register, portal login, public customer).
Dio publicDio() => _baseDio();

Dio _authedDio(_AuthKind kind) {
  final dio = _baseDio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        if (kind == _AuthKind.portal) {
          final t = await AuthStorage.portalToken();
          if (t != null && t.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $t';
          }
        } else {
          final t = await AuthStorage.guestToken();
          if (t != null && t.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $t';
          }
        }
        handler.next(options);
      },
    ),
  );
  return dio;
}

Dio portalDio() => _authedDio(_AuthKind.portal);

Dio guestDio() => _authedDio(_AuthKind.guest);
