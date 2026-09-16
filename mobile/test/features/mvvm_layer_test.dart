import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MVVM layer boundaries', () {
    final viewFiles = [
      'lib/features/auth/presentation/views/splash_view.dart',
      'lib/features/auth/presentation/views/phone_entry_view.dart',
      'lib/features/auth/presentation/views/otp_entry_view.dart',
      'lib/features/onboarding/presentation/views/onboarding_view.dart',
      'lib/features/passenger/presentation/views/home_shell_view.dart',
      'lib/features/passenger/presentation/views/passenger_home_view.dart',
      'lib/features/passenger/presentation/views/passenger_unavailable_view.dart',
      'lib/features/ride/presentation/views/ride_request_view.dart',
      'lib/features/ride/presentation/views/ride_request_created_view.dart',
      'lib/features/ride/presentation/views/offers_inbox_view.dart',
      'lib/features/ride/presentation/views/active_ride_view.dart',
      'lib/features/ride/presentation/views/ride_history_view.dart',
      'lib/features/ride/presentation/views/ride_history_detail_view.dart',
      'lib/features/ride/presentation/views/ride_rating_view.dart',
    ];

    const forbiddenImports = [
      'package:dio/',
      'package:firebase_',
      'package:cloud_firestore',
      'package:firebase_database',
      'data/data_sources/',
      'data/repositories/',
    ];

    for (final relativePath in viewFiles) {
      test('$relativePath has no direct infrastructure imports', () {
        final file = File(relativePath);
        expect(file.existsSync(), isTrue);
        final content = file.readAsStringSync();

        for (final forbidden in forbiddenImports) {
          expect(
            content.contains(forbidden),
            isFalse,
            reason: '$relativePath must not import $forbidden',
          );
        }
      });
    }
  });

  test('SplashView does not navigate to home', () {
    final content = File(
      'lib/features/auth/presentation/views/splash_view.dart',
    ).readAsStringSync();
    expect(content.contains('context.go'), isFalse);
    expect(content.contains('AppRoutes.home'), isFalse);
    expect(content.contains("'/home'"), isFalse);
  });

  test('HomeShellView logout does not force a route', () {
    final content = File(
      'lib/features/passenger/presentation/views/home_shell_view.dart',
    ).readAsStringSync();
    // Ride request may use context.push; logout must not navigate.
    expect(content.contains('onSignOut: homeState.signingOut ? null : vm.logout'),
        isTrue);
    expect(content.contains('vm.logout();'), isFalse);
    expect(RegExp(r'logout[\s\S]{0,80}context\.(go|push)').hasMatch(content),
        isFalse);
  });

  test('GoRouter is refreshed, not rebuilt, on auth status changes', () {
    final content = File('lib/app/app.dart').readAsStringSync();
    expect(content, contains('refreshListenable'));
    expect(content, contains('ref.listen(authStateNotifierProvider'));
    expect(
      content.contains(
        'final appRouterProvider = Provider<GoRouter>((ref) {\n'
        '  final refresh = ref.watch(authRouterRefreshProvider);',
      ),
      isTrue,
    );
  });
}
