/// Immutable representation of an authenticated Ora user, derived from
/// the Firebase ID-token claims after server verification.
///
/// The client NEVER determines role, driverStatus, or verification status —
/// those are custom claims set server-side and reflected here read-only.
class AuthUser {
  const AuthUser({
    required this.uid,
    required this.phoneNumber,
    required this.isEmailVerified,
    this.displayName,
    this.role,
    this.driverStatus,
    this.isProfileComplete = false,
  });

  final String uid;
  final String phoneNumber;
  final bool isEmailVerified;
  final String? displayName;

  /// Custom claim: 'passenger' | 'driver' | 'admin' — server-authoritative.
  final String? role;

  /// Custom claim: 'none' | 'pending' | 'approved' | 'suspended' — server only.
  final String? driverStatus;

  /// True when the backend has confirmed the user document exists and the
  /// minimum profile fields required for ride flows are present.
  final bool isProfileComplete;

  bool get isDriver => role == 'driver';
  bool get isPassenger => role == 'passenger' || role == null;

  /// Prefer [UserProfile.isApprovedDriver] from session /me when available.
  /// Firebase AuthUser often has null role claims — do not invent them here.
  bool get isApprovedDriver =>
      role == 'driver' && driverStatus == 'approved';

  /// Copies this user, carrying [role] and [driverStatus] over unchanged.
  ///
  /// Those two fields are deliberately absent from the parameter list: they are
  /// server-authoritative custom claims and there must be no client-side path
  /// that can set them.  A new role can only enter the app through the
  /// constructor, called from the data layer with server-verified values.
  AuthUser copyWith({
    String? displayName,
    bool? isProfileComplete,
  }) =>
      AuthUser(
        uid: uid,
        phoneNumber: phoneNumber,
        isEmailVerified: isEmailVerified,
        displayName: displayName ?? this.displayName,
        role: role,
        driverStatus: driverStatus,
        isProfileComplete: isProfileComplete ?? this.isProfileComplete,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthUser && runtimeType == other.runtimeType && uid == other.uid;

  @override
  int get hashCode => uid.hashCode;
}
