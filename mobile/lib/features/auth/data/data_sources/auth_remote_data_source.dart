import '../../../../core/network/api_client.dart';
import '../../../../core/network/request_context.dart';
import '../models/user_profile_model.dart';

/// Wraps the Ora Cloud Run API endpoints related to auth/user lifecycle.
///
/// Endpoints used (from frozen Phase 1.6 / 04-api-contracts.md):
///   POST /v1/auth/register  — first-time user document creation
///   GET  /v1/auth/me        — fetch own user profile
class AuthRemoteDataSource {
  const AuthRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  /// Creates the user document on first sign-in.
  /// Idempotent: safe to retry with same request if the call fails.
  Future<void> registerUser({
    required String uid,
    required RequestContext context,
  }) async {
    await _apiClient.post<void>(
      '/auth/register',
      data: {'uid': uid},
      context: context,
      idempotent: true,
    );
  }

  /// Loads the authenticated user's profile from the backend.
  Future<UserProfileModel> getMe({required RequestContext context}) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/auth/me',
      context: context,
    );
    return UserProfileModel.fromJson(response.data!);
  }

  /// Updates displayName only. Server derives profileComplete.
  Future<UserProfileModel> updateProfile({
    required String displayName,
    String? avatarData,
    bool clearAvatar = false,
    required RequestContext context,
  }) async {
    final response = await _apiClient.patch<Map<String, dynamic>>(
      '/auth/profile',
      data: {
        'displayName': displayName,
        if (clearAvatar)
          'avatarData': null
        else if (avatarData != null)
          'avatarData': avatarData,
      },
      context: context,
      idempotent: true,
    );
    return UserProfileModel.fromJson(response.data!);
  }

  /// POST /v1/auth/mode — server-authoritative Passenger ⇄ Driver switch.
  ///
  /// The server refuses with conflict codes surfaced via AppFailure:
  /// DRIVER_ONBOARDING_REQUIRED, DRIVER_APPROVAL_PENDING, DRIVER_SUSPENDED,
  /// ACTIVE_JOB (live booking/trip — response also carries activeRideId).
  Future<UserProfileModel> switchMode({
    required String mode,
    required RequestContext context,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/auth/mode',
      data: {'mode': mode},
      context: context,
      idempotent: true,
    );
    return UserProfileModel.fromJson(response.data!);
  }

  /// POST /v1/drivers/onboarding — first-time driver application.
  /// Idempotent server-side: replaying while pending/approved returns the
  /// current status unchanged.
  Future<Map<String, dynamic>> submitDriverOnboarding({
    required String vehicleType,
    String? vehicleModel,
    String? plateNumber,
    String? homeCity,
    required RequestContext context,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/drivers/onboarding',
      data: {
        'vehicleType': vehicleType,
        if (vehicleModel != null && vehicleModel.isNotEmpty)
          'vehicleModel': vehicleModel,
        if (plateNumber != null && plateNumber.isNotEmpty)
          'plateNumber': plateNumber,
        if (homeCity != null && homeCity.isNotEmpty) 'homeCity': homeCity,
      },
      context: context,
      idempotent: true,
    );
    final data = response.data;
    return data is Map<String, dynamic> ? data : const {};
  }

  /// POST /v1/auth/vendor-application — partner application (cargo /
  /// rental host / service provider). Idempotent server-side: replaying
  /// while pending or approved returns the profile unchanged. Returns the
  /// updated profile so the session can re-gate immediately.
  Future<UserProfileModel> submitVendorApplication({
    required String type,
    Map<String, dynamic>? details,
    required RequestContext context,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/auth/vendor-application',
      data: {
        'type': type,
        if (details != null && details.isNotEmpty) 'details': details,
      },
      context: context,
      idempotent: true,
    );
    return UserProfileModel.fromJson(response.data!);
  }
}
