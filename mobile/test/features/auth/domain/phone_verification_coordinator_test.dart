import 'package:flutter_test/flutter_test.dart';
import 'package:ora/features/auth/domain/entities/auth_user.dart';
import 'package:ora/features/auth/domain/entities/phone_verification_result.dart';
import 'package:ora/features/auth/domain/phone_verification_coordinator.dart';

void main() {
  const user = AuthUser(
    uid: 'uid-1',
    phoneNumber: '+923001234567',
    isEmailVerified: false,
  );

  test('codeSent completes with the real verification id', () async {
    final coordinator = PhoneVerificationCoordinator(
      phoneE164: '+923001234567',
      signInWithCredential: (_) async => user,
    );

    coordinator.onCodeSent('real-verification-id');
    final result = await coordinator.future;

    expect(result, isA<PhoneCodeSent>());
    expect(
      (result as PhoneCodeSent).session.sessionId,
      'real-verification-id',
    );
    expect(result.session.sessionId, isNot('auto'));
  });

  test('auto-verify signs in with the supplied credential', () async {
    Object? received;
    final coordinator = PhoneVerificationCoordinator(
      phoneE164: '+923001234567',
      signInWithCredential: (credential) async {
        received = credential;
        return user;
      },
    );

    const credential = Object();
    await coordinator.onAutoVerified(credential);
    final result = await coordinator.future;

    expect(identical(received, credential), isTrue);
    expect(result, isA<PhoneAutoSignedIn>());
    expect((result as PhoneAutoSignedIn).user.uid, 'uid-1');
  });

  test('late auto-verify after codeSent still signs in', () async {
    var signIns = 0;
    final coordinator = PhoneVerificationCoordinator(
      phoneE164: '+923001234567',
      signInWithCredential: (_) async {
        signIns++;
        return user;
      },
    );

    coordinator.onCodeSent('vid-1');
    await coordinator.future;
    await coordinator.onAutoVerified(Object());

    expect(signIns, 1);
    expect(coordinator.isCompleted, isTrue);
  });

  test('timeout uses the Firebase verification id, never "auto"', () async {
    final coordinator = PhoneVerificationCoordinator(
      phoneE164: '+923001234567',
      signInWithCredential: (_) async => user,
    );

    coordinator.onAutoRetrievalTimeout('timeout-vid');
    final result = await coordinator.future;

    expect((result as PhoneCodeSent).session.sessionId, 'timeout-vid');
  });

  test('failure completes the future with the error', () async {
    final coordinator = PhoneVerificationCoordinator(
      phoneE164: '+923001234567',
      signInWithCredential: (_) async => user,
    );

    coordinator.onFailed(StateError('firebase failed'));

    await expectLater(coordinator.future, throwsA(isA<StateError>()));
  });
}
