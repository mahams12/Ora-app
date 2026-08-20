import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:flutter_test/flutter_test.dart';
import 'package:ora/core/errors/app_failure.dart';
import 'package:ora/core/errors/failure_mapper.dart';

void main() {
  const mapper = FailureMapper();

  group('FailureMapper.fromFirebaseAuthException', () {
    AppFailure map(String code) => mapper.fromFirebaseAuthException(
          FirebaseAuthException(code: code),
        );

    test('invalid-phone-number → InvalidPhoneFailure', () {
      expect(map('invalid-phone-number'), isA<InvalidPhoneFailure>());
    });

    test('invalid-verification-code → InvalidOtpFailure', () {
      expect(map('invalid-verification-code'), isA<InvalidOtpFailure>());
    });

    test('code-expired → OtpExpiredFailure', () {
      expect(map('code-expired'), isA<OtpExpiredFailure>());
    });

    test('session-expired → OtpExpiredFailure', () {
      expect(map('session-expired'), isA<OtpExpiredFailure>());
    });

    test('too-many-requests → TooManyAttemptsFailure', () {
      expect(map('too-many-requests'), isA<TooManyAttemptsFailure>());
    });

    test('user-disabled → AccountDisabledFailure', () {
      expect(map('user-disabled'), isA<AccountDisabledFailure>());
    });

    test('user-token-expired → SessionExpiredFailure', () {
      expect(map('user-token-expired'), isA<SessionExpiredFailure>());
    });

    test('network-request-failed → NetworkFailure', () {
      expect(map('network-request-failed'), isA<NetworkFailure>());
    });

    test('unknown code → UnknownFailure', () {
      expect(map('some-other-code'), isA<UnknownFailure>());
    });
  });

  group('AppFailure.userMessage — auth variants', () {
    test('InvalidPhoneFailure has readable message', () {
      const f = AppFailure.invalidPhone();
      expect(f.userMessage, contains('phone'));
    });

    test('OtpCooldownFailure with remaining includes seconds', () {
      const f = AppFailure.otpCooldown(remaining: Duration(seconds: 25));
      expect(f.userMessage, contains('25'));
    });

    test('TooManyAttemptsFailure has readable message', () {
      const f = AppFailure.tooManyAttempts();
      expect(f.userMessage, contains('Too many'));
    });

    test('AccountDisabledFailure has readable message', () {
      const f = AppFailure.accountDisabled();
      expect(f.userMessage, contains('disabled'));
    });

    test('SessionExpiredFailure has readable message', () {
      const f = AppFailure.sessionExpired();
      expect(f.userMessage, contains('expired'));
    });
  });
}
