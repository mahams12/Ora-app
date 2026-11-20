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
    this.avatarData,
    this.vendorApplications = const {},
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
      avatarData: json['avatarData'] as String?,
      vendorApplications: _parseVendorApplications(
        json['vendorApplications'],
      ),
    );
  }

  /// Flattens `{type: {status, submittedAt, reviewedAt?}}` → `{type: status}`.
  /// Only the status drives client gating; unknown types/statuses drop.
  static Map<String, String> _parseVendorApplications(Object? raw) {
    if (raw is! Map) return const {};
    const statuses = {'pending', 'approved', 'rejected', 'suspended'};
    final out = <String, String>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String || value is! Map) continue;
      final status = value['status'];
      if (status is String && statuses.contains(status)) {
        out[key] = status;
      }
    }
    return out;
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

  /// Profile photo as a `data:image/...;base64,...` URL (server-capped).
  final String? avatarData;

  /// Partner applications as type → status ('pending'|'approved'|…).
  final Map<String, String> vendorApplications;

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
        avatarData: avatarData,
        vendorApplications: vendorApplications,
      );
}
