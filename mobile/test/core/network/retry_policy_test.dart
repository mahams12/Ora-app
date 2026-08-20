import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ora/core/network/retry_policy.dart';

void main() {
  const policy = RetryPolicy(maxAttempts: 3);

  RequestOptions options({required String method, bool idempotent = false}) {
    return RequestOptions(
      path: '/rides',
      method: method,
      extra: {'idempotent': idempotent},
    );
  }

  test('does not retry non-idempotent POST', () {
    final error = DioException(
      requestOptions: options(method: 'POST'),
      type: DioExceptionType.connectionTimeout,
    );

    expect(policy.shouldRetry(error, 1), isFalse);
  });

  test('retries idempotent POST when marked', () {
    final error = DioException(
      requestOptions: options(method: 'POST', idempotent: true),
      type: DioExceptionType.connectionTimeout,
    );

    expect(policy.shouldRetry(error, 1), isTrue);
  });

  test('stops after maxAttempts', () {
    final error = DioException(
      requestOptions: options(method: 'GET'),
      type: DioExceptionType.connectionTimeout,
    );

    expect(policy.shouldRetry(error, 3), isFalse);
  });
}
