import type { UserProfile } from './types';

/**
 * Server-owned completeness rule for Phase 2A.
 *
 * Ride fields are not collected yet, so a passenger is "complete" only when
 * they have an active, non-banned account AND a non-empty displayName.
 * Until real onboarding lands, new users remain profileComplete=false.
 */
export function deriveProfileComplete(input: {
  role: string;
  isActive: boolean;
  banned: boolean;
  displayName: string | null;
}): boolean {
  if (!input.isActive || input.banned) {
    return false;
  }
  const name = input.displayName?.trim() ?? '';
  return name.length > 0;
}

export function toPublicProfile(doc: Record<string, unknown>, uid: string): UserProfile {
  const displayName =
    typeof doc.displayName === 'string' ? doc.displayName : null;
  const role = (doc.role as UserProfile['role']) ?? 'passenger';
  const driverStatus =
    (doc.driverStatus as UserProfile['driverStatus']) ?? 'none';
  const isActive = doc.isActive !== false;
  const banned = doc.banned === true;

  return {
    uid,
    phoneNumber: typeof doc.phoneNumber === 'string' ? doc.phoneNumber : '',
    displayName,
    role,
    driverStatus,
    isActive,
    banned,
    profileComplete: deriveProfileComplete({
      role,
      isActive,
      banned,
      displayName,
    }),
  };
}
