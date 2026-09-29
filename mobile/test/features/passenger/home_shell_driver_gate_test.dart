import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ora/app/di/providers.dart';
import 'package:ora/app/router/route_guards.dart';
import 'package:ora/app/router/routes.dart';
import 'package:ora/app/theme/theme.dart';
import 'package:ora/features/auth/domain/entities/auth_user.dart';
import 'package:ora/features/auth/domain/entities/user_profile.dart';
import 'package:ora/features/auth/domain/use_cases/get_current_user_use_case.dart';
import 'package:ora/features/auth/domain/use_cases/logout_use_case.dart';
import 'package:ora/features/auth/presentation/view_models/auth_state_notifier.dart';
import 'package:ora/features/auth/presentation/view_models/auth_view_state.dart';
import 'package:ora/features/auth/presentation/view_models/session_user_profile.dart';
import 'package:ora/features/driver/presentation/views/driver_shell_view.dart';
import 'package:ora/features/passenger/presentation/views/home_shell_view.dart';
import 'package:ora/features/ride/domain/entities/ride.dart';
import 'package:ora/features/ride/domain/use_cases/ride_use_cases.dart';

class MockLogoutUseCase extends Mock implements LogoutUseCase {}

class MockGetCurrentUserUseCase extends Mock implements GetCurrentUserUseCase {}

class MockListRidesUseCase extends Mock implements ListRidesUseCase {}

class _RefreshingAuthNotifier extends AuthStateNotifier {
  @override
  AuthStatus build() => AuthStatus.authenticatedReady;

  @override
  Future<void> refreshCanonicalProfile() async {
    ref.read(sessionUserProfileProvider.notifier).setProfile(
          const UserProfile(
            uid: 'SRjL7BJgCKTduhtpjtYMRZMq5fD2',
            phoneNumber: '+923012345677',
            displayName: 'Hello',
            role: 'driver',
            driverStatus: 'approved',
            profileComplete: true,
          ),
        );
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, Object?>{});
    registerFallbackValue('');
  });

  testWidgets('Earn on ORA refreshes /me and opens driver shell for approved driver',
      (tester) async {
    final logout = MockLogoutUseCase();
    final getUser = MockGetCurrentUserUseCase();
    final listRides = MockListRidesUseCase();
    when(() => logout()).thenAnswer((_) async {});
    when(() => getUser()).thenAnswer(
      (_) async => const AuthUser(
        uid: 'SRjL7BJgCKTduhtpjtYMRZMq5fD2',
        phoneNumber: '+923012345677',
        isEmailVerified: false,
        displayName: 'Hello',
      ),
    );
    when(
      () => listRides(
        limit: any(named: 'limit'),
        cursor: any(named: 'cursor'),
        status: any(named: 'status'),
        serviceType: any(named: 'serviceType'),
      ),
    ).thenAnswer((_) async => const RideListPage(rides: [], nextCursor: null));

    final container = ProviderContainer(
      overrides: [
        logoutUseCaseProvider.overrideWithValue(logout),
        getCurrentUserUseCaseProvider.overrideWithValue(getUser),
        listRidesUseCaseProvider.overrideWithValue(listRides),
        authStateNotifierProvider.overrideWith(_RefreshingAuthNotifier.new),
      ],
    );
    addTearDown(container.dispose);

    final routerProvider = Provider<GoRouter>((ref) {
      final guard = AuthRouteGuard(ref);
      return GoRouter(
        initialLocation: AppRoutes.home,
        redirect: (context, state) => guard.redirect(state),
        routes: [
          GoRoute(
            path: AppRoutes.home,
            builder: (_, __) => const HomeShellView(),
          ),
          GoRoute(
            path: AppRoutes.driverHome,
            builder: (_, __) => const DriverShellView(),
          ),
        ],
      );
    });

    final router = container.read(routerProvider);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: OraTheme.dark(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Stale passenger session — gate would block without refresh.
    container.read(sessionUserProfileProvider.notifier).setProfile(
          const UserProfile(
            uid: 'SRjL7BJgCKTduhtpjtYMRZMq5fD2',
            phoneNumber: '+923012345677',
            role: 'passenger',
            driverStatus: 'none',
            profileComplete: true,
          ),
        );

    await tester.tap(find.text('Earn on ORA'));
    await tester.pumpAndSettle();

    expect(find.text('Open ride requests'), findsOneWidget);
    expect(find.text('Coming later'), findsNothing);
    expect(find.text('Driver mode'), findsNothing);
  });
}
