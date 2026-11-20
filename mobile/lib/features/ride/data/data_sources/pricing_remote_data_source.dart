import 'package:dio/dio.dart';

import '../../../../core/network/api_client.dart';
import '../../domain/ports/pricing_estimate_port.dart';

/// HTTP client for POST /v1/pricing/estimate. Never fabricates fares/snapshots.
class PricingRemoteDataSource implements PricingEstimatePort {
  const PricingRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<PricingEstimate> estimate(PricingEstimateRequest request) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/pricing/estimate',
        data: request.toJson(),
      );
      final body = response.data;
      if (body is! Map<String, dynamic>) {
        throw const PricingClientException(
          PricingFailureKind.unknown,
          'Empty pricing response.',
        );
      }
      final data = body['data'];
      if (data is! Map) {
        throw const PricingClientException(
          PricingFailureKind.unknown,
          'Malformed pricing response.',
        );
      }
      return PricingEstimate.fromJson(Map<String, dynamic>.from(data));
    } on PricingClientException {
      rethrow;
    } on DioException catch (e) {
      throw _mapDio(e);
    } on FormatException catch (e) {
      throw PricingClientException(
        PricingFailureKind.unknown,
        e.message,
      );
    }
  }

  PricingClientException _mapDio(DioException error) {
    final status = error.response?.statusCode;
    final body = error.response?.data;
    String? code;
    String? message;
    if (body is Map) {
      final err = body['error'];
      if (err is Map) {
        final c = err['code'];
        final m = err['message'];
        if (c is String) code = c;
        if (m is String) message = m;
      }
    }

    if (code == 'ROUTE_UNAVAILABLE' || status == 422 && code == 'ROUTE_UNAVAILABLE') {
      return PricingClientException(
        PricingFailureKind.routeUnavailable,
        message ?? 'Unable to determine a route for those points.',
      );
    }
    if (code == 'PRICING_UNAVAILABLE' ||
        (status != null && status >= 500) ||
        status == 503) {
      return PricingClientException(
        PricingFailureKind.pricingUnavailable,
        message ?? 'Pricing isn\'t available right now. Please try again later.',
      );
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.connectionError) {
      return PricingClientException(
        PricingFailureKind.network,
        message ?? 'Network error. Check your connection.',
      );
    }
    if (status == 400 || status == 422) {
      return PricingClientException(
        PricingFailureKind.validation,
        message ?? 'Please check your trip details.',
      );
    }
    return PricingClientException(
      PricingFailureKind.unknown,
      message ?? 'Pricing isn\'t available right now. Please try again later.',
    );
  }
}
