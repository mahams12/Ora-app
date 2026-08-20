import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/views/otp_entry_view.dart';
import '../../features/auth/presentation/views/phone_entry_view.dart';
import '../../features/auth/presentation/views/splash_view.dart';
import '../../features/onboarding/presentation/views/onboarding_placeholder_view.dart';
import '../../features/passenger/presentation/views/home_shell_view.dart';
import 'route_guards.dart';
import 'routes.dart';

/// Creates the app-level [GoRouter].
///
/// The router is built once and held by [appRouterProvider].  Route guards
/// require a [Ref] to read auth state reactively.  We accept an optional
/// [initialLocation] override for testing.
GoRouter createAppRouter({
  String initialLocation = AppRoutes.splash,
  Ref? ref,
}) {
  final guard = ref != null ? AuthRouteGuard(ref) : null;

  return GoRouter(
    initialLocation: initialLocation,
    // Redirect is called on every navigation; it reads the current AuthStatus
    // from Riverpod and returns a redirect path when required.
    redirect: guard != null
        ? (context, state) => guard.redirect(state)
        : (context, state) => null,
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        name: 'splash',
        builder: (context, state) => const SplashView(),
      ),

      // ── Auth flow ────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.phoneEntry,
        name: 'phone-entry',
        builder: (context, state) => const PhoneEntryView(),
      ),
      GoRoute(
        path: AppRoutes.otpEntry,
        name: 'otp-entry',
        builder: (context, state) => const OtpEntryView(),
      ),

      // ── Onboarding ───────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.onboarding,
        name: 'onboarding',
        builder: (context, state) => const OnboardingPlaceholderView(),
      ),

      // ── Protected home ───────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.home,
        name: 'home',
        builder: (context, state) => const HomeShellView(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('Route not found: ${state.uri}'),
      ),
    ),
  );
}
