import '../features/driver/domain/driver_onboarding_application.dart';
import '../features/driver/domain/repositories/driver_onboarding_repository.dart';
import 'demo_session_store.dart';

/// DEMO/REVIEW BUILD ONLY — driver onboarding resolves instantly to
/// APPROVED and stamps the local demo session, unlocking the driver shell.
/// The production admin-review path is untouched.
class DemoDriverOnboardingRepository implements DriverOnboardingRepository {
  const DemoDriverOnboardingRepository(this._session);

  final DemoSessionStore _session;

  @override
  Future<DriverOnboardingResult> submit(
    DriverOnboardingApplication application,
  ) async {
    await _session.approveDriver(displayName: application.fullName);
    return const DriverOnboardingResult(
      driverStatus: 'approved',
      approved: true,
    );
  }
}
