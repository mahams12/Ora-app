export type DriverStatus = 'none' | 'pending' | 'approved' | 'suspended';
export type UserRole = 'passenger' | 'driver' | 'admin';

/**
 * The mode the account is currently operating in (Switch to Driver feature).
 * Distinct from `role`: `role === 'driver'` is a capability granted at
 * approval and is NEVER downgraded by mode switching — an approved driver in
 * passenger mode keeps role='driver' but activeMode='passenger'.
 */
export type ActiveMode = 'passenger' | 'driver';

/** Server-authoritative user document shape for GET /v1/auth/me. */
export interface UserProfile {
  uid: string;
  phoneNumber: string;
  displayName: string | null;
  role: UserRole;
  driverStatus: DriverStatus;
  activeMode: ActiveMode;
  isActive: boolean;
  banned: boolean;
  profileComplete: boolean;
}

export interface AuthenticatedCaller {
  uid: string;
  phoneNumber: string | null;
  email: string | null;
  disabled: boolean;
}
