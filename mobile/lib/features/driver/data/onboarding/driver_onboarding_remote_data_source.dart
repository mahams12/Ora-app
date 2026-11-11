import '../../../../core/network/api_client.dart';
import '../../../../core/network/request_context.dart';
import '../../domain/driver_onboarding_application.dart';

abstract interface class DriverOnboardingRemoteDataSource {
  Future<DriverOnboardingResult> submit({
    required DriverOnboardingApplication application,
    required RequestContext context,
  });
}

class ApiDriverOnboardingRemoteDataSource
    implements DriverOnboardingRemoteDataSource {
  const ApiDriverOnboardingRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<DriverOnboardingResult> submit({
    required DriverOnboardingApplication application,
    required RequestContext context,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/drivers/onboarding',
      data: {
        'fullName': application.fullName,
        'cnicNumber': application.cnicNumber,
        'homeCity': application.homeCity,
        'licenseNumber': application.licenseNumber,
        'licenseExpiry': application.licenseExpiry,
        'vehicleCategory': application.vehicleCategory,
        'vehicleMake': application.vehicleMake,
        'vehicleModel': application.vehicleModel,
        'vehicleYear': application.vehicleYear,
        'vehicleColor': application.vehicleColor,
        'plateNumber': application.plateNumber,
      },
      context: context,
    );
    final data = response.data?['data'];
    if (data is! Map) {
      throw const FormatException('Invalid driver onboarding response.');
    }
    return DriverOnboardingResult(
      driverStatus: data['driverStatus'] is String
          ? data['driverStatus'] as String
          : 'pending',
      approved: data['approved'] == true,
    );
  }
}
