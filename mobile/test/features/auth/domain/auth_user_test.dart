import 'package:flutter_test/flutter_test.dart';
import 'package:ora/features/auth/domain/entities/auth_user.dart';

void main() {
  group('AuthUser', () {
    const user = AuthUser(
      uid: 'uid-1',
      phoneNumber: '+923001234567',
      isEmailVerified: false,
      role: 'passenger',
    );

    test('isPassenger returns true for role passenger', () {
      expect(user.isPassenger, isTrue);
    });

    test('isDriver returns false for role passenger', () {
      expect(user.isDriver, isFalse);
    });

    test('isPassenger returns true when role is null', () {
      const u = AuthUser(
        uid: 'uid-2',
        phoneNumber: '+923001234568',
        isEmailVerified: false,
      );
      expect(u.isPassenger, isTrue);
    });

    test('isDriver returns true for role driver', () {
      const u = AuthUser(
        uid: 'uid-3',
        phoneNumber: '+923001234569',
        isEmailVerified: false,
        role: 'driver',
      );
      expect(u.isDriver, isTrue);
    });

    test('copyWith preserves unchanged fields', () {
      final updated = user.copyWith(displayName: 'Ali');
      expect(updated.uid, 'uid-1');
      expect(updated.displayName, 'Ali');
      expect(updated.role, 'passenger');
    });

    test('equality is uid-based', () {
      const u1 = AuthUser(uid: 'uid-1', phoneNumber: '+0', isEmailVerified: false);
      const u2 = AuthUser(uid: 'uid-1', phoneNumber: '+1', isEmailVerified: true);
      expect(u1, equals(u2));
    });
  });
}
