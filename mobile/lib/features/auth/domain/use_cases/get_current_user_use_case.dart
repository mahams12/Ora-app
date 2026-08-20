import '../entities/auth_user.dart';
import '../repositories/auth_repository.dart';

/// Returns the current [AuthUser] snapshot, or null if unauthenticated.
class GetCurrentUserUseCase {
  const GetCurrentUserUseCase(this._repository);

  final AuthRepository _repository;

  Future<AuthUser?> call() => _repository.getCurrentUser();
}
