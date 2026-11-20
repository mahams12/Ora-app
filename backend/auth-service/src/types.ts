export type DriverStatus = 'none' | 'pending' | 'approved' | 'suspended';
export type UserRole = 'passenger' | 'driver' | 'admin';

/** Partner/vendor roles that post listings. Each is applied + approved independently. */
export type VendorType = 'cargo' | 'rental' | 'service';
export type VendorStatus = 'pending' | 'approved' | 'rejected' | 'suspended';
export interface VendorApplication {
  status: VendorStatus;
  submittedAt: string;
  reviewedAt?: string;
}

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
  /** Base64 JPEG data URL (data:image/jpeg;base64,…). Null when unset. */
  avatarData?: string | null;
  /** Per-type partner applications. Absent key = never applied. */
  vendorApplications?: Partial<Record<VendorType, VendorApplication>>;
}

export interface AuthenticatedCaller {
  uid: string;
  phoneNumber: string | null;
  email: string | null;
  disabled: boolean;
}
