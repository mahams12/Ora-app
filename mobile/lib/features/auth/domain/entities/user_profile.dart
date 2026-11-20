/// Minimal user profile loaded from the Firestore `users/{uid}` document
/// immediately after successful authentication.
///
/// Only fields needed by the auth/onboarding flow are included here.
/// Full profile editing belongs in a later feature phase.
class UserProfile {
  const UserProfile({
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

  final String uid;
  final String phoneNumber;
  final String? displayName;

  /// Server-authoritative role: 'passenger' | 'driver' | 'admin'.
  final String? role;

  /// Server-authoritative driver status (relevant only for driver role).
  final String? driverStatus;

  /// Server-authoritative operating mode (Switch to Driver):
  /// 'passenger' | 'driver'. Restored after app restart from GET /v1/auth/me.
  final String? activeMode;

  /// Base64 image data URL (`data:image/...;base64,...`) set via profile edit.
  final String? avatarData;

  final bool isActive;
  final bool banned;

  /// Server-authoritative partner applications: vendor type ('cargo' |
  /// 'rental' | 'service') → status ('pending' | 'approved' | 'rejected' |
  /// 'suspended'). Absent key = never applied. Mirrors the driver gate —
  /// posting dashboards require status == 'approved'.
  final Map<String, String> vendorApplications;

  /// True when the backend user document exists AND minimum required fields
  /// for ride flows are populated.  Derived server-side; never inferred from
  /// local storage alone.
  final bool profileComplete;

  /// UI/router gate only — backend still enforces driver eligibility.
  /// Never set by the client; values come from GET /v1/auth/me.
  bool get isApprovedDriver =>
      role == 'driver' && driverStatus == 'approved';

  /// Status for a partner application of [type] ('cargo' | 'rental' |
  /// 'service'), or null when never applied.
  String? vendorStatusFor(String type) => vendorApplications[type];

  /// UI/router gate only — posting dashboards require an approved
  /// application from GET /v1/auth/me.
  bool isApprovedVendor(String type) =>
      vendorApplications[type] == 'approved';
}
