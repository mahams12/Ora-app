import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';
import '../../../../core/errors/app_failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/auth_user.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/use_cases/resolve_auth_profile_use_case.dart';
import '../../domain/use_cases/restore_session_use_case.dart';
import 'auth_bootstrap_diagnostics.dart';
import 'auth_view_state.dart';
import 'profile_bootstrap_ui_notifier.dart';
import 'session_user_profile.dart';

/// Tracks the global authentication status used by route guards.
///
/// Listens to [AuthRepository.authStateChanges] and maps Firebase Auth
/// identity into an authoritative Ora session via `POST /auth/register` +
/// `GET /auth/me`. Views never call Firebase or the API directly.
class AuthStateNotifier extends Notifier<AuthStatus> {
  static const _bootstrapAttemptTimeout = Duration(seconds: 35);
  static const _maxBootstrapAttempts = 3;
  static const _autoRetryDelay = Duration(milliseconds: 800);

  late final AuthRepository _authRepository;
  late final RestoreSessionUseCase _restoreSession;
  late final ResolveAuthProfileUseCase _resolveProfile;
  late final AppLogger _logger;
  late final AuthBootstrapDiagnostics _diag;
  StreamSubscription<AuthUser?>? _authSub;

  /// Monotonic counter so overlapping Firebase emissions don't apply stale
  /// profile results after a newer sign-out / sign-in.
  int _profileEpoch = 0;

  Future<void>? _bootstrapInFlight;

  @override
  AuthStatus build() {
    _authRepository = ref.read(authRepositoryProvider);
    _restoreSession = ref.read(restoreSessionUseCaseProvider);
    _resolveProfile = ref.read(resolveAuthProfileUseCaseProvider);
    _logger = ref.read(appLoggerProvider);
    _diag = AuthBootstrapDiagnostics(_logger);

    ref.onDispose(() => _authSub?.cancel());

    _authSub = _authRepository.authStateChanges.listen(
      _onAuthStateChanged,
      onError: (_) {
        ref.read(sessionUserProfileProvider.notifier).clear();
        ref.read(profileBootstrapUiProvider.notifier).clear();
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
      ref.read(sessionUserProfileProvider.notifier).clear();
      ref.read(profileBootstrapUiProvider.notifier).clear();
      state = AuthStatus.unauthenticated;
      return;
    }

    // Hold splash while the backend decides onboarding vs home.
    state = AuthStatus.authenticated;
    await _bootstrapProfile(user);
  }

  Future<void> _bootstrapProfile(
    AuthUser user, {
    bool manualRetry = false,
  }) async {
    if (_bootstrapInFlight != null && !manualRetry) {
      return _bootstrapInFlight!;
    }

    _bootstrapInFlight = _runBootstrap(user, manualRetry: manualRetry)
        .whenComplete(() => _bootstrapInFlight = null);
    return _bootstrapInFlight!;
  }

  Future<void> _runBootstrap(
    AuthUser user, {
    required bool manualRetry,
  }) async {
    final epoch = ++_profileEpoch;
    final ui = ref.read(profileBootstrapUiProvider.notifier);

    if (manualRetry) {
      _diag.resetOrigin();
      _diag.mark('AUTH_RETRY_START');
    } else {
      _diag.resetOrigin();
      _diag.mark('AUTH_BOOT_START');
    }

    ui.resetForBootstrap();
    _diag.mark('AUTH_FIREBASE_READY');

    Object? lastError;
    AppFailure? lastFailure;

    for (var attempt = 1; attempt <= _maxBootstrapAttempts; attempt++) {
      if (epoch != _profileEpoch) {
        return;
      }

      if (attempt > 1) {
        ui.setAutoRetrying();
        _diag.mark(
          'AUTH_BOOT_RETRY',
          extra: {'attempt': attempt, 'maxAttempts': _maxBootstrapAttempts},
        );
        await Future<void>.delayed(_autoRetryDelay);
        if (epoch != _profileEpoch) {
          return;
        }
      }

      try {
        _diag.mark('AUTH_REGISTER_START');
        final profile = await _resolveProfile(uid: user.uid).timeout(
          _bootstrapAttemptTimeout,
          onTimeout: () {
            throw const AppFailure.timeout(
              message: 'Profile bootstrap timed out.',
            );
          },
        );
        _diag.mark('AUTH_REGISTER_OK');
        _diag.mark('AUTH_ME_OK');

        if (epoch != _profileEpoch) {
          return;
        }

        if (!profile.isActive || profile.banned) {
          _logger.warning(
            'Account disabled by server; clearing session',
            metadata: {'op': 'resolve_profile'},
          );
          ref.read(sessionUserProfileProvider.notifier).clear();
          ui.clear();
          await _authRepository.logout();
          if (epoch == _profileEpoch) {
            state = AuthStatus.unauthenticated;
          }
          return;
        }

        ref.read(sessionUserProfileProvider.notifier).setProfile(profile);
        ui.clear();
        state = profile.profileComplete
            ? AuthStatus.authenticatedReady
            : AuthStatus.onboardingRequired;
        _diag.mark('AUTH_BOOT_COMPLETE');
        if (manualRetry) {
          _diag.mark('AUTH_RETRY_COMPLETE');
        }
        return;
      } on AppFailure catch (failure) {
        lastFailure = failure;
        lastError = failure;
        _logBootstrapFailure(failure, attempt: attempt);
        if (!_shouldAutoRetry(failure) || attempt >= _maxBootstrapAttempts) {
          break;
        }
      } on TimeoutException catch (e) {
        lastError = e;
        _diag.markFailure(
          'AUTH_BOOT_TIMEOUT',
          classification: 'timeout',
        );
        if (attempt >= _maxBootstrapAttempts) {
          break;
        }
      } catch (e) {
        lastError = e;
        _diag.markFailure(
          'AUTH_BOOT_ERROR',
          classification: e.runtimeType.toString(),
        );
        if (attempt >= _maxBootstrapAttempts) {
          break;
        }
      }
    }

    if (epoch != _profileEpoch) {
      return;
    }

    final message = lastFailure?.userMessage ??
        'Could not reach Ora. Check your connection and try again.';
    ui.setFailure(message);
    state = AuthStatus.authenticated;
    _diag.markFailure(
      'AUTH_BOOT_ERROR',
      classification: lastFailure?.runtimeType.toString() ??
          lastError.runtimeType.toString(),
    );
  }

  void _logBootstrapFailure(AppFailure failure, {required int attempt}) {
    final marker = switch (failure) {
      NetworkFailure() => 'AUTH_REGISTER_FAILED',
      TimeoutFailure() => 'AUTH_BOOT_TIMEOUT',
      UnauthorizedFailure() => 'AUTH_TOKEN_FAILED',
      _ => 'AUTH_ME_FAILED',
    };
    _diag.markFailure(
      marker,
      classification: failure.runtimeType.toString(),
      httpStatus: _httpStatus(failure),
    );
    _logger.warning(
      'Profile bootstrap failed',
      metadata: {
        'op': 'resolve_profile',
        'attempt': attempt,
        'failure': failure.runtimeType.toString(),
      },
    );
  }

  int? _httpStatus(AppFailure failure) => switch (failure) {
        NetworkFailure(:final statusCode) => statusCode,
        ServerFailure(:final statusCode) => statusCode,
        _ => null,
      };

  bool _shouldAutoRetry(AppFailure failure) => switch (failure) {
        NetworkFailure() => true,
        TimeoutFailure() => true,
        ServerFailure() => true,
        _ => false,
      };

  /// Re-runs register + /me (splash recovery after a failed bootstrap).
  ///
  /// Holds [AuthStatus.authenticated] until the server answers so the guard
  /// cannot grant home. Does not throw — splash owns retry UX.
  Future<void> retryProfileBootstrap() async {
    final user = await _authRepository.getCurrentUser();
    if (user == null) {
      state = AuthStatus.unauthenticated;
      return;
    }
    state = AuthStatus.authenticated;
    await _bootstrapProfile(user, manualRetry: true);
  }

  /// Applies a server-returned [UserProfile] (e.g. PATCH `/auth/profile`).
  ///
  /// Prefer this after a successful profile mutation so navigation does not
  /// depend on a second `/me` round-trip that can fail with a connection error
  /// even though Firestore already has `profileComplete=true`.
  ///
  /// Does not forge readiness — [profile.profileComplete] is server-derived.
  Future<void> applyCanonicalProfile(UserProfile profile) async {
    await _applyServerProfile(profile, epoch: ++_profileEpoch);
  }

  /// Reloads canonical `GET /v1/auth/me` after a profile mutation.
  ///
  /// Does not register again, does not move to splash first, and does not
  /// forge [AuthStatus.authenticatedReady]. Failures propagate so callers
  /// that require a fresh `/me` can retry without leaving the form.
  Future<void> refreshCanonicalProfile() async {
    final user = await _authRepository.getCurrentUser();
    if (user == null) {
      state = AuthStatus.unauthenticated;
      throw const AppFailure.sessionExpired();
    }

    final epoch = ++_profileEpoch;
    final profile = await _authRepository.getUserProfile(uid: user.uid);
    if (epoch != _profileEpoch) {
      return;
    }
    await _applyServerProfile(profile, epoch: epoch);
  }

  Future<void> _applyServerProfile(
    UserProfile profile, {
    required int epoch,
  }) async {
    if (epoch != _profileEpoch) {
      return;
    }

    if (!profile.isActive || profile.banned) {
      _logger.warning(
        'Account disabled by server; clearing session',
        metadata: {'op': 'apply_profile'},
      );
      ref.read(sessionUserProfileProvider.notifier).clear();
      ref.read(profileBootstrapUiProvider.notifier).clear();
      await _authRepository.logout();
      if (epoch == _profileEpoch) {
        state = AuthStatus.unauthenticated;
      }
      return;
    }

    ref.read(sessionUserProfileProvider.notifier).setProfile(profile);
    ref.read(profileBootstrapUiProvider.notifier).clear();
    state = profile.profileComplete
        ? AuthStatus.authenticatedReady
        : AuthStatus.onboardingRequired;
  }

  /// Called after profile fetch confirms full readiness.
  void setAuthenticatedReady() => state = AuthStatus.authenticatedReady;

  /// Called when profile exists but onboarding steps remain.
  void setOnboardingRequired() => state = AuthStatus.onboardingRequired;

  /// Called on logout.
  void clearSession() {
    ref.read(sessionUserProfileProvider.notifier).clear();
    ref.read(profileBootstrapUiProvider.notifier).clear();
    state = AuthStatus.unauthenticated;
  }
}
