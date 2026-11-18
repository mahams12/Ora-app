import type { Firestore } from 'firebase-admin/firestore';
import { RideDomainError } from './types';

export interface EligibleActor {
  uid: string;
  role: string;
  driverStatus: string;
  /** users/{uid}.vendorApplications.cargo.status === 'approved'. */
  cargoApproved: boolean;
  isActive: boolean;
  banned: boolean;
}

/**
 * Phase 2E eligibility: users/{uid} must be active, not banned.
 * Drivers require role=driver and driverStatus=approved.
 * No geo-store/dispatch membership yet — stub boundary only.
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
  const apps = (data.vendorApplications ?? {}) as Record<string, unknown>;
  const cargoApp = (apps['cargo'] ?? {}) as Record<string, unknown>;
  const actor: EligibleActor = {
    uid,
    role: typeof data.role === 'string' ? data.role : 'passenger',
    driverStatus:
      typeof data.driverStatus === 'string' ? data.driverStatus : 'none',
    cargoApproved: cargoApp['status'] === 'approved',
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

/**
 * Delivery-pipeline eligibility — approved drivers OR approved logistics
 * (cargo) partners. A cargo approval never grants driver capability and a
 * driver approval never grants the logistics dashboard; this gate only
 * decides who may see/accept realtime delivery-style work.
 */
export function isDeliveryEligible(actor: EligibleActor): boolean {
  return (
    (actor.role === 'driver' && actor.driverStatus === 'approved') ||
    actor.cargoApproved
  );
}

export function assertDeliveryEligible(actor: EligibleActor): void {
  if (!isDeliveryEligible(actor)) {
    throw new RideDomainError(
      'DRIVER_NOT_ELIGIBLE',
      403,
      'Driver or logistics partner is not approved to offer on rides.',
    );
  }
}
