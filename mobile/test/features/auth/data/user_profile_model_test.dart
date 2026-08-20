import 'package:flutter_test/flutter_test.dart';
import 'package:ora/features/auth/data/models/user_profile_model.dart';

/// Response contract: `docs/architecture-final/04-api-contracts.md` §23.
void main() {
  Map<String, dynamic> body({
    String? role = 'passenger',
    bool isActive = true,
    bool banned = false,
    bool? profileComplete,
  }) =>
      <String, dynamic>{
        'uid': 'uid-1',
        'phoneNumber': '+923001234567',
        'role': role,
        'isActive': isActive,
        'banned': banned,
        if (profileComplete != null) 'profileComplete': profileComplete,
      };

  group('profileComplete is server-derived', () {
    test('is read verbatim when the server says true', () {
      final profile =
          UserProfileModel.fromJson(body(profileComplete: true)).toDomain();

      expect(profile.profileComplete, isTrue);
    });

    test('is read verbatim when the server says false', () {
      // A complete-looking payload must still be incomplete if the server
      // says so — the client does not own the completeness rule.
      final profile =
          UserProfileModel.fromJson(body(profileComplete: false)).toDomain();

      expect(profile.profileComplete, isFalse);
    });

    test('is not inferred from role, isActive and banned', () {
      // These are exactly the inputs the old client-side rule used.
      final profile = UserProfileModel.fromJson(
        body(role: 'passenger', isActive: true, banned: false),
      ).toDomain();

      expect(
        profile.profileComplete,
        isFalse,
        reason: 'an absent flag must not be reconstructed from other fields',
      );
    });

    test('fails closed to false when the field is absent', () {
      final profile = UserProfileModel.fromJson(body()).toDomain();

      expect(profile.profileComplete, isFalse);
    });
  });

  group('server-authoritative claims are carried through unchanged', () {
    test('role and driverStatus pass into the domain entity', () {
      final json = body(profileComplete: true)
        ..['driverStatus'] = 'approved'
        ..['role'] = 'driver';

      final profile = UserProfileModel.fromJson(json).toDomain();

      expect(profile.role, 'driver');
      expect(profile.driverStatus, 'approved');
    });

    test('banned and inactive states are preserved', () {
      final profile = UserProfileModel.fromJson(
        body(isActive: false, banned: true, profileComplete: true),
      ).toDomain();

      expect(profile.banned, isTrue);
      expect(profile.isActive, isFalse);
    });
  });
}
