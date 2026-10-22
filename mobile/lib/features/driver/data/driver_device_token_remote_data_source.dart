import '../../../core/network/api_client.dart';
import '../../../core/network/request_context.dart';

/// D1 — register/clear FCM device token (approved drivers only).
class DriverDeviceTokenRemoteDataSource {
  const DriverDeviceTokenRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<void> registerToken({
    required String token,
    required RequestContext context,
  }) async {
    await _apiClient.post<Map<String, dynamic>>(
      '/drivers/device-tokens',
      data: {'token': token},
      context: context,
    );
  }

  Future<void> clearToken({
    required String token,
    required RequestContext context,
  }) async {
    await _apiClient.delete<Map<String, dynamic>>(
      '/drivers/device-tokens',
      data: {'token': token},
      context: context,
    );
  }

  /// NOTIF-RS-PUSH — passenger token registration (role-gated server-side).
  Future<void> registerPassengerToken({
    required String token,
    required RequestContext context,
  }) async {
    await _apiClient.post<Map<String, dynamic>>(
      '/device-tokens',
      data: {'token': token},
      context: context,
    );
  }

  Future<void> clearPassengerToken({
    required String token,
    required RequestContext context,
  }) async {
    await _apiClient.delete<Map<String, dynamic>>(
      '/device-tokens',
      data: {'token': token},
      context: context,
    );
  }
}
