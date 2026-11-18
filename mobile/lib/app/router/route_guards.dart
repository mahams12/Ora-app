import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/di/providers.dart';
import '../../features/auth/presentation/view_models/auth_view_state.dart';
import '../../features/auth/presentation/view_models/session_user_profile.dart';
import 'routes.dart';

/// Enforces auth-based route protection.
///
/// Guard logic (from Phase 2 / 2A / Slice L):
///   unknown / authenticated → stay on splash (session or /me in flight)
///   unauthenticated         → phone entry (OTP only with session)
///   onboardingRequired      → onboarding
///   authenticatedReady      → home (or stay on protected paths)
///   /driver/*               → approved driver only (server /me role gate)
///
/// Client navigation cannot bypass auth; the guard always reads the
/// authoritative [AuthStatus] from the Riverpod graph.
class AuthRouteGuard {
  const AuthRouteGuard(this._ref);

  final Ref _ref;

  String? redirect(GoRouterState routerState) {
    final authStatus = _ref.read(authStateNotifierProvider);
    // Compare on the path only: a deep link may carry a query string and must
    // still be matched against the known routes.
    final location = routerState.uri.path;

    final isOnAuth = location.startsWith('/auth');
    final isOnOnboarding = location == AppRoutes.onboarding;
    final isOnSplash = location == AppRoutes.splash;
    final isOnDriver =
        location == AppRoutes.driverHome ||
        location.startsWith('${AppRoutes.driverHome}/');

    return switch (authStatus) {
      // Session restore / Firebase init still in flight.
      AuthStatus.unknown => isOnSplash ? null : AppRoutes.splash,

      // Firebase signed in; GET /v1/auth/me (profile bootstrap) still running.
      // Hold splash — never grant home until the server decides.
      AuthStatus.authenticated => isOnSplash ? null : AppRoutes.splash,

      // Not signed in — force to phone entry unless the requested auth screen
      // is legitimately reachable.
      AuthStatus.unauthenticated => _redirectForUnauthenticated(location),

      // Signed in but profile incomplete — onboarding only.
      AuthStatus.onboardingRequired =>
        isOnOnboarding ? null : AppRoutes.onboarding,

      // Server confirmed profileComplete — allow home; leave auth screens.
      // Driver shell requires approved driver from session /me profile.
      // activeMode='driver' restores the last-used mode after restart.
      AuthStatus.authenticatedReady => () {
        if (isOnAuth || isOnOnboarding || isOnSplash) {
          return _restoredModeHome();
        }
        if (isOnDriver && !_isApprovedDriver()) {
          return AppRoutes.home;
        }
        return _partnerRouteGate(location);
      }(),
    };
  }

  /// Per-role gates for partner posting + registration routes.
  ///
  /// Posting dashboards require the matching approved vendor application in
  /// the server /me profile; anything else (none/pending/rejected/
  /// suspended) bounces to home where the partner sheet shows the real
  /// state. Registration routes disappear for approved users (sent to their
  /// dashboard) and are unreachable while pending or suspended. Deep links
  /// and typed-in URLs hit the same guard.
  String? _partnerRouteGate(String location) {
    final profile = _ref.read(sessionUserProfileProvider);

    const postingRoutes = <String, String>{
      AppRoutes.vendorHome: 'service',
      AppRoutes.logisticsVendorHome: 'cargo',
      AppRoutes.rentalVendorHome: 'rental',
    };
    for (final entry in postingRoutes.entries) {
      if (location == entry.key || location.startsWith('${entry.key}/')) {
        return profile?.isApprovedVendor(entry.value) == true
            ? null
            : AppRoutes.home;
      }
    }

    const registrationRoutes = <String, String>{
      AppRoutes.cargoRegistration: 'cargo',
      AppRoutes.rentalRegistration: 'rental',
      AppRoutes.serviceVendorRegistration: 'service',
    };
    for (final entry in registrationRoutes.entries) {
      if (location == entry.key) {
        return switch (profile?.vendorStatusFor(entry.value)) {
          'approved' => _dashboardFor(entry.value),
          'pending' || 'suspended' => AppRoutes.home,
          _ => null, // never applied or rejected → form reachable
        };
      }
    }

    // An approved driver never sees the onboarding form again.
    if (location == AppRoutes.driverRegistration &&
        profile?.isApprovedDriver == true) {
      return AppRoutes.driverHome;
    }
    return null;
  }

  String _dashboardFor(String type) => switch (type) {
    'cargo' => AppRoutes.logisticsVendorHome,
    'rental' => AppRoutes.rentalVendorHome,
    _ => AppRoutes.vendorHome,
  };

  bool _isApprovedDriver() {
    final profile = _ref.read(sessionUserProfileProvider);
    return profile?.isApprovedDriver == true;
  }

  /// Landing route after auth bootstrap: driver mode restores the driver
  /// shell; everyone else (and non-approved accounts) lands on passenger home.
  String _restoredModeHome() {
    final profile = _ref.read(sessionUserProfileProvider);
    if (profile?.activeMode == 'driver' && profile?.isApprovedDriver == true) {
      return AppRoutes.driverHome;
    }
    return AppRoutes.home;
  }

  /// The OTP screen is only reachable while an OTP session is in flight.
  ///
  /// Without this check a deep link, or a back-stack entry restored after the
  /// process was killed, would open the OTP screen with no session — leaving a
  /// dead-end screen that cannot verify anything.
  String? _redirectForUnauthenticated(String location) {
    if (location == AppRoutes.otpEntry) {
      return _hasActiveOtpSession() ? null : AppRoutes.phoneEntry;
    }
    return location.startsWith('/auth') ? null : AppRoutes.phoneEntry;
  }

  bool _hasActiveOtpSession() =>
      _carriesOtpSession(_ref.read(authViewModelProvider));

  /// Whether [state] holds the OTP session needed by the OTP screen.
  ///
  /// [AuthFlowError] is unwrapped so that a rejected code keeps the user on the
  /// OTP screen to read the error, instead of bouncing back to phone entry.
  static bool _carriesOtpSession(AuthFlowState? state) => switch (state) {
    AuthFlowOtpSent() => true,
    AuthFlowVerifyingOtp() => true,
    AuthFlowResendingOtp() => true,
    AuthFlowResendCooldown() => true,
    AuthFlowError(:final previousState) => _carriesOtpSession(previousState),
    _ => false,
  };
}
