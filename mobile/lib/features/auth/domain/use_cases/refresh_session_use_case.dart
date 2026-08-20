import '../repositories/auth_repository.dart';

/// Forces a Firebase ID-token refresh and returns the new token string.
///
/// Used by the API interceptor when a 401 is received and the refresh has
/// not already been issued for this failure window (single-flight guard is
/// in the token provider, not here).
class RefreshSessionUseCase {
  const RefreshSessionUseCase(this._repository);

  final AuthRepository _repository;

  Future<String> call() => _repository.refreshToken();
}
