import '../entities/user_profile.dart';
import '../repositories/auth_repository.dart';

/// After Firebase identity exists, bootstrap the Ora user and load /me.
///
/// ```
/// Firebase Auth success
///   → POST /v1/auth/register (idempotent)
///   → GET  /v1/auth/me
///   → authoritative UserProfile
/// ```
class ResolveAuthProfileUseCase {
  const ResolveAuthProfileUseCase(this._repository);

  final AuthRepository _repository;

  Future<UserProfile> call({required String uid}) async {
    // Always attempt register: Idempotency-Key = register_{uid}. Safe if the
    // document already exists; repairs the case where a prior register failed.
    await _repository.registerUser(uid: uid);
    return _repository.getUserProfile(uid: uid);
  }
}
