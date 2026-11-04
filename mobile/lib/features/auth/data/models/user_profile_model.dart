import '../../domain/entities/user_profile.dart';

/// Data-transfer object for the `GET /v1/auth/me` response.
///
/// Response contract: `docs/architecture-final/04-api-contracts.md` §23.
class UserProfileModel {
  const UserProfileModel({
    required this.uid,
    required this.phoneNumber,
    this.displayName,
    this.role,
    this.driverStatus,
    this.activeMode,
    this.isActive = true,
    this.banned = false,
    this.profileComplete = false,
  });

  factory UserProfileModel.fromJson(Map<String, dynamic> json) {
    return UserProfileModel(
      uid: json['uid'] as String,
      phoneNumber: json['phoneNumber'] as String? ?? '',
      displayName: json['displayName'] as String?,
      role: json['role'] as String?,
      driverStatus: json['driverStatus'] as String?,
      activeMode: json['activeMode'] as String?,
      isActive: json['isActive'] as bool? ?? true,
      banned: json['banned'] as bool? ?? false,
      // Read verbatim from the server; never recomputed from role/isActive.
      // Absent means false, which routes the user to onboarding rather than
      // granting access to home.
      profileComplete: json['profileComplete'] as bool? ?? false,
    );
  }

  final String uid;
  final String phoneNumber;
  final String? displayName;
  final String? role;
  final String? driverStatus;

  /// Server-authoritative mode (Switch to Driver): 'passenger' | 'driver'.
  final String? activeMode;
  final bool isActive;
  final bool banned;

  /// Server-derived completeness flag. The client does not define the rule.
  final bool profileComplete;

  UserProfile toDomain() => UserProfile(
        uid: uid,
        phoneNumber: phoneNumber,
        displayName: displayName,
        role: role,
        driverStatus: driverStatus,
        activeMode: activeMode,
        isActive: isActive,
        banned: banned,
        profileComplete: profileComplete,
      );
}
