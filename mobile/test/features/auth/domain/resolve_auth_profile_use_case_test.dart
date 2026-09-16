import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ora/core/errors/app_failure.dart';
import 'package:ora/features/auth/domain/entities/user_profile.dart';
import 'package:ora/features/auth/domain/repositories/auth_repository.dart';
import 'package:ora/features/auth/domain/use_cases/resolve_auth_profile_use_case.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late MockAuthRepository repository;
  late ResolveAuthProfileUseCase useCase;

  setUp(() {
    repository = MockAuthRepository();
    useCase = ResolveAuthProfileUseCase(repository);
  });

  test('registers then loads /me', () async {
    const profile = UserProfile(
      uid: 'uid-1',
      phoneNumber: '+923001234567',
      profileComplete: false,
    );
    when(() => repository.registerUser(uid: 'uid-1'))
        .thenAnswer((_) async {});
    when(() => repository.getUserProfile(uid: 'uid-1'))
        .thenAnswer((_) async => profile);

    final result = await useCase(uid: 'uid-1');

    expect(result.profileComplete, isFalse);
    verifyInOrder([
      () => repository.registerUser(uid: 'uid-1'),
      () => repository.getUserProfile(uid: 'uid-1'),
    ]);
  });

  test('register failure is not swallowed before /me', () async {
    when(() => repository.registerUser(uid: 'uid-1'))
        .thenThrow(const AppFailure.network(message: 'register failed'));

    expect(
      () => useCase(uid: 'uid-1'),
      throwsA(isA<NetworkFailure>()),
    );
    verifyNever(() => repository.getUserProfile(uid: any(named: 'uid')));
  });
}
