import type { Firestore } from 'firebase-admin/firestore';
import { RideDomainError } from './types';

export interface EligibleActor {
  uid: string;
  role: string;
  driverStatus: string;
  isActive: boolean;
  banned: boolean;
}

/**
 * Phase 2E eligibility: users/{uid} must be active, not banned.
 * Drivers require role=driver and driverStatus=approved.
 * No Redis/GEO/dispatch membership yet — stub boundary only.
 */
export async function loadActor(
  db: Firestore,
  uid: string,
): Promise<EligibleActor> {
  const snap = await db.collection('users').doc(uid).get();
  if (!snap.exists) {
    throw new RideDomainError(
      'FORBIDDEN',
      403,
      'User profile does not exist. Call POST /v1/auth/register.',
    );
  }
  const data = snap.data() ?? {};
  const actor: EligibleActor = {
    uid,
    role: typeof data.role === 'string' ? data.role : 'passenger',
    driverStatus:
      typeof data.driverStatus === 'string' ? data.driverStatus : 'none',
    isActive: data.isActive !== false,
    banned: data.banned === true,
  };

  if (!actor.isActive || actor.banned) {
    throw new RideDomainError(
      'ACCOUNT_DISABLED',
      403,
      'This account is disabled.',
    );
  }
  return actor;
}

export function assertPassenger(actor: EligibleActor): void {
  // Passengers may also have driver capability later; for create-ride any
  // non-banned active user may act as passenger (Phase 2E).
  void actor;
}

export function assertDriverEligible(actor: EligibleActor): void {
  if (actor.role !== 'driver' || actor.driverStatus !== 'approved') {
    throw new RideDomainError(
      'DRIVER_NOT_ELIGIBLE',
      403,
      'Driver is not approved to offer on rides.',
    );
  }
}
