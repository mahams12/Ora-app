import '../entities/user_profile.dart';
import '../repositories/auth_repository.dart';

/// Saves profile edits (display name and/or photo) via the auth API,
/// then returns the server profile.
class UpdateProfileUseCase {
  const UpdateProfileUseCase(this._repository);

  final AuthRepository _repository;

  Future<UserProfile> call({
    required String displayName,
    String? avatarData,
    bool clearAvatar = false,
  }) =>
      _repository.updateProfile(
        displayName: displayName,
        avatarData: avatarData,
        clearAvatar: clearAvatar,
      );
}
