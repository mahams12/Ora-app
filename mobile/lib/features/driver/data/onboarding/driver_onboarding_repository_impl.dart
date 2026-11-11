import '../../../../core/network/api_client.dart';
import '../../domain/driver_onboarding_application.dart';
import '../../domain/repositories/driver_onboarding_repository.dart';
import 'driver_onboarding_remote_data_source.dart';

class DriverOnboardingRepositoryImpl implements DriverOnboardingRepository {
  const DriverOnboardingRepositoryImpl({
    required DriverOnboardingRemoteDataSource remote,
    required ApiClient apiClient,
  }) : _remote = remote,
       _apiClient = apiClient;

  final DriverOnboardingRemoteDataSource _remote;
  final ApiClient _apiClient;

  @override
  Future<DriverOnboardingResult> submit(
    DriverOnboardingApplication application,
  ) => _remote.submit(
    application: application,
    context: _apiClient.newContext(operationId: 'driver_onboarding'),
  );
}
