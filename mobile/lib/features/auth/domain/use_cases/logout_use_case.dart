import '../repositories/auth_repository.dart';

/// Signs out the current user: clears Firebase Auth state and wipes secure
/// storage (tokens, session IDs).
class LogoutUseCase {
  const LogoutUseCase(this._repository);

  final AuthRepository _repository;

  Future<void> call() => _repository.logout();
}
