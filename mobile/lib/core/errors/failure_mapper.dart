import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:flutter/foundation.dart';

import 'app_failure.dart';

/// Maps infrastructure exceptions to typed [AppFailure] values.
///
/// UI-facing messages are **stable and sanitized**. Raw Firebase / Dio /
/// stack strings are never passed through as [AppFailure.userMessage].
class FailureMapper {
  const FailureMapper();

  AppFailure fromException(Object error, [StackTrace? stackTrace]) {
    if (error is AppFailure) {
      return error;
    }
    if (error is DioException) {
      return fromDioException(error);
    }
    if (error is FirebaseAuthException) {
      return fromFirebaseAuthException(error);
    }
    return const AppFailure.unknown();
  }

  // Maps Firebase Auth error codes to typed failures.
  // Server is authoritative; we do NOT infer OTP validity here.
  // Never surface Firebase Exception.message to the UI.
  AppFailure fromFirebaseAuthException(FirebaseAuthException error) {
    return switch (error.code) {
      'invalid-phone-number' || 'missing-phone-number' =>
        const AppFailure.invalidPhone(),
      'invalid-verification-code' || 'invalid-verification-id' =>
        const AppFailure.invalidOtp(),
      'code-expired' || 'session-expired' => const AppFailure.otpExpired(),
      'too-many-requests' || 'quota-exceeded' =>
        const AppFailure.tooManyAttempts(),
      'user-disabled' || 'account-exists-with-different-credential' =>
        const AppFailure.accountDisabled(),
      'user-token-expired' || 'requires-recent-login' =>
        const AppFailure.sessionExpired(),
      'network-request-failed' => const AppFailure.network(),
      'operation-not-allowed' => const AppFailure.forbidden(
          message: 'This sign-in method is not available.',
        ),
      _ => const AppFailure.unknown(),
    };
  }

  AppFailure fromDioException(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const AppFailure.timeout();
      case DioExceptionType.connectionError:
        // True transport failure (API down, reverse tunnel missing, offline).
        // Do not confuse with HTTP 4xx/5xx — those use badResponse below.
        return AppFailure.network(
          message: kDebugMode
              ? 'Cannot reach Ora API (${error.requestOptions.uri.host}). '
                  'Is auth-service running and adb reverse / LAN configured?'
              : null,
        );
      case DioExceptionType.badResponse:
        return _fromResponse(error.response);
      case DioExceptionType.cancel:
        return const AppFailure.network(message: 'Request cancelled');
      case DioExceptionType.badCertificate:
        return const AppFailure.network(message: 'Secure connection failed');
      case DioExceptionType.transformTimeout:
        return const AppFailure.timeout();
      case DioExceptionType.unknown:
        // Dio wraps some socket failures as unknown.
        final underlying = error.error?.toString() ?? '';
        if (underlying.contains('SocketException') ||
            underlying.contains('Connection refused') ||
            underlying.contains('Network is unreachable')) {
          return AppFailure.network(
            message: kDebugMode
                ? 'Cannot reach Ora API (${error.requestOptions.uri.host}). '
                    'Is auth-service running and adb reverse / LAN configured?'
                : null,
          );
        }
        return const AppFailure.unknown();
    }
  }

  AppFailure _fromResponse(Response<dynamic>? response) {
    final statusCode = response?.statusCode;
    final body = response?.data;
    final code = _extractCode(body);
    // Only trust short, stable messages from our own API envelope.
    final message = _publicApiMessage(_extractMessage(body));

    if (statusCode == 400) {
      return AppFailure.validation(
        message: message,
        fieldErrors: _extractFieldErrors(body),
      );
    }
    if (statusCode == 401) {
      if (code == 'OTP_EXPIRED') {
        return AppFailure.otpExpired(message: message);
      }
      if (code == 'SESSION_EXPIRED') {
        return AppFailure.sessionExpired(message: message);
      }
      if (code == 'APP_CHECK_REQUIRED' || code == 'APP_CHECK_INVALID') {
        return AppFailure.unauthorized(
          message: message ?? 'App verification failed. Please try again.',
        );
      }
      return AppFailure.unauthorized(message: message);
    }
    if (statusCode == 403) {
      if (code == 'ACCOUNT_DISABLED') {
        return AppFailure.accountDisabled(message: message);
      }
      return AppFailure.forbidden(message: message);
    }
    if (statusCode == 404) {
      if (code == 'RATING_NOT_FOUND') {
        return AppFailure.notFound(
          message: message ?? 'You have not rated this ride yet.',
        );
      }
      return AppFailure.notFound(message: message);
    }
    if (statusCode == 409) {
      if (code == 'ALREADY_RATED') {
        return AppFailure.conflict(
          message: message ?? 'You already rated this ride.',
          code: code,
        );
      }
      if (code == 'STATE_CONFLICT') {
        return AppFailure.conflict(
          message: message ??
              'This ride cannot be rated in its current server state.',
          code: code,
        );
      }
      return AppFailure.conflict(message: message, code: code);
    }
    if (statusCode == 422) {
      if (code == 'INVALID_OTP') {
        return AppFailure.invalidOtp(message: message);
      }
      if (code == 'INVALID_PHONE') {
        return AppFailure.invalidPhone(message: message);
      }
      return AppFailure.validation(
        message: message,
        fieldErrors: _extractFieldErrors(body),
      );
    }
    if (statusCode == 429) {
      if (code == 'OTP_COOLDOWN') {
        return AppFailure.otpCooldown(message: message);
      }
      if (code == 'RATE_LIMITED') {
        return AppFailure.tooManyAttempts(
          message: message ?? 'Too many requests. Please try again later.',
        );
      }
      return AppFailure.tooManyAttempts(message: message);
    }
    if (statusCode != null && statusCode >= 500 && statusCode < 600) {
      return AppFailure.server(message: message, statusCode: statusCode);
    }
    return AppFailure.network(
      message: message,
      statusCode: statusCode,
      code: code,
    );
  }

  /// Accept only short, single-line API messages from our backend envelope.
  String? _publicApiMessage(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed.length > 160) return null;
    if (trimmed.contains('\n') || trimmed.contains('\r')) return null;
    final lower = trimmed.toLowerCase();
    if (lower.contains('exception') ||
        lower.contains('stack') ||
        lower.contains('service account') ||
        lower.contains('authorization') ||
        lower.contains('bearer ') ||
        lower.contains('firestore') ||
        lower.contains('sql')) {
      return null;
    }
    return trimmed;
  }

  String? _extractMessage(Object? body) {
    if (body is Map) {
      final error = body['error'];
      if (error is Map) {
        final message = error['message'];
        return message is String ? message : null;
      }
      final message = body['message'];
      return message is String ? message : null;
    }
    return null;
  }

  String? _extractCode(Object? body) {
    if (body is Map) {
      final error = body['error'];
      if (error is Map) {
        final code = error['code'];
        return code is String ? code : null;
      }
    }
    return null;
  }

  Map<String, List<String>>? _extractFieldErrors(Object? body) {
    if (body is Map) {
      final error = body['error'];
      if (error is Map) {
        final details = error['details'];
        if (details is Map) {
          return details.map(
            (key, value) => MapEntry(
              key.toString(),
              (value is List)
                  ? value.map((e) => e.toString()).toList()
                  : <String>[],
            ),
          );
        }
      }
    }
    return null;
  }
}
