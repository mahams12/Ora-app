import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ora/app/di/providers.dart';
import 'package:ora/app/router/routes.dart';
import 'package:ora/app/theme/theme.dart';
import 'package:ora/features/auth/domain/entities/user_profile.dart';
import 'package:ora/features/auth/presentation/view_models/auth_state_notifier.dart';
import 'package:ora/features/auth/presentation/view_models/auth_view_state.dart';
import 'package:ora/features/auth/presentation/view_models/session_user_profile.dart';
import 'package:ora/features/driver/domain/driver_onboarding_application.dart';
import 'package:ora/features/driver/domain/repositories/driver_onboarding_repository.dart';
import 'package:ora/features/driver/presentation/views/driver_registration_view.dart';

class _FakeOnboardingRepository implements DriverOnboardingRepository {
  _FakeOnboardingRepository(this.result);

  final DriverOnboardingResult result;
  final applications = <DriverOnboardingApplication>[];

  @override
  Future<DriverOnboardingResult> submit(
    DriverOnboardingApplication application,
  ) async {
    applications.add(application);
    return result;
  }
}

class _ProfileNotifier extends SessionUserProfileNotifier {
  _ProfileNotifier(this.profile);
  final UserProfile profile;

  @override
  UserProfile? build() => profile;
}

class _AuthNotifier extends AuthStateNotifier {
  _AuthNotifier(this.profile);
  final UserProfile profile;

  @override
  AuthStatus build() => AuthStatus.authenticatedReady;

  @override
  Future<void> refreshCanonicalProfile() async {
    ref.read(sessionUserProfileProvider.notifier).setProfile(profile);
  }
}

Widget _app({
  required UserProfile profile,
  required _FakeOnboardingRepository repository,
}) {
  final router = GoRouter(
    initialLocation: AppRoutes.driverRegistration,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (_, __) => const Scaffold(body: Text('Home target')),
      ),
      GoRoute(
        path: AppRoutes.driverHome,
        builder: (_, __) => const Scaffold(body: Text('Driver home target')),
      ),
      GoRoute(
        path: AppRoutes.driverRegistration,
        builder: (_, __) => const DriverRegistrationView(),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      driverOnboardingRepositoryProvider.overrideWithValue(repository),
      sessionUserProfileProvider.overrideWith(() => _ProfileNotifier(profile)),
      authStateNotifierProvider.overrideWith(() => _AuthNotifier(profile)),
    ],
    child: MaterialApp.router(theme: OraTheme.dark(), routerConfig: router),
  );
}

UserProfile _profile(String status) => UserProfile(
  uid: 'u1',
  phoneNumber: '+923001234567',
  displayName: 'Ayesha Khan',
  role: status == 'approved' ? 'driver' : 'passenger',
  driverStatus: status,
  profileComplete: true,
);

Future<void> _enter(WidgetTester tester, String key, String value) async {
  final field = find.byKey(ValueKey('driver-$key'));
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
}

Future<void> _tapVisible(WidgetTester tester, String label) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  final button = find.text(label).last;
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  final target = find.byKey(ValueKey(key));
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _fillApplication(WidgetTester tester) async {
  await _enter(tester, 'cnic-number', '3520212345678');
  await _enter(tester, 'home-city', 'Lahore');
  await _tapVisible(tester, 'Continue');
  await _enter(tester, 'license-number', 'LHR-123456');
  await _tapKey(tester, 'driver-license-expiry');
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
  await _tapVisible(tester, 'Continue');
  await _tapKey(tester, 'driver-category-zip');
  await _enter(tester, 'vehicle-make', 'Toyota');
  await _enter(tester, 'vehicle-model', 'Corolla');
  await _enter(tester, 'vehicle-year', '2024');
  await _enter(tester, 'vehicle-color', 'White');
  await _enter(tester, 'plate-number', 'LEA-1234');
  await _tapVisible(tester, 'Continue');
  await tester.ensureVisible(
    find.byKey(const ValueKey('driver-confirm-details')),
  );
  await _tapKey(tester, 'driver-confirm-details');
  await _tapVisible(tester, 'Submit application');
}

void main() {
  testWidgets('validates Personal, Licence, Vehicle, and Review steps', (
    tester,
  ) async {
    final repo = _FakeOnboardingRepository(
      const DriverOnboardingResult(driverStatus: 'pending', approved: false),
    );
    await tester.pumpWidget(_app(profile: _profile('none'), repository: repo));
    await tester.pumpAndSettle();

    await _tapVisible(tester, 'Continue');
    expect(find.text('Enter a valid 13-digit CNIC.'), findsOneWidget);
    expect(find.text('Home city must be 2–64 characters.'), findsOneWidget);

    await _enter(tester, 'cnic-number', '3520212345678');
    await _enter(tester, 'home-city', 'Lahore');
    await _tapVisible(tester, 'Continue');
    await _tapVisible(tester, 'Continue');
    expect(
      find.text('Licence number must be 3–32 characters.'),
      findsOneWidget,
    );
    expect(find.textContaining('Choose a valid date'), findsOneWidget);

    await _enter(tester, 'license-number', 'LHR-123456');
    await _tapKey(tester, 'driver-license-expiry');
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await _tapVisible(tester, 'Continue');
    await _tapVisible(tester, 'Continue');
    expect(find.text('Select a vehicle category.'), findsOneWidget);
    expect(find.text('Vehicle make must be 1–64 characters.'), findsOneWidget);
    expect(find.textContaining('Enter a year from 1980 to'), findsOneWidget);

    await _tapKey(tester, 'driver-category-zip');
    await _enter(tester, 'vehicle-make', 'Toyota');
    await _enter(tester, 'vehicle-model', 'Corolla');
    await _enter(tester, 'vehicle-year', '2024');
    await _enter(tester, 'vehicle-color', 'White');
    await _enter(tester, 'plate-number', 'LEA-1234');
    await _tapVisible(tester, 'Continue');
    await _tapVisible(tester, 'Submit application');
    expect(
      find.text('Confirm these details before submitting.'),
      findsOneWidget,
    );
    expect(repo.applications, isEmpty);
  });

  testWidgets('approved submission refreshes profile and opens driver home', (
    tester,
  ) async {
    const result = DriverOnboardingResult(
      driverStatus: 'approved',
      approved: true,
    );
    final repo = _FakeOnboardingRepository(result);
    await tester.pumpWidget(
      _app(profile: _profile('approved'), repository: repo),
    );
    await tester.pumpAndSettle();
    await _fillApplication(tester);

    expect(find.text('Driver home target'), findsOneWidget);
    expect(repo.applications, hasLength(1));
  });

  testWidgets('pending submission shows receipt sheet then returns Home', (
    tester,
  ) async {
    const result = DriverOnboardingResult(
      driverStatus: 'pending',
      approved: false,
    );
    final repo = _FakeOnboardingRepository(result);
    await tester.pumpWidget(
      _app(profile: _profile('pending'), repository: repo),
    );
    await tester.pumpAndSettle();
    await _fillApplication(tester);

    expect(
      find.text("Application received — we'll notify you after review"),
      findsOneWidget,
    );
    await _tapVisible(tester, 'Back to Home');
    expect(find.text('Home target'), findsOneWidget);
    expect(repo.applications, hasLength(1));
  });
}
