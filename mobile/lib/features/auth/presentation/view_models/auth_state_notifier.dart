import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';
import '../../../../core/errors/app_failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/auth_user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/use_cases/resolve_auth_profile_use_case.dart';
import '../../domain/use_cases/restore_session_use_case.dart';
import 'auth_view_state.dart';

/// Tracks the global authentication status used by route guards.
///
/// Listens to [AuthRepository.authStateChanges] and maps Firebase Auth
/// identity into an authoritative Ora session via `POST /auth/register` +
/// `GET /auth/me`. Views never call Firebase or the API directly.
class AuthStateNotifier extends Notifier<AuthStatus> {
  late final AuthRepository _authRepository;
  late final RestoreSessionUseCase _restoreSession;
  late final ResolveAuthProfileUseCase _resolveProfile;
  late final AppLogger _logger;
  StreamSubscription<AuthUser?>? _authSub;

  /// Monotonic counter so overlapping Firebase emissions don't apply stale
  /// profile results after a newer sign-out / sign-in.
  int _profileEpoch = 0;

  @override
  AuthStatus build() {
    _authRepository = ref.read(authRepositoryProvider);
    _restoreSession = ref.read(restoreSessionUseCaseProvider);
    _resolveProfile = ref.read(resolveAuthProfileUseCaseProvider);
    _logger = ref.read(appLoggerProvider);

    ref.onDispose(() => _authSub?.cancel());

    _authSub = _authRepository.authStateChanges.listen(
      _onAuthStateChanged,
      onError: (_) {
        state = AuthStatus.unauthenticated;
      },
    );

    _restoreSessionOnStartup();

    return AuthStatus.unknown;
  }

  Future<void> _restoreSessionOnStartup() async {
    final user = await _restoreSession();
    if (user == null) {
      // Only demote if nothing else already signed the user in.
      if (state == AuthStatus.unknown) {
        state = AuthStatus.unauthenticated;
      }
    }
    // If user != null, authStateChanges fires and updates state.
  }

  Future<void> _onAuthStateChanged(AuthUser? user) async {
    if (user == null) {
      _profileEpoch++;
      state = AuthStatus.unauthenticated;
      return;
    }

    // Hold splash while the backend decides onboarding vs home.
    state = AuthStatus.authenticated;
    await _bootstrapProfile(user);
  }

  Future<void> _bootstrapProfile(AuthUser user) async {
    final epoch = ++_profileEpoch;
    try {
      final profile = await _resolveProfile(uid: user.uid);
      if (epoch != _profileEpoch) {
        return;
      }

      if (!profile.isActive || profile.banned) {
        _logger.warning(
          'Account disabled by server; clearing session',
          metadata: {'op': 'resolve_profile'},
        );
        await _authRepository.logout();
        if (epoch == _profileEpoch) {
          state = AuthStatus.unauthenticated;
        }
        return;
      }

      state = profile.profileComplete
          ? AuthStatus.authenticatedReady
          : AuthStatus.onboardingRequired;
    } on AppFailure catch (failure) {
      if (epoch != _profileEpoch) {
        return;
      }
      _logger.warning(
        'Profile bootstrap failed',
        metadata: {
          'op': 'resolve_profile',
          'failure': failure.runtimeType.toString(),
        },
      );
      // Fail closed: stay on splash (`authenticated`) so home is never granted
      // without a server profile. Caller can retry via [retryProfileBootstrap].
      state = AuthStatus.authenticated;
    } catch (e) {
      if (epoch != _profileEpoch) {
        return;
      }
      _logger.warning(
        'Profile bootstrap failed',
        metadata: {'op': 'resolve_profile', 'error': e.toString()},
      );
      state = AuthStatus.authenticated;
    }
  }

  /// Re-runs register + /me for the current Firebase user (backend recovery /
  /// onboarding placeholder refresh).
  Future<void> retryProfileBootstrap() async {
    final user = await _authRepository.getCurrentUser();
    if (user == null) {
      state = AuthStatus.unauthenticated;
      return;
    }
    state = AuthStatus.authenticated;
    await _bootstrapProfile(user);
  }

  /// Called after profile fetch confirms full readiness.
  void setAuthenticatedReady() => state = AuthStatus.authenticatedReady;

  /// Called when profile exists but onboarding steps remain.
  void setOnboardingRequired() => state = AuthStatus.onboardingRequired;

  /// Called on logout.
  void clearSession() => state = AuthStatus.unauthenticated;
}
