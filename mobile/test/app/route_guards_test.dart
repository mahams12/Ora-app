import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ora/app/di/providers.dart';
import 'package:ora/app/router/route_guards.dart';
import 'package:ora/app/router/routes.dart';
import 'package:ora/features/auth/domain/entities/otp_session.dart';
import 'package:ora/features/auth/presentation/view_models/auth_state_notifier.dart';
import 'package:ora/features/auth/presentation/view_models/auth_view_model.dart';
import 'package:ora/features/auth/presentation/view_models/auth_view_state.dart';

/// Pins [AuthStatus] without building the real notifier, which would reach for
/// the auth repository and therefore Firebase.
class _FixedAuthStateNotifier extends AuthStateNotifier {
  _FixedAuthStateNotifier(this._status);

  final AuthStatus _status;

  @override
  AuthStatus build() => _status;
}

/// Pins the OTP flow state without building the real ViewModel.
class _FixedAuthViewModel extends AuthViewModel {
  _FixedAuthViewModel(this._flow);

  final AuthFlowState _flow;

  @override
  AuthFlowState build() => _flow;
}

const _session = OtpSession(
  sessionId: 'vid-1',
  phoneE164: '+923001234567',
  otpState: OtpState.otpSent,
);

void main() {
  /// Resolves [requested] through the real [AuthRouteGuard] and returns the
  /// path the router settled on.
  ///
  /// Trivial route builders are used deliberately: this exercises the guard in
  /// isolation, without the real screens' own navigation side effects.
  Future<String> resolve(
    WidgetTester tester, {
    required String requested,
    required AuthStatus status,
    AuthFlowState flow = const AuthFlowIdle(),
  }) async {
    final container = ProviderContainer(
      overrides: [
        authStateNotifierProvider
            .overrideWith(() => _FixedAuthStateNotifier(status)),
        authViewModelProvider.overrideWith(() => _FixedAuthViewModel(flow)),
      ],
    );
    addTearDown(container.dispose);

    final routerProvider = Provider<GoRouter>((ref) {
      final guard = AuthRouteGuard(ref);
      return GoRouter(
        initialLocation: requested,
        redirect: (context, state) => guard.redirect(state),
        routes: [
          for (final path in <String>[
            AppRoutes.splash,
            AppRoutes.phoneEntry,
            AppRoutes.otpEntry,
            AppRoutes.onboarding,
            AppRoutes.home,
            AppRoutes.rideRequest,
            AppRoutes.rideRequestCreated,
            '/rides/:rideId/offers',
            '/rides/:rideId/active',
            '/rides/:rideId/detail',
            '/rides/:rideId/rate',
            AppRoutes.driverHome,
            AppRoutes.driverRides,
            AppRoutes.driverRide,
            AppRoutes.driverDirectOffer,
          ])
            GoRoute(
              path: path,
              builder: (context, state) => const SizedBox.shrink(),
            ),
        ],
      );
    });

    final router = container.read(routerProvider);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    return router.routerDelegate.currentConfiguration.uri.path;
  }

  group('AuthRouteGuard — unknown (session check in flight)', () {
    testWidgets('holds on splash', (tester) async {
      expect(
        await resolve(tester,
            requested: AppRoutes.splash, status: AuthStatus.unknown),
        AppRoutes.splash,
      );
    });

    testWidgets('pulls any other route back to splash', (tester) async {
      expect(
        await resolve(tester,
            requested: AppRoutes.home, status: AuthStatus.unknown),
        AppRoutes.splash,
      );
    });
  });

  group('AuthRouteGuard — unauthenticated', () {
    testWidgets('protected home redirects to phone entry', (tester) async {
      expect(
        await resolve(tester,
            requested: AppRoutes.home, status: AuthStatus.unauthenticated),
        AppRoutes.phoneEntry,
      );
    });

    testWidgets('onboarding redirects to phone entry', (tester) async {
      expect(
        await resolve(tester,
            requested: AppRoutes.onboarding,
            status: AuthStatus.unauthenticated),
        AppRoutes.phoneEntry,
      );
    });

    testWidgets('phone entry is allowed', (tester) async {
      expect(
        await resolve(tester,
            requested: AppRoutes.phoneEntry,
            status: AuthStatus.unauthenticated),
        AppRoutes.phoneEntry,
      );
    });

    testWidgets('splash redirects to phone entry', (tester) async {
      expect(
        await resolve(tester,
            requested: AppRoutes.splash, status: AuthStatus.unauthenticated),
        AppRoutes.phoneEntry,
      );
    });
  });

  group('AuthRouteGuard — OTP route requires an in-flight OTP session', () {
    testWidgets('deep link to /auth/otp with no session → phone entry',
        (tester) async {
      expect(
        await resolve(
          tester,
          requested: AppRoutes.otpEntry,
          status: AuthStatus.unauthenticated,
          flow: const AuthFlowIdle(),
        ),
        AppRoutes.phoneEntry,
      );
    });

    testWidgets('deep link with a query string is still guarded',
        (tester) async {
      expect(
        await resolve(
          tester,
          requested: '${AppRoutes.otpEntry}?code=123456',
          status: AuthStatus.unauthenticated,
          flow: const AuthFlowIdle(),
        ),
        AppRoutes.phoneEntry,
      );
    });

    testWidgets('reaching /auth/otp while only on phone entry is blocked',
        (tester) async {
      expect(
        await resolve(
          tester,
          requested: AppRoutes.otpEntry,
          status: AuthStatus.unauthenticated,
          flow: const AuthFlowPhoneEntry(),
        ),
        AppRoutes.phoneEntry,
      );
    });

    testWidgets('an OTP request failure does not open the OTP screen',
        (tester) async {
      expect(
        await resolve(
          tester,
          requested: AppRoutes.otpEntry,
          status: AuthStatus.unauthenticated,
          flow: const AuthFlowError(
            message: 'Please enter a valid phone number.',
            previousState: AuthFlowPhoneEntry(),
          ),
        ),
        AppRoutes.phoneEntry,
      );
    });

    testWidgets('an OTP session in flight opens the OTP screen',
        (tester) async {
      expect(
        await resolve(
          tester,
          requested: AppRoutes.otpEntry,
          status: AuthStatus.unauthenticated,
          flow: const AuthFlowOtpSent(session: _session),
        ),
        AppRoutes.otpEntry,
      );
    });

    testWidgets('a rejected code keeps the user on the OTP screen',
        (tester) async {
      // Regression guard: bouncing to phone entry here would hide the error.
      expect(
        await resolve(
          tester,
          requested: AppRoutes.otpEntry,
          status: AuthStatus.unauthenticated,
          flow: const AuthFlowError(
            message: 'Incorrect code. Please try again.',
            previousState: AuthFlowOtpSent(session: _session),
          ),
        ),
        AppRoutes.otpEntry,
      );
    });

    testWidgets('a resend cooldown keeps the user on the OTP screen',
        (tester) async {
      expect(
        await resolve(
          tester,
          requested: AppRoutes.otpEntry,
          status: AuthStatus.unauthenticated,
          flow: const AuthFlowResendCooldown(
            session: _session,
            remaining: Duration(seconds: 20),
          ),
        ),
        AppRoutes.otpEntry,
      );
    });
  });

  group('AuthRouteGuard — onboardingRequired', () {
    testWidgets('home redirects to onboarding', (tester) async {
      expect(
        await resolve(tester,
            requested: AppRoutes.home,
            status: AuthStatus.onboardingRequired),
        AppRoutes.onboarding,
      );
    });

    testWidgets('onboarding is allowed', (tester) async {
      expect(
        await resolve(tester,
            requested: AppRoutes.onboarding,
            status: AuthStatus.onboardingRequired),
        AppRoutes.onboarding,
      );
    });

    testWidgets('auth routes redirect to onboarding', (tester) async {
      expect(
        await resolve(tester,
            requested: AppRoutes.phoneEntry,
            status: AuthStatus.onboardingRequired),
        AppRoutes.onboarding,
      );
    });

    testWidgets('splash redirects to onboarding', (tester) async {
      expect(
        await resolve(tester,
            requested: AppRoutes.splash,
            status: AuthStatus.onboardingRequired),
        AppRoutes.onboarding,
      );
    });
  });

  group('AuthRouteGuard — authenticated (profile bootstrap in flight)', () {
    testWidgets('holds on splash', (tester) async {
      expect(
        await resolve(tester,
            requested: AppRoutes.splash, status: AuthStatus.authenticated),
        AppRoutes.splash,
      );
    });

    testWidgets('pulls home back to splash until /me resolves', (tester) async {
      expect(
        await resolve(tester,
            requested: AppRoutes.home, status: AuthStatus.authenticated),
        AppRoutes.splash,
      );
    });

    testWidgets('pulls auth routes back to splash', (tester) async {
      expect(
        await resolve(tester,
            requested: AppRoutes.phoneEntry, status: AuthStatus.authenticated),
        AppRoutes.splash,
      );
    });

    testWidgets('OTP route is closed once Firebase signed in', (tester) async {
      expect(
        await resolve(
          tester,
          requested: AppRoutes.otpEntry,
          status: AuthStatus.authenticated,
          flow: const AuthFlowOtpSent(session: _session),
        ),
        AppRoutes.splash,
      );
    });
  });

  group('AuthRouteGuard — authenticatedReady', () {
    testWidgets('home is allowed', (tester) async {
      expect(
        await resolve(tester,
            requested: AppRoutes.home,
            status: AuthStatus.authenticatedReady),
        AppRoutes.home,
      );
    });

    testWidgets('onboarding redirects to home', (tester) async {
      expect(
        await resolve(tester,
            requested: AppRoutes.onboarding,
            status: AuthStatus.authenticatedReady),
        AppRoutes.home,
      );
    });

    testWidgets('splash redirects to home', (tester) async {
      expect(
        await resolve(tester,
            requested: AppRoutes.splash,
            status: AuthStatus.authenticatedReady),
        AppRoutes.home,
      );
    });
  });
}
