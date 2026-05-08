import 'package:dio/dio.dart';

import 'auth_storage.dart';
import 'config.dart';

String dioErrorMessage(DioException e) {
  final response = e.response;
  final data = response?.data;
  if (data is Map) {
    final msg = data['message'];
    if (msg is String && msg.isNotEmpty) {
      return msg;
    }
    final errors = data['errors'];
    if (errors is Map) {
      final parts = <String>[];
      for (final entry in errors.entries) {
        final v = entry.value;
        if (v is List) {
          parts.addAll(v.map((x) => x.toString()));
        } else {
          parts.add(v.toString());
        }
      }
      if (parts.isNotEmpty) {
        return parts.join(' ');
      }
    }
  }
  final code = response?.statusCode;
  if (code != null) {
    return 'HTTP $code ${e.message ?? e.type.name}';
  }
  return e.message ?? e.type.name;
}

enum _AuthKind { portal, guest }

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
