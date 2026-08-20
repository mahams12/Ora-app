import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/config/app_config.dart';
import '../../app/config/environment.dart';
import '../../core/errors/failure_mapper.dart';
import '../../core/logging/app_logger.dart';
import '../../core/network/api_client.dart';
import '../../core/network/auth_token_provider.dart';
import '../../core/network/network_config.dart';
import '../../core/security/app_check_token_provider.dart';
import '../../core/security/firebase_app_check_bootstrap.dart';
import '../../core/storage/local_storage.dart';
import '../../core/storage/secure_storage.dart';
import '../../features/auth/data/data_sources/app_config_local_data_source.dart';
import '../../features/auth/data/data_sources/auth_remote_data_source.dart';
import '../../features/auth/data/data_sources/firebase_auth_data_source.dart';
import '../../features/auth/data/repositories/app_config_repository_impl.dart';
import '../../features/auth/data/repositories/auth_repository_impl.dart';
import '../../features/auth/domain/repositories/app_config_repository.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import '../../features/auth/domain/use_cases/get_app_bootstrap_use_case.dart';
import '../../features/auth/domain/use_cases/get_current_user_use_case.dart';
import '../../features/auth/domain/use_cases/logout_use_case.dart';
import '../../features/auth/domain/use_cases/refresh_session_use_case.dart';
import '../../features/auth/domain/use_cases/request_otp_use_case.dart';
import '../../features/auth/domain/use_cases/resend_otp_use_case.dart';
import '../../features/auth/domain/use_cases/resolve_auth_profile_use_case.dart';
import '../../features/auth/domain/use_cases/restore_session_use_case.dart';
import '../../features/auth/domain/use_cases/verify_otp_use_case.dart';
import '../../features/auth/presentation/view_models/auth_state_notifier.dart';
import '../../features/auth/presentation/view_models/auth_view_model.dart';
import '../../features/auth/presentation/view_models/auth_view_state.dart';
import '../../features/auth/presentation/view_models/splash_view_model.dart';
import '../../features/auth/presentation/view_models/splash_view_state.dart';
import '../../features/onboarding/presentation/view_models/onboarding_view_model.dart';
import '../../features/onboarding/presentation/view_models/onboarding_view_state.dart';

// ── Environment / Config ──────────────────────────────────────────────────────

/// Active environment — overridden in tests or via `--dart-define=ORA_ENV=...`.
final environmentProvider = Provider<AppEnvironment>(
  (ref) => environmentFromString(
    const String.fromEnvironment('ORA_ENV', defaultValue: 'development'),
  ),
);

final appConfigProvider = Provider<AppConfig>(
  (ref) => AppConfig.fromEnvironment(ref.watch(environmentProvider)),
);

// ── Logging ───────────────────────────────────────────────────────────────────

final appLoggerProvider = Provider<AppLogger>(
  (ref) => ConsoleAppLogger(),
);

// ── Errors ────────────────────────────────────────────────────────────────────

final failureMapperProvider = Provider<FailureMapper>(
  (ref) => const FailureMapper(),
);

// ── Storage ───────────────────────────────────────────────────────────────────

/// Production secure storage (Keychain / Keystore).
final secureStorageProvider = Provider<SecureStorage>(
  (ref) => FlutterSecureStorageImpl(),
);

final localStorageProvider = Provider<LocalStorage>(
  (ref) => InMemoryLocalStorage(),
);

// ── Auth token provider ───────────────────────────────────────────────────────

/// Supplies bearer tokens for the Dio interceptor.
///
/// Uses [FirebaseAuthTokenProvider] in production.  Tests can override with
/// [NoAuthTokenProvider] or a mock.
final authTokenProviderProvider = Provider<AuthTokenProvider>((ref) {
  // Build the token provider so it delegates to FirebaseAuth.
  // The firebase data source manages the actual call.
  return FirebaseAuthTokenProvider(
    getIdToken: (forceRefresh) async {
      try {
        return await FirebaseAuth.instance.currentUser
            ?.getIdToken(forceRefresh);
      } catch (_) {
        return null;
      }
    },
  );
});

// ── Network ───────────────────────────────────────────────────────────────────

final networkConfigProvider = Provider<NetworkConfig>(
  (ref) {
    final config = ref.watch(appConfigProvider);
    return NetworkConfig(
      baseUrl: config.apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      enableRequestLogging: !config.environment.isProduction,
    );
  },
);

final appCheckTokenProviderProvider = Provider<AppCheckTokenProvider>((ref) {
  final config = ref.watch(appConfigProvider);
  if (!config.appCheckEnabled) {
    return const NoAppCheckTokenProvider();
  }
  return FirebaseAppCheckTokenProvider();
});

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    config: ref.watch(networkConfigProvider),
    authTokenProvider: ref.watch(authTokenProviderProvider),
    appCheckTokenProvider: ref.watch(appCheckTokenProviderProvider),
    logger: ref.watch(appLoggerProvider),
    failureMapper: ref.watch(failureMapperProvider),
  ),
);

// ── Firebase Auth data source ─────────────────────────────────────────────────

final firebaseAuthDataSourceProvider = Provider<FirebaseAuthDataSource>(
  (ref) => FirebaseAuthDataSource(
    failureMapper: ref.watch(failureMapperProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);

// ── Auth remote data source ───────────────────────────────────────────────────

final authRemoteDataSourceProvider = Provider<AuthRemoteDataSource>(
  (ref) => AuthRemoteDataSource(ref.watch(apiClientProvider)),
);

// ── Auth repository ───────────────────────────────────────────────────────────

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepositoryImpl(
    firebaseDataSource: ref.watch(firebaseAuthDataSourceProvider),
    remoteDataSource: ref.watch(authRemoteDataSourceProvider),
    secureStorage: ref.watch(secureStorageProvider),
    apiClient: ref.watch(apiClientProvider),
    failureMapper: ref.watch(failureMapperProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);

// ── Auth use cases ────────────────────────────────────────────────────────────

final requestOtpUseCaseProvider = Provider<RequestOtpUseCase>(
  (ref) => RequestOtpUseCase(ref.watch(authRepositoryProvider)),
);

final verifyOtpUseCaseProvider = Provider<VerifyOtpUseCase>(
  (ref) => VerifyOtpUseCase(ref.watch(authRepositoryProvider)),
);

final resendOtpUseCaseProvider = Provider<ResendOtpUseCase>(
  (ref) => ResendOtpUseCase(ref.watch(authRepositoryProvider)),
);

final restoreSessionUseCaseProvider = Provider<RestoreSessionUseCase>(
  (ref) => RestoreSessionUseCase(ref.watch(authRepositoryProvider)),
);

final refreshSessionUseCaseProvider = Provider<RefreshSessionUseCase>(
  (ref) => RefreshSessionUseCase(ref.watch(authRepositoryProvider)),
);

final logoutUseCaseProvider = Provider<LogoutUseCase>(
  (ref) => LogoutUseCase(ref.watch(authRepositoryProvider)),
);

final getCurrentUserUseCaseProvider = Provider<GetCurrentUserUseCase>(
  (ref) => GetCurrentUserUseCase(ref.watch(authRepositoryProvider)),
);

final resolveAuthProfileUseCaseProvider = Provider<ResolveAuthProfileUseCase>(
  (ref) => ResolveAuthProfileUseCase(ref.watch(authRepositoryProvider)),
);

// ── Auth ViewModels / state ───────────────────────────────────────────────────

/// Global authentication status — used by route guards.
final authStateNotifierProvider =
    NotifierProvider<AuthStateNotifier, AuthStatus>(
  AuthStateNotifier.new,
);

/// OTP flow ViewModel.
final authViewModelProvider =
    NotifierProvider<AuthViewModel, AuthFlowState>(
  AuthViewModel.new,
);

// ── Onboarding ────────────────────────────────────────────────────────────────

/// Placeholder onboarding ViewModel — owns the auth-state transition so the
/// onboarding View never navigates or decides completeness itself.
final onboardingViewModelProvider =
    NotifierProvider<OnboardingViewModel, OnboardingViewState>(
  OnboardingViewModel.new,
);

// ── Bootstrap (Phase 1 unchanged) ────────────────────────────────────────────

final appConfigLocalDataSourceProvider = Provider<AppConfigLocalDataSource>(
  (ref) => AppConfigLocalDataSource(ref.watch(appConfigProvider)),
);

final appConfigRepositoryProvider = Provider<AppConfigRepository>(
  (ref) => AppConfigRepositoryImpl(ref.watch(appConfigLocalDataSourceProvider)),
);

final getAppBootstrapUseCaseProvider = Provider<GetAppBootstrapUseCase>(
  (ref) => GetAppBootstrapUseCase(ref.watch(appConfigRepositoryProvider)),
);

final splashViewModelProvider =
    NotifierProvider<SplashViewModel, SplashViewState>(
  SplashViewModel.new,
);
