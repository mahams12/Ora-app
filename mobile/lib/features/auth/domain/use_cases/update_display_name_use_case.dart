import '../entities/user_profile.dart';
import '../repositories/auth_repository.dart';

/// Saves displayName via the auth API, then returns the server profile.
class UpdateDisplayNameUseCase {
  const UpdateDisplayNameUseCase(this._repository);

  final AuthRepository _repository;

  Future<UserProfile> call({required String displayName}) =>
      _repository.updateDisplayName(displayName: displayName);
}
