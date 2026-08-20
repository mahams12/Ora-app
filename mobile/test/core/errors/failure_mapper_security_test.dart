import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ora/core/errors/app_failure.dart';
import 'package:ora/core/errors/failure_mapper.dart';

void main() {
  const mapper = FailureMapper();

  test('Firebase errors never leak raw messages to UI', () {
    final failure = mapper.fromFirebaseAuthException(
      FirebaseAuthException(
        code: 'operation-not-allowed',
        message:
            'This operation is not allowed. [ SMS unable to be sent ... service account ...]',
      ),
    );
    expect(failure.userMessage.toLowerCase(), isNot(contains('sms')));
    expect(failure.userMessage.toLowerCase(), isNot(contains('service account')));
  });

  test('unknown Firebase codes use generic message', () {
    final failure = mapper.fromFirebaseAuthException(
      FirebaseAuthException(code: 'weird-internal', message: 'stack at foo'),
    );
    expect(failure, isA<UnknownFailure>());
    expect(failure.userMessage, 'An unexpected error occurred.');
  });

  test('RATE_LIMITED maps to tooManyAttempts with stable message', () {
    final failure = mapper.fromDioException(
      DioException(
        requestOptions: RequestOptions(path: '/v1/auth/me'),
        response: Response(
          requestOptions: RequestOptions(path: '/v1/auth/me'),
          statusCode: 429,
          data: {
            'error': {
              'code': 'RATE_LIMITED',
              'message': 'Too many requests. Please try again later.',
            },
          },
        ),
        type: DioExceptionType.badResponse,
      ),
    );
    expect(failure, isA<TooManyAttemptsFailure>());
    expect(failure.userMessage, contains('Too many'));
  });

  test('strips suspicious API messages', () {
    final failure = mapper.fromDioException(
      DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 500,
          data: {
            'error': {
              'code': 'INTERNAL',
              'message': 'FirebaseException stack\nat line',
            },
          },
        ),
        type: DioExceptionType.badResponse,
      ),
    );
    expect(failure.userMessage, 'Something went wrong. Please try again.');
  });
}
