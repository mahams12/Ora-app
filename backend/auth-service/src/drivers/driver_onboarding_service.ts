import type { Firestore } from 'firebase-admin/firestore';
import type { AuthenticatedCaller } from '../types';
import { loadActor } from '../rides/eligibility';
import { RideDomainError } from '../rides/types';
import { DriverDomainError } from './types';

const USERS = 'users';
const DRIVERS = 'drivers';

export const DRIVER_VEHICLE_TYPES = [
  'bike',
  'car',
  'auto',
  'other',
] as const;
export type DriverVehicleType = (typeof DRIVER_VEHICLE_TYPES)[number];

const MAX_FIELD_LEN = 64;

export interface DriverOnboardingInput {
  caller: AuthenticatedCaller;
  vehicleType: unknown;
  vehicleModel: unknown;
  plateNumber: unknown;
  homeCity: unknown;
}

function optionalString(value: unknown, field: string): string | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string' || value.trim().length > MAX_FIELD_LEN) {
    throw new DriverDomainError(
      'VALIDATION_ERROR',
      400,
      `${field} must be a string of at most ${MAX_FIELD_LEN} characters.`,
    );
  }
  const trimmed = value.trim();
  return trimmed === '' ? null : trimmed;
}

/**
 * Driver onboarding (Switch to Driver first-time flow).
 *
 * Idempotent: submitting again while pending/approved returns the current
 * status without rewriting anything. Suspended drivers keep their suspension
 * — onboarding never lifts it. Approval itself remains an ops action that
 * sets role='driver' + driverStatus='approved' out-of-band; this endpoint
 * only ever moves 'none' → 'pending'.
 *
 * Creates/merges drivers/{uid} with availabilityState='offline' — an
 * applicant must never become discoverable before approval.
 */
export class DriverOnboardingService {
  constructor(private readonly db: Firestore) {}

  async submit(input: DriverOnboardingInput): Promise<{
    httpStatus: number;
    body: { data: { driverStatus: string; pending: boolean } };
  }> {
    const vehicleType = optionalString(input.vehicleType, 'vehicleType');
    if (
      vehicleType == null ||
      !(DRIVER_VEHICLE_TYPES as readonly string[]).includes(vehicleType)
    ) {
      throw new DriverDomainError(
        'VALIDATION_ERROR',
        400,
        `vehicleType must be one of: ${DRIVER_VEHICLE_TYPES.join(', ')}.`,
      );
    }
    const vehicleModel = optionalString(input.vehicleModel, 'vehicleModel');
    const plateNumber = optionalString(input.plateNumber, 'plateNumber');
    const homeCity = optionalString(input.homeCity, 'homeCity');

    let actor;
    try {
      actor = await loadActor(this.db, input.caller.uid);
    } catch (err) {
      if (err instanceof RideDomainError) {
        throw new DriverDomainError(err.code, err.httpStatus, err.message);
      }
      throw err;
    }

    const ref = this.db.collection(USERS).doc(actor.uid);
    const driverRef = this.db.collection(DRIVERS).doc(actor.uid);
    const nowIso = new Date().toISOString();

    const status = await this.db.runTransaction(async (tx) => {
      // All reads before any write (Firestore transaction constraint).
      const snap = await tx.get(ref);
      const driverSnap = await tx.get(driverRef);
      if (!snap.exists) {
        throw new DriverDomainError(
          'FORBIDDEN',
          403,
          'User profile does not exist. Call POST /v1/auth/register.',
        );
      }
      const data = snap.data() ?? {};
      if (data.isActive === false || data.banned === true) {
        throw new DriverDomainError(
          'ACCOUNT_DISABLED',
          403,
          'This account is disabled.',
        );
      }
      const current =
        typeof data.driverStatus === 'string' ? data.driverStatus : 'none';
      if (current !== 'none') {
        // Idempotent replay or re-submit — never downgrade or revive.
        return current;
      }
      tx.update(ref, { driverStatus: 'pending', updatedAt: nowIso });

      const vehicle: Record<string, unknown> = { type: vehicleType };
      if (vehicleModel != null) vehicle.model = vehicleModel;
      if (plateNumber != null) vehicle.plateNumber = plateNumber;
      const driverPatch: Record<string, unknown> = {
        driverId: actor.uid,
        userId: actor.uid,
        vehicle,
        onboardingSubmittedAt: nowIso,
        updatedAt: nowIso,
      };
      if (homeCity != null) driverPatch.homeCity = homeCity;
      if (!driverSnap.exists) {
        driverPatch.availabilityState = 'offline';
        driverPatch.createdAt = nowIso;
        tx.set(driverRef, driverPatch);
      } else {
        tx.update(driverRef, driverPatch);
      }
      return 'pending';
    });

    return {
      httpStatus: 200,
      body: { data: { driverStatus: status, pending: status === 'pending' } },
    };
  }
}
