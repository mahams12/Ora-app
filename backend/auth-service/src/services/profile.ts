import type { UserProfile } from '../types';
import { DisplayNameValidationError } from './display_name';

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

export const AVATAR_DATA_MAX_LENGTH = 400_000;
const AVATAR_DATA_PREFIX = 'data:image/';

/**
 * Validates an avatar payload. Returns the canonical data URL, or null when
 * the caller asked to clear it. Throws on malformed/oversized input.
 */
export function normalizeAvatarData(raw: unknown): string | null {
  if (raw == null) return null;
  if (typeof raw !== 'string') {
    throw new DisplayNameValidationError('avatarData must be a string.');
  }
  const value = raw.trim();
  if (value === '') return null;
  if (
    !value.startsWith(AVATAR_DATA_PREFIX) ||
    value.length > AVATAR_DATA_MAX_LENGTH
  ) {
    throw new DisplayNameValidationError(
      'avatarData must be a data:image/* URL under 400KB.',
    );
  }
  return value;
}

export function toPublicProfile(doc: Record<string, unknown>, uid: string): UserProfile {
  const displayName =
    typeof doc.displayName === 'string' ? doc.displayName : null;
  const avatarData =
    typeof doc.avatarData === 'string' &&
    doc.avatarData.startsWith(AVATAR_DATA_PREFIX) &&
    doc.avatarData.length <= AVATAR_DATA_MAX_LENGTH
      ? doc.avatarData
      : null;
  const role = (doc.role as UserProfile['role']) ?? 'passenger';
  const driverStatus =
    (doc.driverStatus as UserProfile['driverStatus']) ?? 'none';
  const isActive = doc.isActive !== false;
  const banned = doc.banned === true;
  // Legacy docs predate activeMode — they behaved as passenger.
  const activeMode = doc.activeMode === 'driver' ? 'driver' : 'passenger';

  return {
    uid,
    phoneNumber: typeof doc.phoneNumber === 'string' ? doc.phoneNumber : '',
    displayName,
    role,
    driverStatus,
    activeMode,
    isActive,
    banned,
    avatarData,
    profileComplete: deriveProfileComplete({
      role,
      isActive,
      banned,
      displayName,
    }),
  };
}
