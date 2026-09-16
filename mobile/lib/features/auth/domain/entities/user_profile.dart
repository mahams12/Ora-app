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
    this.isActive = true,
    this.banned = false,
    this.profileComplete = false,
  });

  final String uid;
  final String phoneNumber;
  final String? displayName;

  /// Server-authoritative role: 'passenger' | 'driver' | 'admin'.
  final String? role;

  /// Server-authoritative driver status (relevant only for driver role).
  final String? driverStatus;

  final bool isActive;
  final bool banned;

  /// True when the backend user document exists AND minimum required fields
  /// for ride flows are populated.  Derived server-side; never inferred from
  /// local storage alone.
  final bool profileComplete;

  /// UI/router gate only — backend still enforces driver eligibility.
  /// Never set by the client; values come from GET /v1/auth/me.
  bool get isApprovedDriver =>
      role == 'driver' && driverStatus == 'approved';
}
