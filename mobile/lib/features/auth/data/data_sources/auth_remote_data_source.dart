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
    required RequestContext context,
  }) async {
    final response = await _apiClient.patch<Map<String, dynamic>>(
      '/auth/profile',
      data: {'displayName': displayName},
      context: context,
      idempotent: true,
    );
    return UserProfileModel.fromJson(response.data!);
  }
}
