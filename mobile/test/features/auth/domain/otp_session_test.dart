import 'package:flutter_test/flutter_test.dart';
import 'package:ora/features/auth/domain/entities/otp_session.dart';

void main() {
  group('OtpSession', () {
    test('isLocked returns false when lockedUntil is null', () {
      const session = OtpSession(
        sessionId: 's1',
        phoneE164: '+923001234567',
        otpState: OtpState.otpSent,
      );
      expect(session.isLocked, isFalse);
    });

    test('isLocked returns true when lockedUntil is in the future', () {
      final session = OtpSession(
        sessionId: 's1',
        phoneE164: '+923001234567',
        otpState: OtpState.otpLocked,
        lockedUntil: DateTime.now().add(const Duration(minutes: 15)),
      );
      expect(session.isLocked, isTrue);
    });

    test('isLocked returns false when lockedUntil is in the past', () {
      final session = OtpSession(
        sessionId: 's1',
        phoneE164: '+923001234567',
        otpState: OtpState.otpLocked,
        lockedUntil: DateTime.now().subtract(const Duration(seconds: 1)),
      );
      expect(session.isLocked, isFalse);
    });

    test('isCoolingDown returns true when cooldownUntil is in the future', () {
      final session = OtpSession(
        sessionId: 's1',
        phoneE164: '+923001234567',
        otpState: OtpState.otpCooldown,
        cooldownUntil: DateTime.now().add(const Duration(seconds: 30)),
      );
      expect(session.isCoolingDown, isTrue);
    });

    test('cooldownRemaining returns Duration.zero when no cooldown', () {
      const session = OtpSession(
        sessionId: 's1',
        phoneE164: '+923001234567',
        otpState: OtpState.otpSent,
      );
      expect(session.cooldownRemaining, Duration.zero);
    });

    test('copyWith preserves unchanged fields', () {
      const session = OtpSession(
        sessionId: 's1',
        phoneE164: '+923001234567',
        otpState: OtpState.otpSent,
        attemptCount: 2,
      );
      final updated = session.copyWith(attemptCount: 3);
      expect(updated.sessionId, 's1');
      expect(updated.phoneE164, '+923001234567');
      expect(updated.attemptCount, 3);
    });

    // Phase 1.6 §4 constant verification
    test('OtpState enum contains all required states', () {
      expect(
        OtpState.values.map((e) => e.name),
        containsAll([
          'otpRequested',
          'otpSent',
          'otpVerified',
          'otpExpired',
          'otpInvalid',
          'otpLocked',
          'otpCooldown',
        ]),
      );
    });
  });
}
