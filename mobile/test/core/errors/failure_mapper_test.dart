import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ora/core/errors/app_failure.dart';
import 'package:ora/core/errors/failure_mapper.dart';

void main() {
  const mapper = FailureMapper();

  group('FailureMapper', () {
    test('maps 401 to UnauthorizedFailure', () {
      final failure = mapper.fromDioException(
        DioException(
          requestOptions: RequestOptions(path: '/rides'),
          response: Response(
            requestOptions: RequestOptions(path: '/rides'),
            statusCode: 401,
            data: {
              'error': {'message': 'Sign in required'},
            },
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      expect(failure, isA<UnauthorizedFailure>());
      expect(failure.userMessage, 'Sign in required');
    });

    test('maps timeout types to TimeoutFailure', () {
      final failure = mapper.fromDioException(
        DioException(
          requestOptions: RequestOptions(path: '/rides'),
          type: DioExceptionType.connectionTimeout,
        ),
      );

      expect(failure, isA<TimeoutFailure>());
    });

    test('maps 409 to ConflictFailure', () {
      final failure = mapper.fromDioException(
        DioException(
          requestOptions: RequestOptions(path: '/rides/1/offers/1/select'),
          response: Response(
            requestOptions: RequestOptions(path: '/rides/1/offers/1/select'),
            statusCode: 409,
            data: {
              'error': {
                'code': 'ALREADY_ASSIGNED',
                'message': 'Ride already assigned',
              },
            },
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      expect(failure, isA<ConflictFailure>());
    });
  });
}
