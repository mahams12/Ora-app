import '../../../../core/network/api_client.dart';
import '../../../../core/network/request_context.dart';

/// Durable driver availability snapshot returned by
/// GET /v1/drivers/availability and the go-online/go-offline mutations.
class DriverAvailabilitySnapshot {
  const DriverAvailabilitySnapshot({required this.availabilityState});

  /// 'online' | 'offline' — server-validated enum; anything else is treated
  /// as offline by callers (never trust an unknown label).
  final String availabilityState;

  bool get isOnline => availabilityState == 'online';
}

/// HTTP adapter for the driver availability endpoints (N1).
abstract class DriverAvailabilityRemoteDataSource {
  Future<DriverAvailabilitySnapshot> getAvailability({
    RequestContext? context,
  });

  Future<DriverAvailabilitySnapshot> goOnline({RequestContext? context});

  Future<DriverAvailabilitySnapshot> goOffline({RequestContext? context});
}

/// Uses existing [ApiClient] auth/interceptors. Never fabricates state —
/// failures surface as [AppFailure] to the caller.
class ApiDriverAvailabilityRemoteDataSource
    implements DriverAvailabilityRemoteDataSource {
  const ApiDriverAvailabilityRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<DriverAvailabilitySnapshot> getAvailability({
    RequestContext? context,
  }) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/drivers/availability',
      context: context,
    );
    return _parse(response.data);
  }

  @override
  Future<DriverAvailabilitySnapshot> goOnline({RequestContext? context}) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/drivers/go-online',
      data: const <String, Object?>{},
      context: context,
    );
    return _parse(response.data);
  }

  @override
  Future<DriverAvailabilitySnapshot> goOffline({RequestContext? context}) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/drivers/go-offline',
      data: const <String, Object?>{},
      context: context,
    );
    return _parse(response.data);
  }

  DriverAvailabilitySnapshot _parse(Map<String, dynamic>? envelope) {
    final data = envelope?['data'];
    if (data is Map) {
      final state = data['availabilityState'];
      return DriverAvailabilitySnapshot(
        availabilityState: state is String ? state : 'offline',
      );
    }
    return const DriverAvailabilitySnapshot(availabilityState: 'offline');
  }
}
