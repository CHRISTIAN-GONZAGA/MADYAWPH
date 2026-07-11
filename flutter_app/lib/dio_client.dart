import 'dart:async';

import 'package:dio/dio.dart';

import 'auth_storage.dart';
import 'config.dart';

String dioErrorMessage(DioException e) {
  if (e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.sendTimeout) {
    return 'The server is slow to respond (often while waking up on Render). '
        'Check your internet, wait a moment, then tap Retry.';
  }
  if (e.type == DioExceptionType.connectionError) {
    return 'Cannot reach the server. Check your internet connection and try again.';
  }

  final response = e.response;
  final data = response?.data;
  if (data is Map) {
    final msg = data['message'];
    if (msg is String && msg.isNotEmpty) {
      if (response?.statusCode == 401 &&
          msg.toLowerCase().contains('unauthenticated')) {
        return 'Session expired. Please sign in again.';
      }
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

enum _AuthKind { portal, guest, member }

/// Longer timeouts for cold-hosted APIs (e.g. Render spin-up).
const kPublicConnectTimeout = Duration(seconds: 45);
const kPublicReceiveTimeout = Duration(seconds: 90);

Dio _baseDio({Duration? connectTimeout, Duration? receiveTimeout}) => Dio(
      BaseOptions(
        baseUrl: kApiBaseUrl,
        connectTimeout: connectTimeout ?? const Duration(seconds: 30),
        receiveTimeout: receiveTimeout ?? const Duration(seconds: 45),
        headers: {Headers.acceptHeader: 'application/json'},
      ),
    );

/// Unauthenticated v1 calls (hotel directory, register, portal login, public customer).
Dio publicDio() => _baseDio(
      connectTimeout: kPublicConnectTimeout,
      receiveTimeout: kPublicReceiveTimeout,
    );

/// Wake the API host in the background (Render cold start).
void warmPublicApi() {
  unawaited(
    publicDio()
        .get<void>(
          '/hotels',
          options: Options(receiveTimeout: kPublicReceiveTimeout),
        )
        .then((_) {}, onError: (_) {}),
  );
}

Dio _authedDio(_AuthKind kind) {
  final dio = _baseDio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        final String? t = switch (kind) {
          _AuthKind.portal => await AuthStorage.portalToken(),
          _AuthKind.guest => await AuthStorage.guestToken(),
          _AuthKind.member => await AuthStorage.memberToken(),
        };
        if (t != null && t.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $t';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          switch (kind) {
            case _AuthKind.portal:
              await AuthStorage.clearPortalAuth();
            case _AuthKind.guest:
              await AuthStorage.clearGuestAuth();
            case _AuthKind.member:
              await AuthStorage.clearMemberAuth();
          }
        }
        handler.next(error);
      },
    ),
  );
  return dio;
}

Dio portalDio() => portalDioTestOverride?.call() ?? _authedDio(_AuthKind.portal);

/// Same generous timeouts as [publicDio] — Render cold starts often exceed 45s.
Dio portalDioWithLongTimeout() {
  final dio = _baseDio(
    connectTimeout: kPublicConnectTimeout,
    receiveTimeout: kPublicReceiveTimeout,
  );
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        final t = await AuthStorage.portalToken();
        if (t != null && t.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $t';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          await AuthStorage.clearPortalAuth();
        }
        handler.next(error);
      },
    ),
  );
  return dio;
}

Dio guestDio() => _authedDio(_AuthKind.guest);

Dio memberDio() => _authedDio(_AuthKind.member);

/// Widget tests set this to mock walk-in calendar / amenity API calls.
Dio Function()? portalDioTestOverride;
