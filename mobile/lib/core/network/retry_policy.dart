import 'package:dio/dio.dart';

/// Safe retry policy — never retries non-idempotent mutations by default.
class RetryPolicy {
  const RetryPolicy({
    this.maxAttempts = 3,
    this.initialDelay = const Duration(milliseconds: 300),
  });

  final int maxAttempts;
  final Duration initialDelay;

  bool shouldRetry(DioException error, int attempt) {
    if (attempt >= maxAttempts) {
      return false;
    }

    final method = error.requestOptions.method.toUpperCase();
    final idempotent = error.requestOptions.extra['idempotent'] == true;

    // Never retry POST/PATCH/DELETE unless explicitly marked idempotent.
    if (!idempotent && method != 'GET' && method != 'HEAD') {
      return false;
    }

    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.connectionError =>
        true,
      DioExceptionType.badResponse =>
        error.response?.statusCode == 503 ||
            error.response?.statusCode == 429,
      _ => false,
    };
  }

  Duration delayForAttempt(int attempt) =>
      Duration(milliseconds: initialDelay.inMilliseconds * (1 << (attempt - 1)));
}
