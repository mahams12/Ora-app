export type DriverStatus = 'none' | 'pending' | 'approved' | 'suspended';
export type UserRole = 'passenger' | 'driver' | 'admin';

/** Server-authoritative user document shape for GET /v1/auth/me. */
export interface UserProfile {
  uid: string;
  phoneNumber: string;
  displayName: string | null;
  role: UserRole;
  driverStatus: DriverStatus;
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
