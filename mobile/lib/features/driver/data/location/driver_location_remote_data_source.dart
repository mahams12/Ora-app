import 'package:dio/dio.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/request_context.dart';
import '../../domain/location/driver_location_fix.dart';

/// Result of a trip-mode location publish attempt.
sealed class LocationPublishResult {
  const LocationPublishResult();
}

final class LocationPublishAccepted extends LocationPublishResult {
  const LocationPublishAccepted({
    required this.locationSeq,
    required this.locationStreamId,
    required this.acceptedAt,
  });

  final int locationSeq;
  final String locationStreamId;
  final String? acceptedAt;
}

final class LocationPublishFailed extends LocationPublishResult {
  const LocationPublishFailed({
    required this.kind,
    this.statusCode,
    this.code,
  });

  final LocationPublishFailureKind kind;
  final int? statusCode;
  final String? code;
}

enum LocationPublishFailureKind {
  unauthorized,
  forbidden,
  sequenceViolation,
  invalidOrStale,
  rateLimited,
  server,
  timeout,
  network,
  cancelled,
  unknown,
}

/// HTTP adapter for POST /v1/location/update (trip + idle modes).
abstract class DriverLocationRemoteDataSource {
  Future<LocationPublishResult> publishTripLocation({
    required String rideId,
    required int locationSeq,
    required String locationStreamId,
    required DriverLocationFix fix,
    required CancelToken cancelToken,
    RequestContext? context,
  });

  /// Idle-mode publish — no rideId, so the server records it under the
  /// driver's idle stream and projects presence into the geo index. Online
  /// drivers need this to stay discoverable between trips.
  ///
  /// Default returns unsupported so pre-existing fakes stay valid; the HTTP
  /// adapter overrides it.
  Future<LocationPublishResult> publishIdleLocation({
    required int locationSeq,
    required String locationStreamId,
    required DriverLocationFix fix,
    required CancelToken cancelToken,
    RequestContext? context,
  }) async {
    return const LocationPublishFailed(
      kind: LocationPublishFailureKind.unknown,
    );
  }
}

/// Uses existing [ApiClient] auth/interceptors. Never marks the POST idempotent.
class ApiDriverLocationRemoteDataSource
    implements DriverLocationRemoteDataSource {
  const ApiDriverLocationRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<LocationPublishResult> publishTripLocation({
    required String rideId,
    required int locationSeq,
    required String locationStreamId,
    required DriverLocationFix fix,
    required CancelToken cancelToken,
    RequestContext? context,
  }) async {
    return _publish(
      rideId: rideId,
      locationSeq: locationSeq,
      locationStreamId: locationStreamId,
      fix: fix,
      cancelToken: cancelToken,
      context: context,
    );
  }

  @override
  Future<LocationPublishResult> publishIdleLocation({
    required int locationSeq,
    required String locationStreamId,
    required DriverLocationFix fix,
    required CancelToken cancelToken,
    RequestContext? context,
  }) async {
    return _publish(
      rideId: null,
      locationSeq: locationSeq,
      locationStreamId: locationStreamId,
      fix: fix,
      cancelToken: cancelToken,
      context: context,
    );
  }

  Future<LocationPublishResult> _publish({
    required String? rideId,
    required int locationSeq,
    required String locationStreamId,
    required DriverLocationFix fix,
    required CancelToken cancelToken,
    RequestContext? context,
  }) async {
    final heading = fix.headingDegrees;
    final body = <String, Object?>{
      // rideId omitted entirely in idle mode — the server treats its absence
      // as an idle (presence) stream, not a trip stream.
      if (rideId != null) 'rideId': rideId,
      'locationSeq': locationSeq,
      'locationStreamId': locationStreamId,
      'lat': fix.latitude,
      'lng': fix.longitude,
      'accuracy': fix.accuracyMeters,
      // Server requires a finite heading; unknown → 0.
      'heading': (heading != null && heading.isFinite) ? heading : 0,
      'speed': fix.speedKmh,
      'timestamp': fix.timestamp.toUtc().toIso8601String(),
      'provider': 'gps',
      if (fix.altitudeMeters != null && fix.altitudeMeters!.isFinite)
        'altitude': fix.altitudeMeters,
    };

    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/location/update',
        data: body,
        context: context,
        idempotent: false,
        cancelToken: cancelToken,
      );
      final data = _unwrapData(response.data);
      return LocationPublishAccepted(
        locationSeq: locationSeq,
        locationStreamId: locationStreamId,
        acceptedAt: data['acceptedAt'] is String
            ? data['acceptedAt'] as String
            : null,
      );
    } on DioException catch (error) {
      if (CancelToken.isCancel(error) ||
          error.type == DioExceptionType.cancel) {
        return const LocationPublishFailed(
          kind: LocationPublishFailureKind.cancelled,
        );
      }
      // ApiClient normally maps to AppFailure; keep a Dio fallback.
      return _fromStatus(
        statusCode: error.response?.statusCode,
        code: _extractCode(error.response?.data),
      );
    } on AppFailure catch (failure) {
      return _fromAppFailure(failure);
    } catch (_) {
      return const LocationPublishFailed(
        kind: LocationPublishFailureKind.unknown,
      );
    }
  }

  LocationPublishFailed _fromAppFailure(AppFailure failure) {
    return switch (failure) {
      UnauthorizedFailure() || SessionExpiredFailure() =>
        const LocationPublishFailed(
          kind: LocationPublishFailureKind.unauthorized,
          statusCode: 401,
        ),
      ForbiddenFailure() || AccountDisabledFailure() =>
        const LocationPublishFailed(
          kind: LocationPublishFailureKind.forbidden,
          statusCode: 403,
        ),
      TimeoutFailure() => const LocationPublishFailed(
          kind: LocationPublishFailureKind.timeout,
        ),
      NetworkFailure(:final statusCode, :final code) => _fromStatus(
          statusCode: statusCode,
          code: code,
        ),
      ValidationFailure(:final message) => LocationPublishFailed(
          kind: _isSequenceMessage(message)
              ? LocationPublishFailureKind.sequenceViolation
              : LocationPublishFailureKind.invalidOrStale,
          statusCode: 422,
          code: _isSequenceMessage(message) ? 'SEQUENCE_VIOLATION' : null,
        ),
      TooManyAttemptsFailure() => const LocationPublishFailed(
          kind: LocationPublishFailureKind.rateLimited,
          statusCode: 429,
        ),
      ServerFailure(:final statusCode) => LocationPublishFailed(
          kind: LocationPublishFailureKind.server,
          statusCode: statusCode,
        ),
      _ => const LocationPublishFailed(
          kind: LocationPublishFailureKind.unknown,
        ),
    };
  }

  LocationPublishFailed _fromStatus({
    required int? statusCode,
    required String? code,
  }) {
    if (statusCode == 401) {
      return LocationPublishFailed(
        kind: LocationPublishFailureKind.unauthorized,
        statusCode: statusCode,
        code: code,
      );
    }
    if (statusCode == 403) {
      return LocationPublishFailed(
        kind: LocationPublishFailureKind.forbidden,
        statusCode: statusCode,
        code: code,
      );
    }
    if (statusCode == 422) {
      final sequence = code == 'SEQUENCE_VIOLATION' ||
          (code != null && code.toUpperCase().contains('SEQUENCE'));
      return LocationPublishFailed(
        kind: sequence
            ? LocationPublishFailureKind.sequenceViolation
            : LocationPublishFailureKind.invalidOrStale,
        statusCode: statusCode,
        code: code,
      );
    }
    if (statusCode == 429) {
      return LocationPublishFailed(
        kind: LocationPublishFailureKind.rateLimited,
        statusCode: statusCode,
        code: code,
      );
    }
    if (statusCode != null && statusCode >= 500) {
      return LocationPublishFailed(
        kind: LocationPublishFailureKind.server,
        statusCode: statusCode,
        code: code,
      );
    }
    return LocationPublishFailed(
      kind: LocationPublishFailureKind.network,
      statusCode: statusCode,
      code: code,
    );
  }

  bool _isSequenceMessage(String? message) {
    if (message == null) return false;
    final m = message.toLowerCase();
    return m.contains('sequence') ||
        m.contains('stream is closed') ||
        m.contains('no longer active');
  }

  Map<String, dynamic> _unwrapData(Map<String, dynamic>? envelope) {
    if (envelope == null) return const {};
    final data = envelope['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return envelope;
  }

  String? _extractCode(Object? body) {
    if (body is! Map) return null;
    final error = body['error'];
    if (error is Map && error['code'] is String) {
      return error['code'] as String;
    }
    if (body['code'] is String) return body['code'] as String;
    return null;
  }
}
