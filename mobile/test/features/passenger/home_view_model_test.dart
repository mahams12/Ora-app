import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ora/app/di/providers.dart';
import 'package:ora/features/auth/domain/entities/auth_user.dart';
import 'package:ora/features/auth/domain/use_cases/get_current_user_use_case.dart';
import 'package:ora/features/auth/domain/use_cases/logout_use_case.dart';
import 'package:ora/features/passenger/presentation/view_models/home_view_model.dart';

class MockLogoutUseCase extends Mock implements LogoutUseCase {}

class MockGetCurrentUserUseCase extends Mock implements GetCurrentUserUseCase {}

void main() {
  late MockLogoutUseCase logout;
  late MockGetCurrentUserUseCase getCurrentUser;

  setUp(() {
    logout = MockLogoutUseCase();
    getCurrentUser = MockGetCurrentUserUseCase();
    when(() => getCurrentUser()).thenAnswer(
      (_) async => const AuthUser(
        uid: 'u1',
        phoneNumber: '+923001234567',
        isEmailVerified: false,
        displayName: 'Ayesha',
      ),
    );
    when(() => logout()).thenAnswer((_) async {});
  });

  ProviderContainer makeContainer() {
    return ProviderContainer(
      overrides: [
        logoutUseCaseProvider.overrideWithValue(logout),
        getCurrentUserUseCaseProvider.overrideWithValue(getCurrentUser),
      ],
    );
  }

  test('loads greeting from current user', () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    container.read(homeViewModelProvider);
    await container.read(homeViewModelProvider.notifier).loadProfile();

    final state = container.read(homeViewModelProvider);
    expect(state.loadStatus, HomeLoadStatus.ready);
    expect(state.greetingName, 'Ayesha');
    expect(state.avatarInitials, 'A');
  });

  test('falls back greeting when display name missing', () async {
    when(() => getCurrentUser()).thenAnswer(
      (_) async => const AuthUser(
        uid: 'u1',
        phoneNumber: '+923001234567',
        isEmailVerified: false,
      ),
    );
    final container = makeContainer();
    addTearDown(container.dispose);
    await container.read(homeViewModelProvider.notifier).loadProfile();
    expect(container.read(homeViewModelProvider).greetingName, 'there');
  });

  test('never allows ride submission in Slice C', () {
    final container = makeContainer();
    addTearDown(container.dispose);
    final vm = container.read(homeViewModelProvider.notifier);
    expect(vm.canSubmitRideRequest, isFalse);
    expect(vm.bookingUnavailableMessage, contains('pricing'));
  });

  test('logout uses the shared LogoutUseCase once', () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    await container.read(homeViewModelProvider.notifier).logout();

    verify(() => logout()).called(1);
    expect(container.read(homeViewModelProvider).signingOut, isFalse);
  });

  test('ignores a second logout tap while signing out', () async {
    when(() => logout()).thenAnswer((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });

    final container = makeContainer();
    addTearDown(container.dispose);
    final vm = container.read(homeViewModelProvider.notifier);

    await Future.wait([vm.logout(), vm.logout()]);

    verify(() => logout()).called(1);
  });
}
