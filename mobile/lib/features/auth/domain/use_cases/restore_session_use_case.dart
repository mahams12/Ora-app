import '../entities/auth_user.dart';
import '../repositories/auth_repository.dart';

/// Attempts to restore a previously authenticated session on app start /
/// restart.
///
/// Returns [AuthUser] when a valid session is present (or was refreshed
/// successfully).  Returns null when no session exists or refresh failed.
class RestoreSessionUseCase {
  const RestoreSessionUseCase(this._repository);

  final AuthRepository _repository;

  Future<AuthUser?> call() => _repository.restoreSession();
}
